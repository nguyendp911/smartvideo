import Foundation
import AVFoundation

/// Converts written narration to a local uncompressed CAF audio track.
/// Uses the speech voices installed on iOS; no network account is needed.
final class NarrationSpeechWriter {
    private let synthesizer = AVSpeechSynthesizer()

    func render(text: String, language: String = "vi-VN") async throws -> URL {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            throw SmartVideoError.invalidMedia("Nhập nội dung thuyết minh trước.")
        }
        guard words.count <= 5000 else {
            throw SmartVideoError.invalidMedia("Thuyết minh giới hạn 5.000 ký tự mỗi lần.")
        }
        let url = MediaStorage.mediaDirectory
            .appendingPathComponent("GiongDoc-\(UUID().uuidString).caf")
        let utterance = AVSpeechUtterance(string: words)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.48
        utterance.volume = 1.0

        return try await withCheckedThrowingContinuation { continuation in
            var file: AVAudioFile?
            var completed = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer, !completed else { return }
                if pcm.frameLength == 0 {
                    completed = true
                    if file == nil {
                        continuation.resume(throwing: SmartVideoError.invalidMedia(
                            "iOS không xuất được giọng đọc. Kiểm tra tiếng Việt trong cài đặt giọng nói."
                        ))
                    } else {
                        continuation.resume(returning: url)
                    }
                    return
                }
                do {
                    if file == nil {
                        file = try AVAudioFile(forWriting: url, settings: pcm.format.settings)
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
