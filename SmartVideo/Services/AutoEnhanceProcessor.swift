import Foundation
import CoreImage
import AVFoundation
import UIKit

/// Local, deterministic enhancement. This is NOT generative super-resolution.
/// Uses bounded exposure correction, color balance, denoise and luminance sharpen.
enum AutoEnhanceProcessor {
    static func apply(_ source: CIImage,
                      settings: AutoEnhanceSettings) -> CIImage {
        guard settings.enabled else { return source }
        var image = source
        if abs(settings.exposureEV) > 0.001 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: max(-0.6, min(0.8, settings.exposureEV))
            ])
        }
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: max(0.8, min(1.25, settings.contrast)),
            kCIInputSaturationKey: max(0.8, min(1.2, settings.saturation))
        ])
        let denoise = max(0, min(0.06, settings.noiseReduction))
        if denoise > 0.005 {
            image = image.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": denoise,
                "inputSharpness": 0.4
            ])
        }
        let sharp = max(0, min(0.9, settings.sharpness))
        if sharp > 0.005 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [
                "inputSharpness": sharp
            ])
        }
        return image.cropped(to: source.extent)
    }

    /// Light-weight visual statistics from a small representative frame.
    /// The automatic parameters are computed once, not for every export frame.
    static func recommend(for clip: TimelineClip,
                          strength: Double) async throws -> AutoEnhanceSettings {
        let frame: CGImage
        if clip.kind == .image {
            guard let input = CIImage(contentsOf: clip.fileURL,
                                       options: [.applyOrientationProperty: true]) else {
                throw SmartVideoError.invalidMedia("Không đọc được ảnh để tối ưu.")
            }
            let maxSide = max(input.extent.width, input.extent.height)
            let ratio = min(1.0, 480.0 / max(1, maxSide))
            let scaled = input.transformed(by: CGAffineTransform(
                scaleX: ratio, y: ratio))
            guard let result = CIContext().createCGImage(
                    scaled, from: scaled.extent) else {
                throw SmartVideoError.invalidMedia("Không đọc được ảnh để tối ưu.")
            }
            frame = result
        } else {
            let asset = AVURLAsset(url: clip.fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            let midpoint = max(0, clip.startTime + clip.duration * 0.45)
            frame = try await generator.image(at: CMTime(
                seconds: midpoint, preferredTimescale: 600)).image
        }
        let side = 32
        let strideBytes = side * 4
        var bytes = [UInt8](repeating: 0, count: side * strideBytes)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let available = bytes.withUnsafeMutableBytes { data in
            guard let context = CGContext(
                data: data.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: strideBytes,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(frame, in: CGRect(x: 0, y: 0,
                                           width: side, height: side))
            return true
        }
        guard available else {
            throw SmartVideoError.invalidMedia(
                "Không phân tích được ánh sáng của khung hình.")
        }
        var values: [Double] = []
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let luma = (0.2126 * Double(bytes[offset]) +
                        0.7152 * Double(bytes[offset + 1]) +
                        0.0722 * Double(bytes[offset + 2])) / 255
            values.append(luma)
        }
        let mean = values.reduce(0, +) / Double(max(1, values.count))
        let variance = values.reduce(0.0) {
            $0 + ($1 - mean) * ($1 - mean)
        } / Double(max(1, values.count))
        return AutoEnhanceSettings.tuned(
            averageLuma: mean,
            lumaDeviation: sqrt(variance),
            strength: strength
        )
    }
}
