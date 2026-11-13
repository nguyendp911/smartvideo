import Foundation

enum PhotoPresetCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case travel = "Du lịch"
    case portrait = "Chân dung"
    case food = "Đồ ăn"
    case art = "Nghệ thuật"
    case lifestyle = "Đời sống"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .travel: return "sun.max"
        case .portrait: return "person.crop.square"
        case .food: return "fork.knife"
        case .art: return "paintpalette"
        case .lifestyle: return "house"
        }
    }
}

/// Self-contained recipe is stored in each photo clip. A custom preset
/// keeps rendering after it is deleted from the user's preset library.
struct PhotoPreset: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var category: PhotoPresetCategory
    var exposureEV: Double
    var contrast: Double
    var saturation: Double
    var warmth: Double
    var noiseReduction: Double
    var sharpness: Double
    var highlightSoftness: Double
    var shadowLift: Double
    var vignette: Double
    var vibrance: Double

    static let neutral = PhotoPreset(
        id: "neutral", name: "Nguyên bản", category: .lifestyle,
        exposureEV: 0, contrast: 1, saturation: 1, warmth: 0,
        noiseReduction: 0, sharpness: 0, highlightSoftness: 0,
        shadowLift: 0, vignette: 0, vibrance: 0
    )
}

enum PhotoPresetLibrary {
    static let all: [PhotoPreset] = [
        .init(id: "beach", name: "Đi biển", category: .travel,
              exposureEV: 0.24, contrast: 1.05,
              saturation: 1.14, warmth: -0.05,
              noiseReduction: 0.012, sharpness: 0.3,
              highlightSoftness: 0.08, shadowLift: 0.04,
              vignette: 0.02, vibrance: 0.11),
        .init(id: "sunset", name: "Hoàng hôn", category: .travel,
              exposureEV: 0.1, contrast: 1.08,
              saturation: 1.1, warmth: 0.24,
              noiseReduction: 0.01, sharpness: 0.24,
              highlightSoftness: 0.16, shadowLift: 0.02,
              vignette: 0.08, vibrance: 0.13),
        .init(id: "sunrise", name: "Bình minh", category: .travel,
              exposureEV: 0.16, contrast: 1.04,
              saturation: 1.06, warmth: 0.16,
              noiseReduction: 0.011, sharpness: 0.22,
              highlightSoftness: 0.12, shadowLift: 0.06,
              vignette: 0.04, vibrance: 0.09),
        .init(id: "forest", name: "Rừng xanh", category: .travel,
              exposureEV: 0.08, contrast: 1.06,
              saturation: 1.12, warmth: -0.02,
              noiseReduction: 0.012, sharpness: 0.28,
              highlightSoftness: 0.06, shadowLift: 0.05,
              vignette: 0.05, vibrance: 0.09),
        .init(id: "blue_sky", name: "Trời xanh", category: .travel,
              exposureEV: 0.18, contrast: 1.05,
              saturation: 1.13, warmth: -0.04,
              noiseReduction: 0.01, sharpness: 0.26,
              highlightSoftness: 0.05, shadowLift: 0.04,
              vignette: 0.03, vibrance: 0.14),
        .init(id: "city_night", name: "Thành phố đêm", category: .travel,
              exposureEV: -0.02, contrast: 1.1,
              saturation: 1.08, warmth: 0.04,
              noiseReduction: 0.018, sharpness: 0.34,
              highlightSoftness: 0.1, shadowLift: 0.01,
              vignette: 0.1, vibrance: 0.06),
        .init(id: "natural_skin", name: "Da đẹp tự nhiên", category: .portrait,
              exposureEV: 0.12, contrast: 0.98,
              saturation: 1.03, warmth: 0.06,
              noiseReduction: 0.02, sharpness: 0.16,
              highlightSoftness: 0.18, shadowLift: 0.08,
              vignette: 0.02, vibrance: 0.03),
        .init(id: "korean_soft", name: "Tone Hàn", category: .portrait,
              exposureEV: 0.18, contrast: 0.96,
              saturation: 0.98, warmth: 0.03,
              noiseReduction: 0.022, sharpness: 0.14,
              highlightSoftness: 0.2, shadowLift: 0.1,
              vignette: 0.01, vibrance: 0.02),
        .init(id: "soft_glow", name: "Glow nhẹ", category: .portrait,
              exposureEV: 0.2, contrast: 0.97,
              saturation: 1.04, warmth: 0.08,
              noiseReduction: 0.018, sharpness: 0.12,
              highlightSoftness: 0.22, shadowLift: 0.1,
              vignette: 0.03, vibrance: 0.03),
        .init(id: "warm_portrait", name: "Chân dung ấm", category: .portrait,
              exposureEV: 0.1, contrast: 1.03,
              saturation: 1.05, warmth: 0.15,
              noiseReduction: 0.018, sharpness: 0.18,
              highlightSoftness: 0.14, shadowLift: 0.06,
              vignette: 0.05, vibrance: 0.04),
        .init(id: "cool_portrait", name: "Chân dung lạnh", category: .portrait,
              exposureEV: 0.08, contrast: 1.04,
              saturation: 1.02, warmth: -0.06,
              noiseReduction: 0.018, sharpness: 0.2,
              highlightSoftness: 0.12, shadowLift: 0.05,
              vignette: 0.06, vibrance: 0.04),
        .init(id: "selfie_bright", name: "Selfie sáng da", category: .portrait,
              exposureEV: 0.22, contrast: 0.99,
              saturation: 1.05, warmth: 0.05,
              noiseReduction: 0.024, sharpness: 0.15,
              highlightSoftness: 0.2, shadowLift: 0.12,
              vignette: 0.02, vibrance: 0.06),
        .init(id: "food_fresh", name: "Food tươi ngon", category: .food,
              exposureEV: 0.12, contrast: 1.08,
              saturation: 1.15, warmth: 0.06,
              noiseReduction: 0.01, sharpness: 0.28,
              highlightSoftness: 0.06, shadowLift: 0.03,
              vignette: 0.05, vibrance: 0.12),
        .init(id: "dessert_soft", name: "Dessert ngọt", category: .food,
              exposureEV: 0.18, contrast: 1.02,
              saturation: 1.1, warmth: 0.1,
              noiseReduction: 0.012, sharpness: 0.22,
              highlightSoftness: 0.12, shadowLift: 0.06,
              vignette: 0.04, vibrance: 0.07),
        .init(id: "cafe_brown", name: "Cafe tone nâu", category: .food,
              exposureEV: 0.04, contrast: 1.07,
              saturation: 0.96, warmth: 0.2,
              noiseReduction: 0.011, sharpness: 0.24,
              highlightSoftness: 0.08, shadowLift: 0.03,
              vignette: 0.1, vibrance: 0.05),
        .init(id: "restaurant_lux", name: "Nhà hàng sang", category: .food,
              exposureEV: 0.06, contrast: 1.1,
              saturation: 1.04, warmth: 0.12,
              noiseReduction: 0.012, sharpness: 0.26,
              highlightSoftness: 0.1, shadowLift: 0.02,
              vignette: 0.08, vibrance: 0.03),
        .init(id: "vintage_film", name: "Vintage film", category: .art,
              exposureEV: 0.02, contrast: 0.97,
              saturation: 0.92, warmth: 0.18,
              noiseReduction: 0.01, sharpness: 0.12,
              highlightSoftness: 0.18, shadowLift: 0.08,
              vignette: 0.12, vibrance: -0.04),
        .init(id: "moody_chill", name: "Moody chill", category: .art,
              exposureEV: -0.08, contrast: 1.1,
              saturation: 0.94, warmth: -0.02,
              noiseReduction: 0.014, sharpness: 0.22,
              highlightSoftness: 0.1, shadowLift: -0.02,
              vignette: 0.14, vibrance: -0.04),
        .init(id: "pastel_soft", name: "Pastel nhẹ", category: .art,
              exposureEV: 0.16, contrast: 0.94,
              saturation: 0.96, warmth: 0.04,
              noiseReduction: 0.016, sharpness: 0.12,
              highlightSoftness: 0.2, shadowLift: 0.1,
              vignette: 0.03, vibrance: -0.02),
        .init(id: "cinematic_photo", name: "Cinematic ảnh", category: .art,
              exposureEV: -0.02, contrast: 1.12,
              saturation: 0.95, warmth: 0.02,
              noiseReduction: 0.012, sharpness: 0.26,
              highlightSoftness: 0.1, shadowLift: 0,
              vignette: 0.15, vibrance: 0.02)
    ]

    static func find(_ id: String) -> PhotoPreset? {
        all.first { $0.id == id }
    }
    static func inCategory(_ category: PhotoPresetCategory) -> [PhotoPreset] {
        all.filter { $0.category == category }
    }

    /// Snapshot manual color controls as a reusable user-created recipe.
    static func snapshot(name: String, from clip: TimelineClip) -> PhotoPreset {
        let adjustments = clip.colorAdjustments
        let enhance = clip.autoEnhance
        return PhotoPreset(
            id: "custom-" + UUID().uuidString,
            name: String(name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(42)),
            category: .lifestyle,
            exposureEV: adjustments.exposureEV,
            contrast: adjustments.contrast,
            saturation: adjustments.saturation,
            warmth: adjustments.warmth,
            noiseReduction: enhance.enabled ? enhance.noiseReduction : 0,
            sharpness: enhance.enabled ? enhance.sharpness : 0,
            highlightSoftness: 0,
            shadowLift: 0,
            vignette: 0,
            vibrance: 0
        )
    }
}
