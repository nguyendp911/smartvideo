import Foundation

extension MusicVideoStudio {
    enum TextWeight: String, Codable, CaseIterable, Identifiable {
        case regular = "Thường", semibold = "Đậm vừa", bold = "Đậm", heavy = "Rất đậm"
        var id: String { rawValue }
    }

    enum TextAlignmentOption: String, Codable, CaseIterable, Identifiable {
        case leading = "Trái", center = "Giữa", trailing = "Phải"
        var id: String { rawValue }
    }

    /// Static title text. (Word-by-word karaoke lyrics arrive in the lyrics phase.)
    struct TextLayer: StudioLayer {
        var core: LayerCore
        var text: String
        /// Fraction of the canvas HEIGHT.
        var fontSize = 0.07
        var weight = TextWeight.bold
        var alignment = TextAlignmentOption.center
        /// `#RRGGBB`
        var colorHex = "#FFFFFF"
        var hasShadow = true

        static let sizeRange = 0.02...0.3
    }

    /// Hex colour helpers shared by the inspector and the renderer.
    enum HexColor {
        static func components(_ hex: String) -> (r: Double, g: Double, b: Double)? {
            var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
            return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
        }

        static func string(r: Double, g: Double, b: Double) -> String {
            func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        }
    }
}
