import Foundation

extension MusicVideoStudio {
    /// One word with its own start / end, in seconds of the AUDIO FILE it belongs to.
    struct LyricWord: Codable, Hashable, Identifiable {
        var id = UUID()
        var text: String
        var start: Double
        var end: Double

        var duration: Double { max(0, end - start) }
    }

    struct LyricLine: Codable, Hashable, Identifiable {
        var id = UUID()
        var words: [LyricWord]

        var start: Double { words.first?.start ?? 0 }
        var end: Double { words.last?.end ?? 0 }
        var text: String { words.map(\.text).joined(separator: " ") }
    }

    enum LyricAnimation: String, Codable, CaseIterable, Identifiable {
        case fill = "Tô dần theo từ"
        case highlight = "Đổi màu từng từ"
        case glow = "Phát sáng"
        case scale = "Phóng to"
        case fade = "Mờ dần"
        case typewriter = "Đánh máy"
        var id: String { rawValue }
    }

    /// Karaoke lyrics. Word times are in the linked audio file's own time, so
    /// moving, trimming or splitting that audio keeps the lyrics in sync with
    /// no extra work ("recalculate after trimming" is automatic).
    struct LyricsLayer: StudioLayer {
        var core: LayerCore
        var lines: [LyricLine]
        /// The audio clip whose file time the words use. nil = times are relative to `core.start`.
        var audioLayerID: UUID?
        var animation = LyricAnimation.fill
        /// Fraction of the canvas height.
        var fontSize = 0.06
        var weight = TextWeight.bold
        var alignment = TextAlignmentOption.center
        var highlightColorHex = "#FFD54F"
        var normalColorHex = "#FFFFFF"
        var showNextLine = true
        var hasShadow = true

        static let sizeRange = 0.025...0.2

        var wordCount: Int { lines.reduce(0) { $0 + $1.words.count } }

        init(core: LayerCore, lines: [LyricLine], audioLayerID: UUID?) {
            self.core = core
            self.lines = lines
            self.audioLayerID = audioLayerID
        }

        private enum CodingKeys: String, CodingKey {
            case core, lines, audioLayerID, animation, fontSize, weight, alignment
            case highlightColorHex, normalColorHex, showNextLine, hasShadow
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            core = try c.decode(LayerCore.self, forKey: .core)
            lines = try c.decodeIfPresent([LyricLine].self, forKey: .lines) ?? []
            audioLayerID = try c.decodeIfPresent(UUID.self, forKey: .audioLayerID)
            animation = try c.decodeIfPresent(LyricAnimation.self, forKey: .animation) ?? .fill
            fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 0.06
            weight = try c.decodeIfPresent(TextWeight.self, forKey: .weight) ?? .bold
            alignment = try c.decodeIfPresent(TextAlignmentOption.self, forKey: .alignment) ?? .center
            highlightColorHex = try c.decodeIfPresent(String.self, forKey: .highlightColorHex) ?? "#FFD54F"
            normalColorHex = try c.decodeIfPresent(String.self, forKey: .normalColorHex) ?? "#FFFFFF"
            showNextLine = try c.decodeIfPresent(Bool.self, forKey: .showNextLine) ?? true
            hasShadow = try c.decodeIfPresent(Bool.self, forKey: .hasShadow) ?? true
        }
    }
}
