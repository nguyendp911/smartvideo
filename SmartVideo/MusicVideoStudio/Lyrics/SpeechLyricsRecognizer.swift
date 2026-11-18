import Foundation
import AVFoundation
import Speech

extension MusicVideoStudio {
    /// Anything that can turn audio into timed words. The synchroniser only sees
    /// `[RecognizedWord]`, so a stronger singing-aware / forced-alignment service
    /// can replace Apple Speech without touching the rest of the lyrics engine.
    protocol LyricsRecognizer {
        var name: String { get }
        /// Words with times in seconds of the FILE, between `from` and `to`.
        func recognize(audioURL: URL, from: Double, to: Double, locale: Locale) async throws -> [RecognizedWord]
    }

    enum LyricsRecognitionError: LocalizedError {
        case notAuthorized
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Chưa được cấp quyền nhận diện giọng nói (Cài đặt > ViePN Smart Video)."
            case .unavailable: return "Nhận diện giọng nói không khả dụng cho ngôn ngữ này trên thiết bị."
            case .failed(let reason): return "Nhận diện thất bại: \(reason)"
            }
        }
    }

    /// Apple Speech, in 50 s chunks, on-device when the language supports it.
    /// IMPORTANT: it is built for speech, not singing: timestamps over loud music
    /// are approximate. Use it as a starting point, then refine in the lyrics editor.
    struct SpeechLyricsRecognizer: LyricsRecognizer {
        var name: String { "Apple Speech (thử nghiệm)" }
        static let chunkSeconds = 50.0

        func recognize(audioURL: URL, from: Double, to: Double, locale: Locale) async throws -> [RecognizedWord] {
            let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
            }
            guard status == .authorized else { throw LyricsRecognitionError.notAuthorized }
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { throw LyricsRecognitionError.unavailable }
            let file = try AVAudioFile(forReading: audioURL)
            let rate = file.processingFormat.sampleRate
            var words: [RecognizedWord] = []
            var cursor = max(0, from)
            let end = min(to, Double(file.length) / rate)
            while cursor < end - 0.2 {
                try Task.checkCancellation()
                let chunkEnd = min(end, cursor + Self.chunkSeconds)
                words += try await recognizeChunk(file: file, recognizer: recognizer, from: cursor, to: chunkEnd)
                cursor = chunkEnd
            }
            return words
        }

        private func recognizeChunk(file: AVAudioFile, recognizer: SFSpeechRecognizer, from: Double, to: Double) async throws -> [RecognizedWord] {
            let rate = file.processingFormat.sampleRate
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            file.framePosition = AVAudioFramePosition(from * rate)
            var remaining = AVAudioFramePosition((to - from) * rate)
            while remaining > 0 {
                let count = AVAudioFrameCount(min(remaining, 8192))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { break }
                try file.read(into: buffer, frameCount: count)
                if buffer.frameLength == 0 { break }
                request.append(buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
            request.endAudio()

            let segments: [RecognizedWord] = try await withCheckedThrowingContinuation { continuation in
                var finished = false
                recognizer.recognitionTask(with: request) { result, error in
                    guard !finished else { return }
                    if let result, result.isFinal {
                        finished = true
                        continuation.resume(returning: result.bestTranscription.segments.map {
                            RecognizedWord(text: $0.substring, start: from + $0.timestamp, end: from + $0.timestamp + $0.duration)
                        })
                    } else if let error {
                        finished = true
                        // "No speech detected" is not a failure for a chunk of pure music.
                        let ns = error as NSError
                        if ns.domain == "kAFAssistantErrorDomain", ns.code == 1110 { continuation.resume(returning: []) }
                        else { continuation.resume(throwing: LyricsRecognitionError.failed(error.localizedDescription)) }
                    }
                }
            }
            return segments
        }
    }
}
