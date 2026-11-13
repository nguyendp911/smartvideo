import Foundation

/// Quick editorial warning; not a replacement for listening to the real TTS.
enum AIRevoiceTimingGuide {
    /// Vietnamese prose is approximately 12–17 visible characters per
    /// second in typical narration, with large variation by voice and style.
    static func estimatedSeconds(_ text: String, charactersPerSecond: Double = 14) -> Double {
        let visible = text.filter { !$0.isWhitespace }.count
        return Double(visible) / max(1, charactersPerSecond) + 0.15
    }

    static func overrunSeconds(text: String, start: Double, end: Double) -> Double {
        let available = max(0, end - start)
        return max(0, estimatedSeconds(text) - available)
    }

    static func needsReview(_ cue: SubtitleCue) -> Bool {
        // Avoid warning about tiny differences that iOS TTS can absorb.
        overrunSeconds(text: cue.text, start: cue.start, end: cue.end) > 0.45
    }
}
