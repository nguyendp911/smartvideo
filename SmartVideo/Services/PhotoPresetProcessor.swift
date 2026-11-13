import Foundation
import CoreImage

/// Image-only mood/retouch pipeline. Applied only when the clip is a still
/// image; the source file and existing video looks remain untouched.
enum PhotoPresetProcessor {
    static func apply(_ source: CIImage, preset: PhotoPreset?,
                      intensity: Double) -> CIImage {
        guard let preset, intensity.isFinite else { return source }
        let amount = min(1, max(0, intensity))
        guard amount > 0.001 else { return source }

        var filtered = source
        let exposure = min(0.8, max(-0.65, preset.exposureEV))
        if abs(exposure) > 0.001 {
            filtered = filtered.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: exposure
            ])
        }
        filtered = filtered.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: min(1.3, max(0.75, preset.contrast)),
            kCIInputSaturationKey: min(1.4, max(0.7, preset.saturation))
        ])
        let warmth = min(0.35, max(-0.35, preset.warmth))
        if abs(warmth) > 0.001 {
            let bias = warmth * 0.30
            filtered = filtered.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1 + bias, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 - bias, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }
        let vibrance = min(0.30, max(-0.30, preset.vibrance))
        if abs(vibrance) > 0.001 {
            filtered = filtered.applyingFilter("CIVibrance", parameters: [
                "inputAmount": vibrance
            ])
        }
        let highlight = min(0.35, max(0, preset.highlightSoftness))
        let shadow = min(0.35, max(-0.2, preset.shadowLift))
        if highlight > 0.001 || abs(shadow) > 0.001 {
            filtered = filtered.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 1 - highlight,
                "inputShadowAmount": max(0, shadow)
            ])
            if shadow < -0.001 {
                filtered = filtered.applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: shadow * 0.08
                ])
            }
        }
        let reduction = min(0.045, max(0, preset.noiseReduction))
        if reduction > 0.005 {
            filtered = filtered.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": reduction,
                "inputSharpness": 0.4
            ])
        }
        let sharpness = min(0.75, max(0, preset.sharpness))
        if sharpness > 0.005 {
            filtered = filtered.applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": sharpness
            ])
        }
        let vignette = min(0.3, max(0, preset.vignette))
        if vignette > 0.001 {
            filtered = filtered.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: vignette,
                kCIInputRadiusKey: 1.4
            ])
        }
        filtered = filtered.cropped(to: source.extent)
        if amount >= 0.999 { return filtered }
        return source.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: filtered,
            kCIInputTimeKey: amount
        ]).cropped(to: source.extent)
    }
}
