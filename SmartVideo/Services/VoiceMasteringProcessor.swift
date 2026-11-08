import Foundation
import AVFoundation
import AudioToolbox

/// Offline narration processing. These are DSP effects (not generative AI).
/// Settings persist with a project; only processed audio gets mixed into MP4.
struct VoiceMasteringSettings: Codable, Equatable {
    var bassDB: Double = 0
    var midDB: Double = 0
    var trebleDB: Double = 0
    var compressorThreshold: Double = -20
    var compressorRatio: Double = 2.5
    var noiseGateEnabled: Bool = false
    var noiseGateThreshold: Double = -46
    var outputGainDB: Double = 2
}

enum VoiceMasteringPreset: String, CaseIterable, Identifiable {
    case natural = "Nguyên bản"
    case podcast = "Podcast"
    case warm = "Ấm áp"
    case clear = "Trong sáng"
    case radio = "Radio"

    var id: String { rawValue }

    var settings: VoiceMasteringSettings {
        switch self {
        case .natural:
            return VoiceMasteringSettings(bassDB: 0, midDB: 0, trebleDB: 0,
                                         compressorThreshold: -16,
                                         compressorRatio: 1, noiseGateEnabled: false,
                                         noiseGateThreshold: -46, outputGainDB: 0)
        case .podcast:
            return VoiceMasteringSettings(bassDB: 2.5, midDB: 1.8,
                                         trebleDB: 1.5, compressorThreshold: -23,
                                         compressorRatio: 3, noiseGateEnabled: true,
                                         noiseGateThreshold: -49, outputGainDB: 3)
        case .warm:
            return VoiceMasteringSettings(bassDB: 4, midDB: 0.5,
                                         trebleDB: -1.5, compressorThreshold: -21,
                                         compressorRatio: 2.2, noiseGateEnabled: false,
                                         noiseGateThreshold: -47, outputGainDB: 2)
        case .clear:
            return VoiceMasteringSettings(bassDB: -2, midDB: 3.2,
                                         trebleDB: 3, compressorThreshold: -22,
                                         compressorRatio: 2.5, noiseGateEnabled: true,
                                         noiseGateThreshold: -48, outputGainDB: 2)
        case .radio:
            return VoiceMasteringSettings(bassDB: -6, midDB: 5,
                                         trebleDB: -3, compressorThreshold: -26,
                                         compressorRatio: 4, noiseGateEnabled: true,
                                         noiseGateThreshold: -43, outputGainDB: 2)
        }
    }
}

/// Stream-based processing in fixed PCM chunks, avoiding buffering the
/// entire recording in memory. Per-sample compressor/gate gains are linked
/// across channels to preserve stereo balance.
enum VoiceMasteringProcessor {
    static func process(sourceURL: URL,
                        settings: VoiceMasteringSettings) throws -> URL {
        guard sourceURL.isFileURL,
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SmartVideoError.invalidMedia("Tệp giọng đọc không tồn tại.")
        }

        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        let channels = Int(format.channelCount)
        let rate = format.sampleRate
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              channels >= 1, channels <= 2,
              rate.isFinite, rate >= 8000, rate <= 192000,
              source.length > 0,
              Double(source.length) / rate <= 900 else {
            throw SmartVideoError.invalidMedia(
                "Voice Mastering hỗ trợ mono/stereo PCM tối đa 15 phút."
            )
        }

        let outputURL = MediaStorage.mediaDirectory
            .appendingPathComponent("VoiceMaster-\(UUID().uuidString).caf")
        do {
            let output = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            let bufferSize: AVAudioFrameCount = 8192
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: bufferSize
            ) else {
                throw SmartVideoError.invalidMedia(
                    "Không cấp phát được bộ đệm xử lý giọng."
                )
            }

            let bass = min(12, max(-12, settings.bassDB))
            let mid = min(12, max(-12, settings.midDB))
            let treble = min(12, max(-12, settings.trebleDB))
            var chains = (0..<channels).map { _ in
                FilterChain(sampleRate: rate, bass: bass,
                            mid: mid, treble: treble)
            }

            let threshold = min(-5, max(-40, settings.compressorThreshold))
            let ratio = min(8, max(1, settings.compressorRatio))
            let gateThreshold = pow(10, min(-28, max(-65,
                                        settings.noiseGateThreshold)) / 20)
            let makeup = pow(10, min(10, max(-6,
                                  settings.outputGainDB)) / 20)
            let attack = exp(-1 / (rate * 0.012))
            let release = exp(-1 / (rate * 0.17))
            let gateRise = exp(-1 / (rate * 0.012))
            let gateFall = exp(-1 / (rate * 0.10))
            var envelope = 0.0
            var gate = 1.0
            var gain = 1.0
            var framesProcessed: Int64 = 0

