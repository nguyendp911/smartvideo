import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Hook 3s and Auto Enhance

    func findHook3s(clipID: UUID?) {
        guard !isFindingHook3s,
              let clip = clips.first(where: { $0.id == clipID }),
              clip.kind == .video else {
            errorText = "Hãy chọn clip video dài ít nhất 3 giây."
            return
        }
        let project = projectID
        isFindingHook3s = true
        hook3sSuggestions = []
        hook3sSourceClipID = clip.id
        hook3sStatus = "Vision đang tìm 3 giây có gương mặt, chuyển động và hình ảnh nổi bật…"
        Task {
            defer { isFindingHook3s = false }
            do {
                let candidates = try await Hook3sAnalyzer.suggest(from: clip)
                guard projectID == project,
                      clips.contains(where: { $0.id == clip.id }) else { return }
                hook3sSuggestions = candidates
                hook3sStatus = "Đã gợi ý \(candidates.count) đoạn Hook 3 giây. Chọn trước khi chèn."
            } catch {
                hook3sStatus = ""
                errorText = "Hook 3s: \(error.localizedDescription)"
            }
        }
    }

    /// Inserts an independent 3s teaser while preserving the original video.
    /// Existing timed content is shifted to match the new timeline length.
    @discardableResult
    func insertHook3s(clipID: UUID?, suggestion: Hook3sSuggestion,
                      title: String) -> UUID? {
        guard hook3sSourceClipID == clipID,
              hook3sSuggestions.contains(where: { $0.id == suggestion.id }),
              let index = clips.firstIndex(where: { $0.id == clipID }),
              clips[index].kind == .video else { return nil }
        let source = clips[index]
        let inputStart = source.startTime + suggestion.start
        guard inputStart >= 0,
              inputStart + 3 <= source.originalDuration + 0.02 else {
            errorText = "Khoảng Hook nằm ngoài video gốc."
            return nil
        }
        let oldFirst = clips[0]
        let overlap = transition == .cut ? 0 :
            min(transitionSeconds, 3 * 0.24,
                oldFirst.renderedDuration * 0.24)
        let shift = 3.0 - overlap
        hook3sBackup = HookInsertionBackup(
            clips: clips, subtitles: subtitles,
            text: textOverlays, images: imageOverlays,
            videos: videoOverlays, mockups: mockupOverlays,
            sounds: soundEffects, musicRegions: musicRegions,
            musicOffset: musicTimelineOffset,
            voiceOffset: voiceoverOffset,
            vfxStart: vfxStartTime, vfxEnd: vfxEndTime,
            timelineSecond: timelineSecond
        )
        checkpoint()
        var teaser = source
        teaser.id = UUID()
        teaser.startTime = inputStart
        teaser.duration = 3.0
        teaser.originalDuration = source.originalDuration
        teaser.playbackSpeed = 1
        teaser.speedCurve = []
        teaser.sourceAudioFadeIn = 0
        teaser.sourceAudioFadeOut = min(0.15, teaser.duration / 4)
        clips.insert(teaser, at: 0)
        for i in subtitles.indices {
            subtitles[i].start += shift
            subtitles[i].end += shift
            for j in subtitles[i].words.indices {
                subtitles[i].words[j].start += shift
                subtitles[i].words[j].end += shift
            }
        }
        for i in textOverlays.indices { textOverlays[i].start += shift }
        for i in imageOverlays.indices { imageOverlays[i].start += shift }
        for i in videoOverlays.indices { videoOverlays[i].start += shift }
        for i in mockupOverlays.indices { mockupOverlays[i].start += shift }
        for i in soundEffects.indices { soundEffects[i].start += shift }
        for i in musicRegions.indices { musicRegions[i].start += shift }
        musicTimelineOffset += shift
        voiceoverOffset += shift
        if vfxEndTime > vfxStartTime {
            vfxStartTime += shift
            vfxEndTime += shift
        }
        let trimmedTitle = String(title.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(85))
        if !trimmedTitle.isEmpty {
            var overlay = TextOverlayClip()
            overlay.start = 0
            overlay.duration = 3
            overlay.text = trimmedTitle
            overlay.startY = 0.34
            overlay.endY = 0.34
            overlay.fontSize = 48
            overlay.useBackground = true
            overlay.strokeWidth = 1.2
            overlay.shadowOpacity = 0.75
            overlay.typewriterEnabled = true
            overlay.typewriterDuration = 0.65
            textOverlays.insert(overlay, at: 0)
        }
        timelineSecond = 0
        hook3sSuggestions = []
        hook3sSourceClipID = nil
        hook3sStatus = String(format:
            "Đã chèn Hook 3 giây trước video. Timeline tăng %.2f giây; bản gốc vẫn giữ nguyên.",
            shift)
        return teaser.id
    }

    func undoHook3s() {
        guard let old = hook3sBackup else { return }
        checkpoint()
        clips = old.clips
        subtitles = old.subtitles
        textOverlays = old.text
        imageOverlays = old.images
        videoOverlays = old.videos
        mockupOverlays = old.mockups
        soundEffects = old.sounds
        musicRegions = old.musicRegions
        musicTimelineOffset = old.musicOffset
        voiceoverOffset = old.voiceOffset
        vfxStartTime = old.vfxStart
        vfxEndTime = old.vfxEnd
        timelineSecond = old.timelineSecond
        hook3sBackup = nil
        hook3sStatus = "Đã hoàn tác Hook 3s cùng các mốc thời gian."
    }

    var canUndoHook3s: Bool { hook3sBackup != nil }

    func autoEnhanceClip(clipID: UUID?, strength: Double) {
        guard !isAutoTuningEnhance,
              let clip = clips.first(where: { $0.id == clipID }) else {
            errorText = "Hãy chọn ảnh hoặc video để Auto Enhance."
            return
        }
        let project = projectID
        isAutoTuningEnhance = true
        autoEnhanceStatus = "Đang phân tích độ sáng và tương phản của ảnh mẫu…"
        Task {
            defer { isAutoTuningEnhance = false }
            do {
                let result = try await AutoEnhanceProcessor.recommend(
                    for: clip, strength: strength
                )
                guard projectID == project,
                      let index = clips.firstIndex(where: {
                          $0.id == clip.id
                      }) else { return }
                checkpoint()
                clips[index].autoEnhance = result
                autoEnhanceStatus = "Đã tối ưu ánh sáng, màu, giảm nhiễu và độ nét. Kiểm tra preview trước/sau."
            } catch {
                autoEnhanceStatus = ""
                errorText = "Auto Enhance: \(error.localizedDescription)"
            }
        }
    }

    func setAutoEnhance(_ clipID: UUID, settings: AutoEnhanceSettings) {
        guard let index = clips.firstIndex(where: {
            $0.id == clipID
        }) else { return }
        clips[index].autoEnhance = settings
    }

    func disableAutoEnhance(_ clipID: UUID) {
        guard let index = clips.firstIndex(where: {
            $0.id == clipID
        }) else { return }
        checkpoint()
        clips[index].autoEnhance = .off
        autoEnhanceStatus = "Đã tắt Auto Enhance. Video gốc không thay đổi."
    }
    // MARK: - AI-assisted local video selection

    func suggestVideoHighlights(for clip: TimelineClip) {
        guard clip.kind == .video, !isAnalyzingVideoHighlights else { return }
        isAnalyzingVideoHighlights = true
        analyzedClipID = clip.id
        videoHighlights = []
        let sourceURL = clip.fileURL
        let sourceStart = clip.startTime
        let sourceDuration = clip.duration

        Task {
            defer { isAnalyzingVideoHighlights = false }
            do {
                let highlights = try await Task.detached(priority: .utility) {
                    try await VideoHighlightsAnalyzer.find(
                        in: sourceURL,
                        sourceStart: sourceStart,
                        sourceDuration: sourceDuration
                    )
                }.value
                if analyzedClipID == clip.id {
                    videoHighlights = highlights
                }
            } catch {
                errorText = "Không chọn được video highlight: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func applyVideoHighlights(clipID: UUID, selected: [VideoHighlight]) -> UUID? {
        guard let index = clips.firstIndex(where: { $0.id == clipID }),
              clips[index].kind == .video,
              !selected.isEmpty else { return nil }

        let source = clips[index]
        var replacements: [TimelineClip] = []
        for highlight in selected.sorted(by: { $0.start < $1.start }) {
            var result = source
            result.id = UUID()
            result.startTime = min(
                source.originalDuration,
                max(0, source.startTime + highlight.start)
            )
            result.duration = min(
                highlight.duration,
                max(0, source.originalDuration - result.startTime)
            )
            if result.duration >= 0.1 {
                replacements.append(result)
            }
        }
        guard !replacements.isEmpty else { return nil }
        previousTimeline = clips
        clips.replaceSubrange(index...index, with: replacements)
        analyzedClipID = nil
        videoHighlights = []
        return replacements.first?.id
    }

    func undoHighlights() {
        guard let previousTimeline else { return }
        clips = previousTimeline
        self.previousTimeline = nil
        analyzedClipID = nil
        videoHighlights = []
    }
    // MARK: - Music highlights

    func suggestMusicHighlights() {
        guard let file = musicURL, !isAnalyzingMusicHighlights else { return }
        let length = musicHighlightLength
        musicHighlights = []
        isAnalyzingMusicHighlights = true
        Task {
            defer { isAnalyzingMusicHighlights = false }
            do {
                let suggestions = try await Task.detached(priority: .utility) {
                    try await SmartMusicHighlights.find(in: file, desiredLength: length)
                }.value
                if file == musicURL {
                    musicHighlights = suggestions
                }
            } catch {
                errorText = "Phân tích nhạc thất bại: \(error.localizedDescription)"
            }
        }
    }

    func exportMusicHighlight() {
        guard let url = musicURL, musicHighlightDuration > 0,
              !isExportingMusicHighlight else { return }
        isExportingMusicHighlight = true
        exportedMusicHighlightURL = nil
        let start = musicStartSeconds
        let duration = musicHighlightDuration
        Task {
            defer { isExportingMusicHighlight = false }
            do {
                exportedMusicHighlightURL = try await MusicSegmentExporter.export(
                    inputURL: url, start: start, duration: duration
                )
            } catch {
                errorText = "Không xuất được MP3 highlight: \(error.localizedDescription)"
            }
        }
    }

    func useMusicHighlight(_ highlight: MusicHighlight) {
        guard musicURL != nil else { return }
        musicStartSeconds = min(max(0, highlight.start),
                                max(0, musicDuration - 0.1))
        musicHighlightDuration = min(highlight.duration,
                                     max(0, musicDuration - musicStartSeconds))
        exportedMusicHighlightURL = nil
    }

    func generateAIPublishingVariants(apiKey: String) {
        guard !isGeneratingPublishingVariants else { return }
        let cues = subtitles.sorted { $0.start < $1.start }
            .map(\.text).joined(separator: " ")
        let source = cues.isEmpty ?
            (aiVisualReport?.summary ?? narrationText) : cues
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Cần nhận diện lời nói hoặc phân tích cảnh trước khi tạo bản đăng."
            return
        }
        let models = aiGeminiModels.filter {
            !$0.name.lowercased().contains("tts")
        }
        guard let model = aiGeminiModelName.isEmpty ?
            GeminiDirectAPI.recommended(models) :
            models.first(where: { $0.name == aiGeminiModelName }) else {
            errorText = "Hãy nhận diện model Gemini trước."
            return
        }
        let project = projectID
        let instructions = aiMetadataInstructions
        let language = aiRevoiceLanguage
        let styles = ["TikTok / Reels ngắn gọn",
                      "YouTube hấp dẫn, tối ưu tìm kiếm",
                      "Facebook, gần gũi và tự nhiên"]
        isGeneratingPublishingVariants = true
        aiPublishingVariants = []
        aiMetadataStatus = "Đang tạo các phiên bản nội dung đăng bài…"
        Task {
            defer { isGeneratingPublishingVariants = false }
            do {
                var results: [AIMetadataDraft] = []
                for (i, style) in styles.enumerated() {
                    try Task.checkCancellation()
                    aiMetadataStatus = "Gemini tạo bản \(i + 1)/3: \(style)…"
                    results.append(try await GeminiDirectAPI.generateMetadata(
                        apiKey: apiKey,
                        modelName: model.name,
                        transcript: source,
                        language: language,
                        style: style,
                        instructions: instructions
                    ))
                }
                guard projectID == project else { return }
                aiPublishingVariants = results
                aiMetadataStatus = "Đã tạo 3 phiên bản. Chọn bản để chỉnh sửa hoặc áp dụng."
            } catch {
                aiMetadataStatus = ""
                errorText = "AI Publishing: \(error.localizedDescription)"
            }
        }
    }
}
