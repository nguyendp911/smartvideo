import Foundation

/// Safe independent export: does not mutate the editable timeline or
/// its overlays, music, captions and keyframes.
enum AIAutoCreatorExporter {
    static func render(
        plan: AIAutoCreationPlan,
        originalClips: [TimelineClip],
        quality: RenderQuality,
        fallbackCanvas: CanvasFormat
    ) async throws -> URL {
        let assembled = try AIAutoCreationAnalyzer.materialize(
            plan: plan, sourceClips: originalClips
        )
        let title = String(plan.title.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(72))
        var titleOverlay: [TextOverlayClip] = []
        if !title.isEmpty, let first = assembled.first {
            var text = TextOverlayClip()
            text.text = title
            text.start = 0
            text.duration = min(2.6, first.renderedDuration)
            text.startY = 0.22
            text.endY = 0.22
            text.fontSize = 46
            text.useBackground = true
            text.strokeWidth = 0.8
            text.shadowOpacity = 0.8
            text.typewriterEnabled = true
            text.typewriterDuration = 0.6
            titleOverlay = [text]
        }
        var metadata = ExportMetadata()
        metadata.title = title
        metadata.description = String(plan.description.prefix(400))
        metadata.genre = plan.style.rawValue

        return try await VideoRenderer().render(
            clips: assembled,
            imageOverlays: [],
            videoOverlays: [],
            textOverlays: titleOverlay,
            mockupOverlays: [],
            soundEffects: [],
            musicRegions: [],
            transition: assembled.count > 1 ? .dissolve : .cut,
            transitionSeconds: plan.style == .reels ? 0.22 : 0.38,
            vfxPresets: [],
            vfxIntensity: 0,
            vfxCoverage: .videoOnly,
            vfxStartTime: 0,
            vfxEndTime: 0,
            musicURL: nil,
            musicVolume: 0,
            musicStartSeconds: 0,
            musicTimelineOffset: 0,
            musicVolumeKeyframes: [],
            voiceVolumeKeyframes: [],
            repeatShortMusic: false,
            musicHighlightDuration: 0,
            voiceoverURL: nil,
            voiceoverOffset: 0,
            voiceoverVolume: 1,
            subtitles: [],
            subtitleAppearance: SubtitleAppearance(),
            subtitleX: 0.5,
            subtitleY: 0.83,
            keepOriginalAudio: true,
            quality: quality,
            canvas: plan.style == .reels ? .portrait : fallbackCanvas,
            contentMode: plan.style == .reels ? .fill : .fit,
            stripMetadata: true,
            exportMetadata: metadata,
            musicFadeIn: 0,
            musicFadeOut: 0
        )
    }
}