            while source.framePosition < source.length {
                try Task.checkCancellation()
                let remain = source.length - source.framePosition
                let readFrames = AVAudioFrameCount(min(Int64(bufferSize), remain))
                try source.read(into: buffer, frameCount: readFrames)
                let frames = Int(buffer.frameLength)
                guard frames > 0, let channelData = buffer.floatChannelData else { break }

                for frame in 0..<frames {
                    var samples = [Double](repeating: 0, count: channels)
                    var detector = 0.0
                    for channel in 0..<channels {
                        var filter = chains[channel]
                        let input = Double(channelData[channel][frame])
                        let filtered = filter.process(input)
                        chains[channel] = filter
                        samples[channel] = filtered
                        detector = max(detector, abs(filtered))
                    }
                    let coefficient = detector > envelope ? attack : release
                    envelope = coefficient * envelope + (1 - coefficient) * detector
                    let levelDB = 20 * log10(max(0.00001, envelope))
                    let over = max(0, levelDB - threshold)
                    let reductionDB = -(over * (1 - 1 / ratio))
                    let targetGain = pow(10, reductionDB / 20)
                    let gainCoefficient = targetGain < gain ? attack : release
                    gain = gainCoefficient * gain +
                           (1 - gainCoefficient) * targetGain

                    if settings.noiseGateEnabled {
                        // Gentle downward expander, not noise-source separation.
                        let targetGate = detector >= gateThreshold ? 1.0 :
                            max(0.08, pow(max(0, detector / gateThreshold), 0.8))
                        let coefficient = targetGate > gate ? gateRise : gateFall
                        gate = coefficient * gate + (1 - coefficient) * targetGate
                    }

                    for channel in 0..<channels {
                        let sample = samples[channel] * gain * gate * makeup
                        channelData[channel][frame] = Float(
                            min(0.96, max(-0.96, sample))
                        )
                    }
                }
                try output.write(from: buffer)
                framesProcessed += Int64(frames)
            }

            guard framesProcessed > 0 else {
                throw SmartVideoError.invalidMedia(
                    "Tệp thuyết minh không có mẫu âm thanh hợp lệ."
                )
            }
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private struct FilterChain {
        var low: Biquad
        var mid: Biquad
        var high: Biquad

        init(sampleRate: Double, bass: Double,
             mid: Double, treble: Double) {
            low = Biquad.shelf(
                sampleRate: sampleRate, frequency: 155,
                gainDB: bass, high: false
            )
            self.mid = Biquad.peak(
                sampleRate: sampleRate, frequency: 1450,
                gainDB: mid, quality: 0.75
            )
            high = Biquad.shelf(
                sampleRate: sampleRate,
                frequency: min(4900, sampleRate * 0.36),
                gainDB: treble, high: true
            )
        }

        mutating func process(_ sample: Double) -> Double {
            high.process(mid.process(low.process(sample)))
        }
    }

    private struct Biquad {
        var b0: Double
        var b1: Double
        var b2: Double
        var a1: Double
        var a2: Double
        var z1: Double = 0
        var z2: Double = 0

        mutating func process(_ input: Double) -> Double {
            let output = b0 * input + z1
            z1 = b1 * input - a1 * output + z2
            z2 = b2 * input - a2 * output
            return output
        }

        private static func make(_ b0: Double, _ b1: Double, _ b2: Double,
                                 _ a0: Double, _ a1: Double,
                                 _ a2: Double) -> Biquad {
            Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0,
                   a1: a1 / a0, a2: a2 / a0)
        }

        static func peak(sampleRate: Double, frequency: Double,
                         gainDB: Double, quality: Double) -> Biquad {
            let omega = 2 * Double.pi * frequency / sampleRate
            let cosine = cos(omega)
            let alpha = sin(omega) / (2 * quality)
            let amplitude = pow(10, gainDB / 40)
            return make(
                1 + alpha * amplitude, -2 * cosine,
                1 - alpha * amplitude,
                1 + alpha / amplitude, -2 * cosine,
                1 - alpha / amplitude
            )
        }

        static func shelf(sampleRate: Double, frequency: Double,
                          gainDB: Double, high: Bool) -> Biquad {
            let omega = 2 * Double.pi * frequency / sampleRate
            let c = cos(omega)
            let amplitude = pow(10, gainDB / 40)
            let alpha = sin(omega) / 2 * sqrt(2)
            let beta = 2 * sqrt(amplitude) * alpha
            let plus = amplitude + 1
            let minus = amplitude - 1
            if high {
                return make(
                    amplitude * (plus + minus * c + beta),
                    -2 * amplitude * (minus + plus * c),
                    amplitude * (plus + minus * c - beta),
                    plus - minus * c + beta,
                    2 * (minus - plus * c),
                    plus - minus * c - beta
                )
            }
            return make(
                amplitude * (plus - minus * c + beta),
                2 * amplitude * (minus - plus * c),
                amplitude * (plus - minus * c - beta),
                plus + minus * c + beta,
                -2 * (minus + plus * c),
                plus + minus * c - beta
            )
        }
    }
}
