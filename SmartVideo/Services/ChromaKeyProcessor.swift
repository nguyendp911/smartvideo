import UIKit
import CoreImage

/// Core Image chroma key. `render` keys one UIImage (image overlays);
/// `keyed` keys a CIImage so video frames can be processed without
/// round-tripping through UIImage (see AlphaVideoProcessor).
enum ChromaKeyProcessor {
    static let context = CIContext(options: [.cacheIntermediates: false])
    private static let cubeDimension = 32
    private static let cubeCache = NSCache<NSString, NSData>()

    static func render(_ source: UIImage, enabled: Bool,
                       color: ChromaKeyColor,
                       tolerance: Double,
                       softness: Double) -> UIImage? {
        guard enabled else { return source }
        guard let input = CIImage(image: source) else { return source }
        let keyed = Self.keyed(input, color: color,
                               tolerance: tolerance, softness: softness)
        guard let cg = context.createCGImage(keyed, from: keyed.extent) else {
            return source
        }
        return UIImage(cgImage: cg)
    }

    /// Premultiplied-alpha result where the key colour is transparent.
    static func keyed(_ input: CIImage, color: ChromaKeyColor,
                      tolerance: Double, softness: Double) -> CIImage {
        input.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": cubeDimension,
            "inputCubeData": cubeData(color: color, tolerance: tolerance,
                                      softness: softness)
        ])
    }

    private static func cubeData(color: ChromaKeyColor, tolerance: Double,
                                 softness: Double) -> Data {
        let threshold = max(0.06, min(0.85, tolerance))
        let feather = max(0.01, min(0.40, softness))
        let key = "\(color.rawValue)|\(threshold)|\(feather)" as NSString
        if let cached = cubeCache.object(forKey: key) { return cached as Data }

        let dim = cubeDimension
        var values = [Float]()
        values.reserveCapacity(dim * dim * dim * 4)
        for b in 0..<dim {
            for g in 0..<dim {
                for r in 0..<dim {
                    let red = Double(r) / Double(dim - 1)
                    let green = Double(g) / Double(dim - 1)
                    let blue = Double(b) / Double(dim - 1)
                    let distance: Double
                    switch color {
                    case .green:
                        distance = green - max(red, blue)
                    case .blue:
                        distance = blue - max(red, green)
                    }
                    // Transparent when the key color dominates; smooth
                    // the alpha transition to reduce hard-colored edges.
                    let relative = (distance - threshold) / feather
                    let a = Float(1 - min(1, max(0, relative)))
                    values.append(Float(red) * a)
                    values.append(Float(green) * a)
                    values.append(Float(blue) * a)
                    values.append(a)
                }
            }
        }
        let data = values.withUnsafeBytes { raw in Data(raw) }
        cubeCache.setObject(data as NSData, forKey: key)
        return data
    }
}

enum ChromaKeyColor: String, Codable, CaseIterable, Identifiable {
    case green = "Xanh lá"
    case blue = "Xanh dương"
    var id: String { rawValue }
}
