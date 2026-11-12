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
    /// Empty for existing projects; non-destructive per-region automation.
    var volumeKeyframes: [AudioGainKeyframe] = []

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

extension SoundEffectClip {
    private enum CodingKeys: String, CodingKey {
        case id, fileURL, start, sourceStart, duration, originalDuration
        case volume, fadeIn, fadeOut, muted, volumeKeyframes
    }

    /// Old projects lack volumeKeyframes; treat them as 100% constant.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileURL = try c.decode(URL.self, forKey: .fileURL)
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        sourceStart = try c.decodeIfPresent(Double.self, forKey: .sourceStart) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 1
        originalDuration = try c.decodeIfPresent(Double.self,
                                                 forKey: .originalDuration) ?? duration
        volume = AudioAutomationMath.clampGain(
            try c.decodeIfPresent(Float.self, forKey: .volume) ?? 0.8
        )
        fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0.04
        fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 0.12
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        volumeKeyframes = AudioAutomationMath.normalized(
            try c.decodeIfPresent([AudioGainKeyframe].self,
                                  forKey: .volumeKeyframes) ?? []
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
