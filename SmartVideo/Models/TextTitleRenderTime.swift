import Foundation

/// Project time for effects burned into the source clip before the final
/// crossfade / scale / canvas composition.
///
/// All source clips are trimmed into an AVMutableComposition starting at t=0
/// before entering AVVideoComposition. This eliminates ambiguity about
/// whether request.compositionTime carries original or relative timestamps.
enum TextTitleRenderTime {
    static func projectSecond(
        clipStart: Double,
        trimmedCompositionSecond: Double,
        playbackSpeed: Double
    ) -> Double {
        let safeStart = clipStart.isFinite ? max(0, clipStart) : 0
        let safeLocal = trimmedCompositionSecond.isFinite ?
            max(0, trimmedCompositionSecond) : 0
        let safeSpeed = playbackSpeed.isFinite ?
            max(0.25, playbackSpeed) : 1
        return safeStart + safeLocal / safeSpeed
    }

    static func intersects(
        titleStart: Double,
        titleDuration: Double,
        clipStart: Double,
        clipDuration: Double
    ) -> Bool {
        guard titleStart.isFinite, titleDuration.isFinite,
              clipStart.isFinite, clipDuration.isFinite,
              titleDuration > 0, clipDuration > 0 else { return false }
        return titleStart < clipStart + clipDuration &&
            titleStart + titleDuration > clipStart
    }
}
