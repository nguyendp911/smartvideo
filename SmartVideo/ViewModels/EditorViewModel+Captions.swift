import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Speech to timed Auto Captions

    func generateAutoCaptions(selectedClipID: UUID?) {
        guard !isGeneratingAutoCaptions, !clips.isEmpty else { return }
        let language = autoCaptionLanguage.rawValue
        let allowApple = allowAppleSpeechService
        let replaceExisting = replaceExistingAutoCaptions

        let audioURL: URL
        let sourceStart: Double
        let sourceLimit: Double
        let timelineOffset: Double
        let speed: Double

        switch autoCaptionSource {
        case .narration:
            guard let voiceoverURL else {
                errorText = "Hãy thêm thuyết minh trước khi tạo Auto Captions."
                return
            }
            audioURL = voiceoverURL
            sourceStart = 0
            sourceLimit = max(0, totalDuration - voiceoverOffset)
            timelineOffset = voiceoverOffset
            speed = 1
        case .selectedVideo:
            guard let index = clips.firstIndex(where: { $0.id == selectedClipID }),
                  clips[index].kind == .video else {
                errorText = "Chọn một clip VIDEO có tiếng nói trên timeline."
                return
            }
            let clip = clips[index]
            audioURL = clip.fileURL
            sourceStart = clip.startTime
            speed = max(0.25, clip.playbackSpeed)
            sourceLimit = clip.duration
            timelineOffset = timelineStart(of: index)
        }

        let processLong = processLongAutoCaptions
        let projectIDAtStart = projectID
        isGeneratingAutoCaptions = true
        autoCaptionStatus = "Đang kiểm tra nguồn âm thanh…"

        Task {
            defer { isGeneratingAutoCaptions = false }
            do {
                let asset = AVURLAsset(url: audioURL)
                let fileLength = try await asset.load(.duration).seconds
                guard fileLength.isFinite, fileLength > sourceStart else {
                    throw SmartVideoError.invalidMedia("Nguồn audio có thời lượng không hợp lệ.")
                }
                // Bound to a maximum of 10 minutes per run. The service
                // is asked to recognize a small independent chunk each time.
                let availableSource = min(
                    max(0, fileLength - sourceStart),
                    max(0, sourceLimit),
                    max(0, (totalDuration - timelineOffset) * speed),
                    processLong ? 600 : 52
                )
                guard availableSource >= 0.5 else {
                    throw SmartVideoError.invalidMedia(
                        "Không có đủ tiếng nói trong phạm vi timeline."
                    )
                }
                let chunkSeconds = 52.0
                let partCount = Int(ceil(availableSource / chunkSeconds))
                var translated = [SubtitleCue]()
                for part in 0..<partCount {
                    try Task.checkCancellation()
                    let localOffset = Double(part) * chunkSeconds
                    let length = min(chunkSeconds, availableSource - localOffset)
                    guard length >= 0.5 else { continue }
                    autoCaptionStatus = "Đoạn \(part + 1)/\(partCount): trích âm thanh…"
                    let temporary = try await AutoCaptionSpeech.extractAudio(
                        from: audioURL,
                        beginningAt: sourceStart + localOffset,
                        maximumDuration: length
                    )
                    // Delete the M4A even if recognition fails.
                    let cues: [SubtitleCue]
                    do {
                        autoCaptionStatus = "Đoạn \(part + 1)/\(partCount): " +
                            "nhận diện \(language)…"
                        cues = try await autoCaptionSpeech.recognize(
                            fileURL: temporary,
                            localeIdentifier: language,
                            allowAppleService: allowApple
                        )
                    } catch {
                        try? FileManager.default.removeItem(at: temporary)
                        throw error
                    }
                    try? FileManager.default.removeItem(at: temporary)
                    for cue in cues {
                        let position = timelineOffset +
                            (localOffset + cue.start) / speed
                        let finish = min(
                            totalDuration,
                            timelineOffset + (localOffset + cue.end) / speed
                        )
                        guard position < totalDuration,
                              finish > position else { continue }
                        let words = cue.words.map { word in
                            SubtitleWord(
                                start: timelineOffset +
                                    (localOffset + word.start) / speed,
                                end: min(
                                    totalDuration,
                                    timelineOffset + (localOffset + word.end) / speed
                                ),
                                text: word.text
                            )
                        }
                        translated.append(SubtitleCue(
                            start: position, end: max(position + 0.10, finish),
                            text: cue.text, words: words
                        ))
                    }
                    autoCaptionStatus = "Đã nhận diện \(part + 1)/\(partCount) " +
                        "đoạn · \(translated.count) câu."
                }
                guard !translated.isEmpty else {
                    throw SmartVideoError.invalidMedia(
                        "Không có lời nói được nhận diện trong phần đã quét."
                    )
                }
                // Do not apply speech to an entirely different project.
                guard projectID == projectIDAtStart else { return }
                if replaceExisting {
                    subtitles = translated
                } else {
                    subtitles.append(contentsOf: translated)
                    subtitles.sort { $0.start < $1.start }
                }
                autoCaptionStatus = "Đã tạo \(translated.count) câu và " +
                    "\(translated.reduce(0) { $0 + $1.words.count }) " +
                    "mốc từ. Hãy kiểm tra và sửa các chỗ nhận diện sai."
            } catch {
                autoCaptionStatus = ""
                errorText = "Auto Captions: \(error.localizedDescription)"
            }
        }
    }

    func addSubtitle() {
        let start = min(totalDuration, (subtitles.last?.end ?? 0))
        let end = min(max(totalDuration, 0.5), start + 3)
        subtitles.append(SubtitleCue(start: start, end: max(start + 0.1, end), text: "Phụ đề mới"))
    }

    func exportSRT() -> URL? {
        do {
            let target = MediaStorage.exportsDirectory
                .appendingPathComponent("SmartVideo-PhuDe-\(UUID().uuidString.prefix(6)).srt")
            try SubtitleFile.makeSRT(subtitles).write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            errorText = "Không tạo được file SRT: \(error.localizedDescription)"
            return nil
        }
    }

    func copyScoped(_ url: URL, fallbackExtension: String) throws -> URL {
        guard url.isFileURL else {
            throw SmartVideoError.invalidMedia("Nguồn âm thanh không phải tệp cục bộ.")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try MediaStorage.copyToMedia(url, fallbackExtension: fallbackExtension)
    }
}
