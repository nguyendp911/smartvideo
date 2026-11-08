import Foundation

enum KaraokeMotion: String, Codable, CaseIterable, Identifiable {
    case highlight = "Sáng chữ"
    case pop = "Nảy chữ"
    case glow = "Phát sáng"
    var id: String { rawValue }
}

struct SubtitleAppearance: Codable, Equatable {
    var fontScale: Double
    var foregroundHex: String
    var backgroundOpacity: Double
    var shadowEnabled: Bool
    var karaokeEnabled: Bool
    var karaokeHex: String
    var karaokeMotion: KaraokeMotion

    init(fontScale: Double = 1, foregroundHex: String = "FFFFFF",
         backgroundOpacity: Double = 0.68, shadowEnabled: Bool = true,
         karaokeEnabled: Bool = false, karaokeHex: String = "FFE563",
         karaokeMotion: KaraokeMotion = .pop) {
        self.fontScale = fontScale
        self.foregroundHex = foregroundHex
        self.backgroundOpacity = backgroundOpacity
        self.shadowEnabled = shadowEnabled
        self.karaokeEnabled = karaokeEnabled
        self.karaokeHex = karaokeHex
        self.karaokeMotion = karaokeMotion
    }

    private enum CodingKeys: String, CodingKey {
        case fontScale, foregroundHex, backgroundOpacity, shadowEnabled
        case karaokeEnabled, karaokeHex, karaokeMotion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? 1
        foregroundHex = try c.decodeIfPresent(String.self,
                                               forKey: .foregroundHex) ?? "FFFFFF"
        backgroundOpacity = try c.decodeIfPresent(Double.self,
                                                   forKey: .backgroundOpacity) ?? 0.68
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? true
        karaokeEnabled = try c.decodeIfPresent(Bool.self, forKey: .karaokeEnabled) ?? false
        karaokeHex = try c.decodeIfPresent(String.self,
                                            forKey: .karaokeHex) ?? "FFE563"
        karaokeMotion = try c.decodeIfPresent(KaraokeMotion.self,
                                               forKey: .karaokeMotion) ?? .pop
    }

    enum Preset: String, CaseIterable, Identifiable {
        case classic = "Cổ điển"
        case minimal = "Tối giản"
        case yellow = "Vàng nổi bật"
        case highContrast = "Tương phản"

        var id: String { rawValue }
        var settings: SubtitleAppearance {
            switch self {
            case .classic:
                return SubtitleAppearance(fontScale: 1, foregroundHex: "FFFFFF",
                                          backgroundOpacity: 0.68,
                                          shadowEnabled: true)
            case .minimal:
                return SubtitleAppearance(fontScale: 0.94, foregroundHex: "FFFFFF",
                                          backgroundOpacity: 0.0,
                                          shadowEnabled: true)
            case .yellow:
                return SubtitleAppearance(fontScale: 1.08, foregroundHex: "FFE563",
                                          backgroundOpacity: 0.55,
                                          shadowEnabled: true)
            case .highContrast:
                return SubtitleAppearance(fontScale: 1.14, foregroundHex: "FFFFFF",
                                          backgroundOpacity: 0.86,
                                          shadowEnabled: true)
            }
        }
    }
}
