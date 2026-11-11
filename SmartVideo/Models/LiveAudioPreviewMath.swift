import Foundation

/// Pure timing and gain maths shared by the live audio monitor and tests.
/// The renderer remains the source of truth for final mixes.
enum LiveAudioPreviewMath {
    static func musicOffset(
        timeline: Double, fileDuration: Double,
        start: Double, highlightDuration: Double, repeats: Bool
    ) -> Double? {
        guard timeline.isFinite, timeline >= 0,
              fileDuration.isFinite, fileDuration > 0.1 else { return nil }
        let from = min(max(0, start.isFinite ? start : 0),
                       max(0, fileDuration - 0.1))
        let available = fileDuration - from
        let segment = highlightDuration.isFinite && highlightDuration > 0
            ? min(available, highlightDuration) : available
        guard segment > 0.05 else { return nil }
        guard repeats || timeline < segment else { return nil }
        return from + (repeats ? timeline.truncatingRemainder(dividingBy: segment)
                               : timeline)
    }

    static func musicEnd(
        timelineEnd: Double, fileDuration: Double,
        start: Double, highlightDuration: Double, repeats: Bool
    ) -> Double {
        guard timelineEnd.isFinite, timelineEnd > 0,
              fileDuration.isFinite, fileDuration > 0 else { return 0 }
        if repeats { return timelineEnd }
        let from = min(max(0, start.isFinite ? start : 0),
                       max(0, fileDuration - 0.1))
        let available = fileDuration - from
        let length = highlightDuration.isFinite && highlightDuration > 0
            ? min(available, highlightDuration) : available
        return min(timelineEnd, length)
    }

    static func regionOffset(
        timeline: Double, regionStart: Double,
        sourceStart: Double, duration: Double
    ) -> Double? {
        guard timeline.isFinite, regionStart.isFinite,
              sourceStart.isFinite, duration.isFinite,
              duration > 0.05 else { return nil }
        let relative = timeline - regionStart
        guard relative >= 0, relative < duration else { return nil }
        return max(0, sourceStart) + relative
    }

    static func envelope(
        timeline: Double, start: Double, duration: Double,
        fadeIn: Double, fadeOut: Double
    ) -> Float {
        guard timeline.isFinite, start.isFinite, duration.isFinite,
              duration > 0.05 else { return 0 }
        let elapsed = timeline - start
        guard elapsed >= 0, elapsed < duration else { return 0 }
        let rise = min(max(0, fadeIn), duration * 0.48)
        let fall = min(max(0, fadeOut), duration * 0.48)
        let up = rise > 0.001 ? min(1, elapsed / rise) : 1
        let down = fall > 0.001
            ? min(1, (duration - elapsed) / fall) : 1
        return Float(max(0, min(up, down)))
    }

    static func musicGain(
        timeline: Double, baseVolume: Float,
        musicEnd: Double, fadeIn: Double, fadeOut: Double,
        narrationStart: Double?, narrationEnd: Double?
    ) -> Float {
        guard timeline >= 0, timeline < musicEnd else { return 0 }
        let base = min(1, max(0, baseVolume))
        let fade = envelope(timeline: timeline, start: 0,
                            duration: musicEnd, fadeIn: fadeIn,
                            fadeOut: fadeOut)
        var duck: Float = 1
        if let narrationStart, let narrationEnd,
           timeline >= narrationStart, timeline < narrationEnd {
            // Matches the renderer's approximate 25% narration duck.
            duck = 0.25
        }
        return base * fade * duck
    }
}
