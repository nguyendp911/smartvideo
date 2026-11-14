import Foundation
import AVFoundation

/// Creates a bounded, offline edit decision list using Vision and
/// the existing highlight, photo-preset and enhancement pipelines.
enum AIAutoCreationAnalyzer {
    static func analyze(
        clips: [TimelineClip],
        style: AIAutoCreationStyle
    ) async throws -> AIAutoCreationPlan {
        guard !clips.isEmpty else {
            throw SmartVideoError.invalidMedia(
                "Hãy nhập ảnh hoặc video trước khi AI dựng.")
        }
        guard clips.count <= 12 else {
            throw SmartVideoError.invalidMedia(
                "AI Auto Creator xử lý tối đa 12 ảnh/video một lần.")
        }
        var decisions: [AIAutoCreationDecision] = []
        var descriptions: [String] = []
        for (index, clip) in clips.enumerated() {
            try Task.checkCancellation()
            guard FileManager.default.fileExists(
                atPath: clip.fileURL.path) else {
                throw SmartVideoError.invalidMedia(
                    "Không tìm thấy tệp gốc: \(clip.filename)")
            }
            if clip.kind == .image {
                let recommendation = try? await PhotoPresetSuggester.suggest(
                    fileURL: clip.fileURL)
                let presetID = recommendation?.presetID ??
                    (style == .cinematic ? "cinematic_photo" : "pastel_soft")
                let summary = recommendation?.reason ??
                    "Ảnh tĩnh: tối ưu sáng và màu nhẹ nhàng"
                let enhancement = (try? await AutoEnhanceProcessor.recommend(
                    for: clip, strength: 0.52)) ?? .off
                decisions.append(AIAutoCreationDecision(
                    id: clip.id, sourceURL: clip.fileURL,
                    kind: .image,
                    photoPresetID: PhotoPresetLibrary.find(presetID) == nil ?
                        nil : presetID,
                    autoEnhance: enhancement,
                    offsetSeconds: 0,
                    duration: style.photoSeconds,
                    description: summary
                ))
                descriptions.append(summary)
            } else {
                let limit = max(1.0, style.videoSeconds)
                var offset = 0.0
                var segment = min(clip.duration, limit)
                var reason = "Video: giữ đoạn quay phù hợp nhịp dựng"
                // The analyzer ranks faces, contrast, motion and saliency;
                // do not claim to detect spoken words or events from audio.
                if clip.duration > limit + 0.5,
                   let highlight = try? await VideoHighlightsAnalyzer.find(
                    in: clip.fileURL, sourceStart: clip.startTime,
                    sourceDuration: clip.duration
                   ).max(by: { $0.score < $1.score }) {
                    offset = min(
                        max(0, highlight.start),
                        max(0, clip.duration - limit))
                    segment = min(limit, clip.duration - offset)
                    reason = "Chọn đoạn nổi bật: " + highlight.reason
                }
                let enhancement = (try? await AutoEnhanceProcessor.recommend(
                    for: clip, strength: 0.58)) ?? .off
                decisions.append(AIAutoCreationDecision(
                    id: clip.id, sourceURL: clip.fileURL,
                    kind: .video, photoPresetID: nil,
                    autoEnhance: enhancement,
                    offsetSeconds: offset,
                    duration: max(0.2, segment),
                    description: reason
                ))
                descriptions.append(reason)
            }
            // Stable ordering matches the order user imported footage.
            _ = index
        }
        let recognized = decisions.compactMap {
            $0.photoPresetID.flatMap(PhotoPresetLibrary.find)
        }
        let headline = recognized.first?.name ??
            (style == .reels ? "Khoảnh khắc đáng nhớ" :
             style == .travel ? "Chuyến đi của chúng ta" :
             "Những thước phim đáng nhớ")
        return AIAutoCreationPlan(
            sourceIDs: clips.map(\.id),
            decisions: decisions,
            style: style,
            title: headline,
            description: String(
                descriptions.prefix(8).joined(separator: ". ").prefix(650))
        )
    }

    static func materialize(
        plan: AIAutoCreationPlan,
        sourceClips: [TimelineClip]
    ) throws -> [TimelineClip] {
        guard plan.sourceIDs == sourceClips.map(\.id),
              plan.decisions.count == sourceClips.count else {
            throw SmartVideoError.invalidMedia(
                "Danh sách media đã thay đổi trong lúc AI dựng.")
        }
        return try zip(sourceClips, plan.decisions).enumerated().map {
            index, pair in
            let original = pair.0
            let edit = pair.1
            guard original.id == edit.id,
                  original.fileURL == edit.sourceURL,
                  original.kind == edit.kind,
                  edit.duration.isFinite, edit.duration > 0.1 else {
                throw SmartVideoError.invalidMedia(
                    "Quyết định dựng không khớp media gốc.")
            }
            var copy = original
            copy.id = UUID()
            copy.autoEnhance = edit.autoEnhance
            copy.speedCurve = []
            copy.playbackSpeed = 1
            if original.kind == .image {
                copy.startTime = 0
                copy.duration = min(8, max(1.2, edit.duration))
                copy.originalDuration = copy.duration
                copy.imageLook = .original
                copy.photoPreset = edit.photoPresetID.flatMap(
                    PhotoPresetLibrary.find)
                copy.photoPresetIntensity = plan.style == .reels ? 0.68 : 0.78
                copy.imageMotion = index.isMultiple(of: 2) ?
                    .zoomIn : .panRight
            } else {
                let safeSourceDuration = max(0.1,
                    original.originalDuration - original.startTime)
                let trim = min(
                    max(0, edit.offsetSeconds),
                    max(0, safeSourceDuration - 0.2))
                let available = max(0.1, safeSourceDuration - trim)
                copy.startTime = original.startTime + trim
                copy.duration = min(available,
                    max(0.2, edit.duration))
                copy.imageLook = plan.style == .cinematic ?
                    .cinematic : .clean
                copy.lookIntensity = plan.style == .cinematic ? 0.38 : 0.18
                // Preserve source audio when possible; no unlicensed music.
                copy.sourceAudioMuted = false
                copy.sourceAudioVolume = 1
            }
            return copy
        }
    }
}
