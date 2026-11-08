import Foundation

/// A non-destructive audio region on the global video timeline.
/// Durations are measured in seconds, with sourceStart relative to the file.
struct SoundEffectClip: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileURL: URL
    var start: Double = 0
    var sourceStart: Double = 0
    var duration: Double = 1
    var originalDuration: Double = 1
    var volume: Float = 0.80
    var fadeIn: Double = 0.04
    var fadeOut: Double = 0.12
    var muted: Bool = false

    var end: Double { start + duration }
    var filename: String { fileURL.lastPathComponent }

    static func create(url: URL, audioDuration: Double,
                       timelineStart: Double, timelineEnd: Double) -> SoundEffectClip {
        let start = min(max(0, timelineStart),
                        max(0, timelineEnd - 0.1))
        return SoundEffectClip(
            fileURL: url,
            start: start,
            sourceStart: 0,
            duration: min(5, audioDuration, max(0.1, timelineEnd - start)),
            originalDuration: audioDuration
        )
    }
}

/// The built-in samples are synthesized original sounds, not copyrighted
/// audio taken from CapCut or another library.
enum BuiltInSoundEffect: String, CaseIterable, Identifiable {
    case whoosh = "Whoosh"
    case pop = "Pop"
    case impact = "Impact"
    case click = "Click"
    case riser = "Riser"
    case glitch = "Glitch"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .whoosh: return "wind"
        case .pop: return "bubble.left.fill"
        case .impact: return "bolt.fill"
        case .click: return "cursorarrow.click"
        case .riser: return "arrow.up.right"
        case .glitch: return "waveform.path"
        }
    }
}
