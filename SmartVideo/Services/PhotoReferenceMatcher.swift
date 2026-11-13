import Foundation
import CoreGraphics
import ImageIO

/// A local reference-image color matcher. Learns a bounded color grade
/// from thumbnail statistics; it does NOT copy objects, faces or texture.
enum PhotoReferenceMatcher {
    struct Statistics {
        let brightness: Double
        let contrast: Double
        let saturation: Double
        let warmth: Double
    }

    static func createPreset(
        fromReferenceData reference: Data,
        forSourceURL sourceURL: URL,
        name: String
    ) async throws -> PhotoPreset {
        guard reference.count > 100 && reference.count <= 25_000_000 else {
            throw SmartVideoError.invalidMedia(
                "Ảnh mẫu vượt quá 25 MB hoặc không hợp lệ.")
        }
        return try await Task.detached(priority: .userInitiated) {
            let source = try Self.readStats(url: sourceURL)
            let goal = try Self.readStats(data: reference)
            // Statistics are normalized RGB summaries, not a semantic copy
            // of the look. Conservative limits prevent blown highlights.
            let exposure = Self.clamp(
                log2(max(0.08, goal.brightness) /
                     max(0.08, source.brightness)),
                -0.45...0.45)
            let contrast = Self.clamp(
                goal.contrast / max(0.04, source.contrast),
                0.84...1.20)
            let saturation = Self.clamp(
                goal.saturation / max(0.07, source.saturation),
                0.78...1.22)
            let warmth = Self.clamp(
                (goal.warmth - source.warmth) * 2.2,
                -0.30...0.30)
            return PhotoPreset(
                id: "reference-" + UUID().uuidString,
                name: String(name.trimmingCharacters(
                    in: .whitespacesAndNewlines).prefix(42)),
                category: .lifestyle,
                exposureEV: exposure,
                contrast: contrast,
                saturation: saturation,
                warmth: warmth,
                noiseReduction: 0,
                sharpness: 0,
                highlightSoftness: max(0, goal.brightness > 0.72 ? 0.08 : 0),
                shadowLift: 0,
                vignette: 0,
                vibrance: 0
            )
        }.value
    }

    private static func clamp(_ value: Double,
                              _ bounds: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return bounds.lowerBound }
        return min(bounds.upperBound, max(bounds.lowerBound, value))
    }

    private static func readStats(url: URL) throws -> Statistics {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { throw SmartVideoError.invalidMedia("Không đọc được ảnh gốc.") }
        return try stats(from: imageSource)
    }

    private static func readStats(data: Data) throws -> Statistics {
        guard let imageSource = CGImageSourceCreateWithData(
            data as CFData, nil) else {
            throw SmartVideoError.invalidMedia("Không đọc được ảnh mẫu.")
        }
        return try stats(from: imageSource)
    }

    private static func stats(from imageSource: CGImageSource)
        throws -> Statistics {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource, 0, options as CFDictionary) else {
            throw SmartVideoError.invalidMedia("Ảnh không có khung hình hợp lệ.")
        }
        let size = 48
        let bytesPerRow = size * 4
        var pixels = [UInt8](repeating: 0, count: size * bytesPerRow)
        let valid: Bool = pixels.withUnsafeMutableBytes { data in
            guard let context = CGContext(
                data: data.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0,
                                           width: size, height: size))
            return true
        }
        guard valid else {
            throw SmartVideoError.invalidMedia("Không phân tích được màu ảnh.")
        }
        var lumaSum = 0.0
        var lumaSquareSum = 0.0
        var saturationSum = 0.0
        var warmthSum = 0.0
        let count = Double(size * size)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let maximum = max(red, max(green, blue))
            let minimum = min(red, min(green, blue))
            let colorfulness = maximum > 0.01 ?
                (maximum - minimum) / maximum : 0
            lumaSum += luma
            lumaSquareSum += luma * luma
            saturationSum += colorfulness
            warmthSum += red - blue
        }
        let mean = lumaSum / count
        let deviation = sqrt(max(0, lumaSquareSum / count - mean * mean))
        return Statistics(
            brightness: mean, contrast: deviation,
            saturation: saturationSum / count,
            warmth: warmthSum / count
        )
    }
}
