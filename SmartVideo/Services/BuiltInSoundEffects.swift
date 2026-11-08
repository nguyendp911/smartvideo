import Foundation
import AVFoundation

/// Six original procedural sound effects, generated once on demand as CAF.
/// No network connection or third-party audio assets are needed.
enum BuiltInSoundEffects {
    static func create(_ preset: BuiltInSoundEffect) throws -> URL {
        let sampleRate = 44_100.0
        let seconds: Double
        switch preset {
        case .whoosh: seconds = 0.95
        case .pop: seconds = 0.30
        case .impact: seconds = 1.10
        case .click: seconds = 0.16
        case .riser: seconds = 1.80
        case .glitch: seconds = 0.70
        }
        let frameCount = AVAudioFrameCount(seconds * sampleRate)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
            channels: 1, interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: frameCount
        ), let samples = buffer.floatChannelData?[0] else {
            throw SmartVideoError.invalidMedia(
                "Không thể tạo bộ đệm âm thanh mẫu."
            )
        }
        buffer.frameLength = frameCount
        var state: UInt32 = 0xA7D18F23
        var phase = 0.0

        for index in 0..<Int(frameCount) {
            let t = Double(index) / sampleRate
            let p = t / seconds
            state = state &* 1664525 &+ 1013904223
            let noise = Double(state & 0xFFFF) / 32768.0 - 1.0
            let frequency: Double
            let amplitude: Double
            let mix: Double
            switch preset {
            case .whoosh:
                frequency = 180 + p * 900
                amplitude = sin(.pi * p) * 0.30
                mix = 0.15
            case .pop:
                frequency = 520 - p * 350
                amplitude = pow(max(0, 1 - p), 4) * 0.55
                mix = 0.28
            case .impact:
                frequency = 110 - p * 70
                amplitude = exp(-p * 5.3) * 0.75
                mix = 0.45
            case .click:
                frequency = 1200
                amplitude = exp(-p * 14) * 0.48
                mix = 0.74
            case .riser:
                frequency = 200 + p * p * 2000
                amplitude = pow(p, 1.2) * pow(max(0, 1 - p), 0.2) * 0.32
                mix = 0.18
            case .glitch:
                frequency = 310 + Double((index / 1200) % 7) * 140
                amplitude = (index / 1800).isMultiple(of: 3) ? 0.12 : 0.38
                mix = 0.28
            }
            phase += 2 * .pi * frequency / sampleRate
            let sample = sin(phase) * (1 - mix) + noise * mix
            samples[index] = Float(
                min(0.9, max(-0.9, sample * amplitude))
            )
        }

        let target = MediaStorage.mediaDirectory.appendingPathComponent(
            "SFX-\(preset.rawValue)-\(UUID().uuidString).caf"
        )
        let file = try AVAudioFile(forWriting: target, settings: format.settings)
        try file.write(from: buffer)
        return target
    }
}
