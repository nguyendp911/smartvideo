import Foundation

/// Non-destructive still-image portrait focus controls.
/// Values are bounded when loaded from older or imported project JSON.
struct PhotoPortraitFocusSettings: Codable, Hashable {
    var enabled: Bool = false
    var blurStrength: Double = 0.55
    var backgroundDim: Double = 0.12
    var backgroundSaturation: Double = 0.94
    var edgeSoftness: Double = 0.40
    var subjectLiftEV: Double = 0.08

    static let off = PhotoPortraitFocusSettings()

    enum Style: String, CaseIterable, Identifiable {
        case natural = "Tự nhiên"
        case studio = "Studio"
        case cinematic = "Điện ảnh"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .natural: return "camera.aperture"
            case .studio: return "person.crop.rectangle"
            case .cinematic: return "film"
            }
        }
        var settings: PhotoPortraitFocusSettings {
            switch self {
            case .natural:
                return .init(enabled: true, blurStrength: 0.35,
                             backgroundDim: 0.04, backgroundSaturation: 1,
                             edgeSoftness: 0.35, subjectLiftEV: 0.04)
            case .studio:
                return .init(enabled: true, blurStrength: 0.60,
                             backgroundDim: 0.13, backgroundSaturation: 0.95,
                             edgeSoftness: 0.45, subjectLiftEV: 0.13)
            case .cinematic:
                return .init(enabled: true, blurStrength: 0.80,
                             backgroundDim: 0.22, backgroundSaturation: 0.82,
                             edgeSoftness: 0.56, subjectLiftEV: 0.09)
            }
        }
    }

    init(enabled: Bool = false, blurStrength: Double = 0.55,
         backgroundDim: Double = 0.12,
         backgroundSaturation: Double = 0.94,
         edgeSoftness: Double = 0.40,
         subjectLiftEV: Double = 0.08) {
        self.enabled = enabled
        self.blurStrength = Self.safe(blurStrength, 0...1, fallback: 0.55)
        self.backgroundDim = Self.safe(backgroundDim, 0...0.4, fallback: 0.12)
        self.backgroundSaturation = Self.safe(
            backgroundSaturation, 0.55...1.2, fallback: 0.94)
        self.edgeSoftness = Self.safe(edgeSoftness, 0...1, fallback: 0.4)
        self.subjectLiftEV = Self.safe(
            subjectLiftEV, 0...0.4, fallback: 0.08)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, blurStrength, backgroundDim,
             backgroundSaturation, edgeSoftness, subjectLiftEV
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try values.decodeIfPresent(
                Bool.self, forKey: .enabled) ?? false,
            blurStrength: try values.decodeIfPresent(
                Double.self, forKey: .blurStrength) ?? 0.55,
            backgroundDim: try values.decodeIfPresent(
                Double.self, forKey: .backgroundDim) ?? 0.12,
            backgroundSaturation: try values.decodeIfPresent(
                Double.self, forKey: .backgroundSaturation) ?? 0.94,
            edgeSoftness: try values.decodeIfPresent(
                Double.self, forKey: .edgeSoftness) ?? 0.4,
            subjectLiftEV: try values.decodeIfPresent(
                Double.self, forKey: .subjectLiftEV) ?? 0.08
        )
    }

    private static func safe(_ value: Double,
                             _ bounds: ClosedRange<Double>,
                             fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(bounds.upperBound, max(bounds.lowerBound, value))
    }
}
