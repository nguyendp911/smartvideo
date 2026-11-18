import Foundation

extension MusicVideoStudio {
    enum EffectKind: String, Codable, CaseIterable, Identifiable {
        case vignette = "Viền tối"
        case grain = "Hạt phim"
        case lightLeak = "Rò sáng"
        case flash = "Chớp theo nhịp"
        case fadeBlack = "Mờ vào/ra đen"
        case shake = "Rung máy"
        case beatPulse = "Phồng theo nhịp"
        case scanlines = "Đường quét CRT"
        var id: String { rawValue }

        /// Needs the beats of an audio clip.
        var needsAudio: Bool { self == .flash || self == .beatPulse }
        /// Moves the picture instead of drawing over it.
        var movesScene: Bool { self == .shake || self == .beatPulse }
    }

    /// A full-frame effect on the Effects track. Every effect is a pure function of the clock
    /// (and, for beat effects, of the analysed beats), so preview, seek and export agree.
    struct EffectLayer: StudioLayer {
        var core: LayerCore
        var kind: EffectKind
        /// The audio clip whose beats drive Flash / Beat Pulse.
        var audioLayerID: UUID?
        var intensity = 0.6
        var speed = 1.0
        var colorHex = "#FFB74D"
        var fadeIn = 1.0
        var fadeOut = 1.0
        /// Use every n-th beat.
        var everyBeats = 1

        static let intensityRange = 0.05...1.0
        static let speedRange = 0.2...4.0
        static let fadeRange = 0.0...10.0
        static let beatsRange = 1...8

        init(core: LayerCore, kind: EffectKind, audioLayerID: UUID? = nil) {
            self.core = core
            self.kind = kind
            self.audioLayerID = audioLayerID
        }

        private enum CodingKeys: String, CodingKey {
            case core, kind, audioLayerID, intensity, speed, colorHex, fadeIn, fadeOut, everyBeats
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            core = try c.decode(LayerCore.self, forKey: .core)
            kind = try c.decodeIfPresent(EffectKind.self, forKey: .kind) ?? .vignette
            audioLayerID = try c.decodeIfPresent(UUID.self, forKey: .audioLayerID)
            intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.6
            speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
            colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#FFB74D"
            fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 1
            fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 1
            let beats = try c.decodeIfPresent(Int.self, forKey: .everyBeats) ?? 1
            everyBeats = min(Self.beatsRange.upperBound, max(Self.beatsRange.lowerBound, beats))
        }
    }
}
