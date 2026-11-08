import Foundation
import AVFoundation

/// Voice selection is based on the speech engines installed on this iPhone.
/// A tone preset changes speed/pitch/pauses; it does not create a new AI voice.
enum NarrationTone: String, CaseIterable, Identifiable {
    case natural = "Tự nhiên"
    case warm = "Ấm áp"
    case energetic = "Sôi nổi"
    case storytelling = "Kể chuyện"
    case calm = "Chậm rãi"
    case news = "Bản tin"

    var id: String { rawValue }

    var rate: Float {
        switch self {
        case .natural: return 0.50
        case .warm: return 0.46
        case .energetic: return 0.58
        case .storytelling: return 0.43
        case .calm: return 0.39
        case .news: return 0.53
        }
    }

    var pitch: Float {
        switch self {
        case .natural: return 1.0
        case .warm: return 0.91
        case .energetic: return 1.12
        case .storytelling: return 0.96
        case .calm: return 0.94
        case .news: return 1.02
        }
    }

    var pause: TimeInterval {
        switch self {
        case .storytelling, .calm: return 0.18
        case .news: return 0.08
        default: return 0.04
        }
    }
}

struct NarrationVoiceChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String

    var title: String { "\(name) · \(language)" }

    static var available: [NarrationVoiceChoice] {
        let installed = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("vi") || $0.language.hasPrefix("en") }
            .sorted {
                if $0.language.hasPrefix("vi") != $1.language.hasPrefix("vi") {
                    return $0.language.hasPrefix("vi")
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        return installed.map {
            NarrationVoiceChoice(id: $0.identifier, name: $0.name,
                                 language: $0.language)
        }
    }
}

/// Offline narration export using Apple's installed TTS voices.
final class NarrationSpeechWriter {
    private let synthesizer = AVSpeechSynthesizer()

    func render(text: String,
                voiceIdentifier: String?,
                tone: NarrationTone,
                rateAdjustment: Float,
                pitchAdjustment: Float) async throws -> URL {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            throw SmartVideoError.invalidMedia("Nhập nội dung thuyết minh trước.")
        }
        guard words.count <= 5000 else {
            throw SmartVideoError.invalidMedia("Thuyết minh giới hạn 5.000 ký tự.")
        }

        let url = MediaStorage.mediaDirectory
            .appendingPathComponent("ThuyetMinh-TTS-\(UUID().uuidString).caf")
        let utterance = AVSpeechUtterance(string: words)
        if let voiceIdentifier,
           let selected = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = selected
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        }

        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                             max(AVSpeechUtteranceMinimumSpeechRate,
                                 tone.rate * rateAdjustment))
        utterance.pitchMultiplier = min(2.0, max(0.5,
                                                tone.pitch * pitchAdjustment))
        utterance.postUtteranceDelay = tone.pause
        utterance.volume = 1

        return try await withCheckedThrowingContinuation { continuation in
            var file: AVAudioFile?
            var completed = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, !completed else { return }
                if pcm.frameLength == 0 {
                    completed = true
                    if file == nil {
                        continuation.resume(throwing: SmartVideoError.invalidMedia(
                            "iOS chưa tạo được giọng đọc. Thử đổi giọng hoặc ngôn ngữ."
                        ))
                    } else {
                        continuation.resume(returning: url)
                    }
                    return
                }
                do {
                    if file == nil {
                        file = try AVAudioFile(forWriting: url,
                                               settings: pcm.format.settings)
                    }
                    try file?.write(from: pcm)
                } catch {
                    completed = true
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
