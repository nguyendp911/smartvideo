import Foundation

/// Deterministic, non-destructive editing for independent music regions.
/// Pure Foundation so conversions, splitting and clipboard semantics are
/// regression-tested before every iOS Simulator and iPhone build.
enum MusicRegionEditMath {
    static func fromLegacy(
        url: URL, fileDuration: Double,
        sourceStart: Double, highlightDuration: Double,
        timelineStart: Double, projectDuration: Double,
        volume: Float, fadeIn: Double, fadeOut: Double,
        frames: [AudioGainKeyframe]
    ) -> SoundEffectClip? {
        guard fileDuration.isFinite, fileDuration >= 0.1,
              projectDuration.isFinite, projectDuration >= 0.1 else {
            return nil
        }
        let start = AudioTimelineMath.clampStart(
            timelineStart, duration: 0.1,
            projectDuration: projectDuration
        )
        let from = min(max(0, sourceStart.isFinite ?
            sourceStart : 0), fileDuration - 0.1)
        let length = min(
            highlightDuration.isFinite && highlightDuration > 0 ?
                highlightDuration : fileDuration - from,
            fileDuration - from,
            projectDuration - start
        )
        guard length >= 0.1 else { return nil }
        var region = SoundEffectClip.create(
            url: url, audioDuration: fileDuration,
            timelineStart: start, timelineEnd: projectDuration
        )
        region.start = start
        region.sourceStart = from
        region.duration = length
        region.volume = AudioAutomationMath.clampGain(volume)
        region.fadeIn = min(3, max(0, fadeIn.isFinite ? fadeIn : 0))
        region.fadeOut = min(3, max(0, fadeOut.isFinite ? fadeOut : 0))
        region.volumeKeyframes = AudioAutomationMath.normalized(frames)
        return region
    }

    static func duplicate(
        _ region: SoundEffectClip, at second: Double,
        projectDuration: Double
    ) -> SoundEffectClip {
        var next = region
        next.id = UUID()
        next.start = AudioTimelineMath.clampStart(
            second, duration: region.duration,
            projectDuration: projectDuration
        )
        // Each new region owns its keyframe IDs: editing the clone
        // cannot select or overwrite a node in its source region.
        next.volumeKeyframes = region.volumeKeyframes.map {
            AudioGainKeyframe(progress: $0.progress, gain: $0.gain)
        }
        return next
    }

    static func split(
        _ region: SoundEffectClip,
        at projectSecond: Double
    ) -> (left: SoundEffectClip, right: SoundEffectClip)? {
        let local = projectSecond - region.start
        guard local.isFinite, region.duration.isFinite,
              local >= 0.1 && region.duration - local >= 0.1 else {
            return nil
        }
        let p = local / region.duration
        var left = region
        var right = region
        left.duration = local
        left.fadeOut = 0
        right.id = UUID()
        right.start = region.start + local
        right.sourceStart = region.sourceStart + local
        right.duration = region.duration - local
        right.fadeIn = 0
        left.volumeKeyframes = AudioAutomationMath.slice(
            region.volumeKeyframes, start: 0, end: p
        )
        right.volumeKeyframes = AudioAutomationMath.slice(
            region.volumeKeyframes, start: p, end: 1
        )
        return (left, right)
    }
}
