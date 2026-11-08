import Foundation
import AVFoundation

struct AudioLevelReport {
    let inputRMSDBFS: Double
    let outputRMSDBFS: Double
    let inputPeakDBFS: Double
    let appliedGainDB: Double
    let outputURL: URL
}

/// Two-pass streaming RMS normalizer with sample-peak protection.
/// This is intentionally NOT marketed as BS.1770/EBU R128 LUFS or true-peak.
enum AudioLoudnessNormalizer {
    static func normalize(
        sourceURL: URL,
        targetDBFS: Double,
        maximumSeconds: Double = 900
    ) throws -> AudioLevelReport {
        guard sourceURL.isFileURL,
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw SmartVideoError.invalidMedia("Không tìm thấy file âm thanh cần chuẩn hóa.")
        }

        let source = try AVAudioFile(forReading: sourceURL)
        let format = source.processingFormat
        let channels = Int(format.channelCount)
        let rate = format.sampleRate
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved, channels > 0, channels <= 2,
              rate.isFinite, rate >= 8000, source.length > 0,
              Double(source.length) / rate <= maximumSeconds else {
            throw SmartVideoError.invalidMedia(
                "Chuẩn hóa hỗ trợ PCM mono/stereo, thời lượng tối đa " +
                "\(Int(maximumSeconds / 60)) phút."
            )
        }
        let chunk: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: chunk
        ) else { throw SmartVideoError.cannotCreateWriter }

        var sumSquares: Double = 0
        var sampleCount: Int64 = 0
        var peak: Double = 0

        while source.framePosition < source.length {
            try Task.checkCancellation()
            let framesToRead = AVAudioFrameCount(
                min(Int64(chunk), source.length - source.framePosition)
            )
            try source.read(into: buffer, frameCount: framesToRead)
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            for channel in 0..<channels {
                for frame in 0..<frames {
                    let value = Double(data[channel][frame])
                    sumSquares += value * value
                    peak = max(peak, abs(value))
                }
            }
            sampleCount += Int64(frames * channels)
        }

        guard sampleCount > 0, sumSquares.isFinite else {
            throw SmartVideoError.invalidMedia("Không tìm được mẫu âm thanh hợp lệ.")
        }
        let rms = sqrt(sumSquares / Double(sampleCount))
        guard rms > 0.000001 else {
            throw SmartVideoError.invalidMedia(
                "Âm thanh quá nhỏ hoặc im lặng, không nên tăng âm lượng tự động."
            )
        }
        let inputRMS = 20 * log10(rms)
        let inputPeak = 20 * log10(max(0.000001, peak))
        // Constrain the adjustment to avoid bringing up low-level noise.
        let requestedDB = max(-15, min(12, targetDBFS - inputRMS))
        let desiredGain = pow(10, requestedDB / 20)
        let maximumSafeGain = 0.89125 / max(0.000001, peak)
        let gain = min(desiredGain, maximumSafeGain)
        guard gain.isFinite, gain > 0 else {
            throw SmartVideoError.invalidMedia("Mức tăng âm thanh không hợp lệ.")
        }

        let outputURL = MediaStorage.mediaDirectory.appendingPathComponent(
            "Normalize-\(UUID().uuidString).caf"
        )
        do {
            let output = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            source.framePosition = 0
            while source.framePosition < source.length {
                try Task.checkCancellation()
                let framesToRead = AVAudioFrameCount(
                    min(Int64(chunk), source.length - source.framePosition)
                )
                try source.read(into: buffer, frameCount: framesToRead)
                let frames = Int(buffer.frameLength)
                guard frames > 0, let data = buffer.floatChannelData else { break }
                for channel in 0..<channels {
                    for frame in 0..<frames {
                        let scaled = Double(data[channel][frame]) * gain
                        data[channel][frame] = Float(min(0.89125, max(-0.89125, scaled)))
                    }
                }
                try output.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return AudioLevelReport(
            inputRMSDBFS: inputRMS,
            outputRMSDBFS: inputRMS + 20 * log10(gain),
            inputPeakDBFS: inputPeak,
            appliedGainDB: 20 * log10(gain),
            outputURL: outputURL
        )
    }
}
