import Foundation
import Speech
import AVFoundation

enum AutoCaptionSource: String, CaseIterable, Identifiable {
    case narration = "Thuyết minh"
    case selectedVideo = "Clip video đang chọn"
    var id: String { rawValue }
}

enum AutoCaptionLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi-VN"
    case english = "en-US"
    case chinese = "zh-CN"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }
}

/// Speech recognition of existing media; no microphone recording.
/// On-device is enforced unless the user explicitly permits Apple service.
/// Recognition is limited to one audio segment up to 58 seconds per request.
@MainActor
final class AutoCaptionSpeech {
    private var activeTask: SFSpeechRecognitionTask?

    func recognize(
        fileURL: URL,
        localeIdentifier: String,
        allowAppleService: Bool
    ) async throws -> [SubtitleCue] {
        let status: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { authorization in
                    continuation.resume(returning: authorization)
                }
            }
        } else {
            status = SFSpeechRecognizer.authorizationStatus()
        }
        guard status == .authorized else {
            throw SmartVideoError.invalidMedia(
                "Chưa cấp quyền Nhận diện giọng nói trong Cài đặt iOS."
            )
        }
        guard let recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: localeIdentifier)
        ) else {
            throw SmartVideoError.invalidMedia(
                "iPhone không hỗ trợ ngôn ngữ nhận diện đã chọn."
            )
        }
        let offline = !allowAppleService
        guard !offline || recognizer.supportsOnDeviceRecognition else {
            throw SmartVideoError.invalidMedia(
                "Ngôn ngữ này chưa hỗ trợ nhận diện offline trên iPhone. " +
                "Bạn có thể chọn ngôn ngữ khác hoặc chủ động bật " +
                "«Cho phép dịch vụ Apple» (cần Internet, âm thanh có thể " +
                "được gửi tới Apple)."
            )
        }
        guard recognizer.isAvailable else {
            throw SmartVideoError.invalidMedia(
                "Dịch vụ Speech chưa sẵn sàng. Kiểm tra ngôn ngữ và kết nối."
            )
        }
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = offline

        // Force all recognition callbacks onto the main queue so the
        // continuation is resumed exactly once, even on error.
        recognizer.queue = OperationQueue.main
        let finalResult: SFSpeechRecognitionResult = try await
            withCheckedThrowingContinuation { continuation in
                var finished = false
                self.activeTask = recognizer.recognitionTask(with: request) {
                    result, error in
                    guard !finished else { return }
                    if let error {
                        finished = true
                        self.activeTask = nil
                        continuation.resume(throwing: error)
                    } else if let result, result.isFinal {
                        finished = true
                        self.activeTask = nil
                        continuation.resume(returning: result)
                    }
                }
            }

        let words = finalResult.bestTranscription.segments.compactMap { segment
            -> SubtitleWord? in
            let text = segment.substring.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !text.isEmpty else { return nil }
            return SubtitleWord(
                start: segment.timestamp,
                end: segment.timestamp + max(0.05, segment.duration),
                text: text
            )
        }
        return Self.makeCues(words)
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
    }

    private static func makeCues(_ words: [SubtitleWord]) -> [SubtitleCue] {
        guard !words.isEmpty else { return [] }
        var cues: [SubtitleCue] = []
        var phrases: [SubtitleWord] = []

        func flush() {
            guard let first = phrases.first, let last = phrases.last else {
                return
            }
            let phrase = phrases.map(\.text).joined(separator: " ")
                .replacingOccurrences(of: " ,", with: ",")
                .replacingOccurrences(of: " .", with: ".")
                .replacingOccurrences(of: " !", with: "!")
                .replacingOccurrences(of: " ?", with: "?")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !phrase.isEmpty {
                cues.append(SubtitleCue(
                    start: max(0, first.start),
                    end: max(first.start + 0.14, last.end + 0.07),
                    text: phrase,
                    words: phrases
                ))
            }
            phrases.removeAll(keepingCapacity: true)
        }

        for word in words {
            let previous = phrases.last
            let gap = previous.map { word.start - $0.end } ?? 0
            let duration = phrases.first.map { word.end - $0.start } ?? 0
            let chars = phrases.map { $0.text.count }.reduce(0, +)
            if !phrases.isEmpty &&
                (gap > 0.55 || duration > 3.2 ||
                 phrases.count >= 8 || chars + word.text.count > 44) {
                flush()
            }
            phrases.append(word)
            if word.text.hasSuffix(".") || word.text.hasSuffix("?") ||
               word.text.hasSuffix("!") {
                flush()
            }
        }
        flush()
        return cues
    }

    /// Extract precisely the selected source-video time range to M4A.
    /// The returned URL is ephemeral and must be deleted after recognition.
    static func extractAudio(from clip: TimelineClip) async throws -> URL {
        guard clip.kind == .video else {
            throw SmartVideoError.invalidMedia(
                "Chỉ clip video có tiếng nói mới nhận diện được."
            )
        }
        return try await extractAudio(
            from: clip.fileURL, beginningAt: clip.startTime,
            maximumDuration: clip.duration
        )
    }

    static func extractAudio(
        from fileURL: URL, beginningAt start: Double,
        maximumDuration: Double
    ) async throws -> URL {
        let asset = AVURLAsset(url: fileURL)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw SmartVideoError.invalidMedia(
                "Video không có track âm thanh."
            )
        }
        let duration = try await asset.load(.duration).seconds
        let from = max(0, start)
        let seconds = min(max(0, duration - from),
                          max(0, maximumDuration), 58)
        guard seconds >= 0.5 else {
            throw SmartVideoError.invalidMedia(
                "Đoạn clip có lời nói phải dài tối thiểu 0,5 giây."
            )
        }
        guard let exporter = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SmartVideoError.cannotExport(
                "Không trích xuất được tiếng nói từ video."
            )
        }
        let temporary = MediaStorage.temporaryDirectory
            .appendingPathComponent("AutoCaption-\(UUID().uuidString).m4a")
        exporter.outputURL = temporary
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: from, preferredTimescale: 600),
            duration: CMTime(seconds: seconds, preferredTimescale: 600)
        )
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: temporary)
            throw SmartVideoError.cannotExport(
                exporter.error?.localizedDescription ??
                "Không thể trích âm thanh nguồn video."
            )
        }
        return temporary
    }
}
