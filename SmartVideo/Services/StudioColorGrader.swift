import Foundation
import CoreImage

/// Original color transforms using built-in Core Image filters. These looks
/// are applied to still-image clips in the actual MP4 writer.
enum StudioColorGrader {
    static func apply(_ image: CIImage, look: ImageLook) -> CIImage {
        switch look {
        case .original:
            return image
        case .cinematic:
            return controls(image, saturation: 0.82, contrast: 1.16,
                            brightness: -0.015)
        case .mono:
            return controls(image, saturation: 0, contrast: 1.1)
        case .warm:
            return channels(image, red: 1.065, green: 1.01, blue: 0.92)
        case .cool:
            return channels(image, red: 0.94, green: 1, blue: 1.07)
        case .tealOrange:
            let base = controls(image, saturation: 0.92, contrast: 1.16,
                                brightness: -0.012)
            return matrix(base, r: (1.04, 0.015, 0.0),
                          g: (0.0, 0.985, 0.025),
                          b: (0.0, 0.035, 1.08))
        case .noir:
            return vignette(controls(image, saturation: 0,
                                     contrast: 1.31, brightness: -0.025),
                            intensity: 0.55)
        case .golden:
            return vignette(channels(
                controls(image, saturation: 1.08, contrast: 1.045,
                         brightness: 0.015),
                red: 1.075, green: 1.025, blue: 0.88
            ), intensity: 0.16)
        case .pastel:
            return channels(controls(image, saturation: 0.75,
                                     contrast: 0.90, brightness: 0.048),
                            red: 1.025, green: 1.016, blue: 1.03)
        case .moody:
            return vignette(channels(controls(image, saturation: 0.72,
                                              contrast: 1.20, brightness: -0.034),
                                     red: 0.97, green: 1.025, blue: 1.045),
                            intensity: 0.38)
        case .clean:
            return controls(image, saturation: 1.04,
                            contrast: 1.085, brightness: 0.028)
        case .forest:
            return vignette(matrix(controls(image, saturation: 0.81,
                                            contrast: 1.12),
                                   r: (0.97, 0.015, 0),
                                   g: (0.0, 1.07, 0.006),
                                   b: (0.016, 0.035, 0.94)),
                            intensity: 0.19)
        case .vintage:
            let sepia = image.applyingFilter("CISepiaTone",
                                            parameters: [kCIInputIntensityKey: 0.28])
            return vignette(controls(sepia, saturation: 0.84,
                                     contrast: 0.96, brightness: 0.012),
                            intensity: 0.30)
        case .rose:
            return matrix(controls(image, saturation: 0.90,
                                   contrast: 1.03, brightness: 0.032),
                          r: (1.06, 0.012, 0.002),
                          g: (0.004, 0.99, 0.0),
                          b: (0.019, 0.0, 1.02))
        case .desert:
            return channels(controls(image, saturation: 0.80,
                                     contrast: 1.10, brightness: 0.018),
                            red: 1.052, green: 1.014, blue: 0.872)
        case .midnight:
            return vignette(channels(controls(image, saturation: 0.76,
                                              contrast: 1.22, brightness: -0.048),
                                     red: 0.92, green: 0.975, blue: 1.10),
                            intensity: 0.47)
        case .neon:
            return channels(controls(image, saturation: 1.28,
                                     contrast: 1.20, brightness: -0.022),
                            red: 1.035, green: 0.98, blue: 1.085)
        case .editorial:
            return controls(image, saturation: 0.87,
                            contrast: 1.14, brightness: 0.022)
        case .creamy:
            return channels(controls(image, saturation: 0.90,
                                     contrast: 0.93, brightness: 0.046),
                            red: 1.043, green: 1.009, blue: 0.967)
        }
    }

    private static func controls(
        _ image: CIImage,
        saturation: Double, contrast: Double,
        brightness: Double = 0
    ) -> CIImage {
        image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: saturation,
            kCIInputContrastKey: contrast,
            kCIInputBrightnessKey: brightness
        ])
    }

    private static func channels(_ image: CIImage,
                                 red: Double, green: Double,
                                 blue: Double) -> CIImage {
        matrix(image, r: (red, 0, 0),
               g: (0, green, 0), b: (0, 0, blue))
    }

    private static func matrix(
        _ image: CIImage,
        r: (Double, Double, Double),
        g: (Double, Double, Double),
        b: (Double, Double, Double)
    ) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r.0, y: r.1, z: r.2, w: 0),
            "inputGVector": CIVector(x: g.0, y: g.1, z: g.2, w: 0),
            "inputBVector": CIVector(x: b.0, y: b.1, z: b.2, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    private static func vignette(_ image: CIImage,
                                 intensity: Double) -> CIImage {
        image.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: intensity,
            kCIInputRadiusKey: 1.5
        ])
    }
}
