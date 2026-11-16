import Foundation

/// Timing math for ripple deletes: when a span [cutStart, cutEnd) of the main
/// timeline disappears, every time-based item after it moves earlier by the
/// span length, and items that overlap the span are trimmed or dropped.
enum RippleMath {
    /// What to do with an item that fully straddles the removed span.
    enum Straddle {
        /// Keep the whole item but shorten it by the span (text, subtitles,
        /// overlays: the same visual content just ends earlier).
        case shrink
        /// Keep only the part before the cut (audio: the removed middle can't
        /// be preserved without splitting the item in two).
        case keepHead
    }

    struct Result: Equatable {
        var start: Double
        var end: Double
        /// Seconds removed from the START of the item (source offset grows).
        var headTrim: Double
    }

    /// nil means the item is removed entirely.
    static func range(
        start s: Double, end e: Double,
        cutStart a: Double, cutEnd b: Double,
        straddle: Straddle = .shrink, minLength: Double = 0.05
    ) -> Result? {
        guard s.isFinite, e.isFinite, a.isFinite, b.isFinite, e > s else {
            return nil
        }
        let length = b - a
        guard length > 0 else { return Result(start: s, end: e, headTrim: 0) }
        let out: Result
        if e <= a {
            out = Result(start: s, end: e, headTrim: 0)
        } else if s >= b {
            out = Result(start: s - length, end: e - length, headTrim: 0)
        } else if s >= a && e <= b {
            return nil
        } else if s < a && e <= b {
            out = Result(start: s, end: a, headTrim: 0)
        } else if s >= a && e > b {
            out = Result(start: a, end: e - length, headTrim: b - s)
        } else {
            switch straddle {
            case .shrink: out = Result(start: s, end: e - length, headTrim: 0)
            case .keepHead: out = Result(start: s, end: a, headTrim: 0)
            }
        }
        return out.end - out.start >= minLength ? out : nil
    }

    /// A single position (offset of a track, effect window start/end).
    static func point(_ t: Double, cutStart a: Double, cutEnd b: Double) -> Double {
        guard t.isFinite, b > a else { return t }
        if t <= a { return t }
        if t >= b { return t - (b - a) }
        return a
    }

    /// Re-map a 0...1 keyframe position after an item lost `headTrim` seconds
    /// at the start and now lasts `newDuration`. nil = keyframe fell outside.
    static func remapProgress(
        _ progress: Double, oldDuration: Double,
        headTrim: Double, newDuration: Double
    ) -> Double? {
        guard progress.isFinite, oldDuration > 0, newDuration > 0 else { return nil }
        let t = progress * oldDuration - headTrim
        guard t >= -0.0001, t <= newDuration + 0.0001 else { return nil }
        return min(1, max(0, t / newDuration))
    }
}
