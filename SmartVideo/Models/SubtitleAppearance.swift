import Foundation

struct SubtitleAppearance: Codable, Equatable {
    var fontScale: Double = 1
    var foregroundHex: String = "FFFFFF"
    var backgroundOpacity: Double = 0.68
    var shadowEnabled: Bool = true

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
