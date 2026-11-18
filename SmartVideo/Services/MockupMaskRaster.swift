import Foundation
import CoreGraphics

/// Rasterises `MockupMaskMath` into a small greyscale bitmap that Core Image
/// stretches over the canvas (bilinear), so every renderer shares one mask.
enum MockupMaskRaster {
    static let side = 160
    private final class Box { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 24
        return c
    }()

    static func image(for mask: MockupMask) -> CGImage? {
        guard mask.isActive else { return nil }
        let key = "\(mask.kind.rawValue)|\(Int(mask.size * 100))|\(Int(mask.feather * 100))|\(mask.invert)" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }
        var pixels = [UInt8](repeating: 0, count: side * side)
        for row in 0..<side {
            let y = (Double(row) + 0.5) / Double(side)          // row 0 = top
            for column in 0..<side {
                let x = (Double(column) + 0.5) / Double(side)
                pixels[row * side + column] = UInt8((MockupMaskMath.alpha(mask, x: x, y: y) * 255).rounded())
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return nil }
        cache.setObject(Box(image), forKey: key)
        return image
    }

    /// White image whose ALPHA carries the mask, for SwiftUI's `.mask`.
    static func alphaImage(for mask: MockupMask) -> CGImage? {
        guard mask.isActive else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            let y = (Double(row) + 0.5) / Double(side)
            for column in 0..<side {
                let x = (Double(column) + 0.5) / Double(side)
                let a = UInt8((MockupMaskMath.alpha(mask, x: x, y: y) * 255).rounded())
                let offset = (row * side + column) * 4
                pixels[offset] = a; pixels[offset + 1] = a; pixels[offset + 2] = a; pixels[offset + 3] = a   // premultiplied white
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
