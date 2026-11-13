import Foundation

/// Non-destructive Core Image image-restoration controls, saved per clip.
/// These filters cannot recover real detail absent from the source.
struct AutoEnhanceSettings: Codable, Hashable {
    var enabled: Bool = false
    var exposureEV: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var noiseReduction: Double = 0.015
    var sharpness: Double = 0.32

    static let off = AutoEnhanceSettings()
    var isActive: Bool { enabled }

    static func tuned(
        averageLuma: Double,
        lumaDeviation: Double,
        strength: Double
    ) -> AutoEnhanceSettings {
        let power = min(1, max(0, strength))
        // Avoid aggressive exposure lifts, clipped highlights and halos.
        let exposure = max(-0.40, min(0.55,
            log2(0.49 / max(0.11, averageLuma)))) * power
        let contrastBoost = max(0, min(0.12, (0.23 - lumaDeviation) * 0.42))
        return AutoEnhanceSettings(
            enabled: true,
            exposureEV: exposure,
            contrast: 1 + contrastBoost * power,
            saturation: 1 + 0.055 * power,
            noiseReduction: 0.005 + 0.025 * power,
            sharpness: 0.1 + 0.48 * power
        )
    }
}
