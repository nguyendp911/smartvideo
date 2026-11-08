import UIKit
import CoreImage

/// Simple Core Image chroma key for *image overlays*. Keying video frames
/// requires a custom pixel-buffer compositor; not claimed here.
enum ChromaKeyProcessor {
    static let context = CIContext(options: [.cacheIntermediates: false])

    static func render(_ source: UIImage, enabled: Bool,
                       color: ChromaKeyColor,
                       tolerance: Double,
                       softness: Double) -> UIImage? {
        guard enabled else { return source }
        guard let input = CIImage(image: source) else { return source }
        let dim = 32
        var values = [Float]()
        values.reserveCapacity(dim * dim * dim * 4)
        let threshold = max(0.06, min(0.85, tolerance))
        let feather = max(0.01, min(0.40, softness))
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
        let keyed = input.applyingFilter("CIColorCube", parameters: [
            "inputCubeDimension": dim,
            "inputCubeData": data
        ])
        guard let cg = context.createCGImage(keyed, from: keyed.extent) else {
            return source
        }
        return UIImage(cgImage: cg)
    }
}

enum ChromaKeyColor: String, Codable, CaseIterable, Identifiable {
    case green = "Xanh lá"
    case blue = "Xanh dương"
    var id: String { rawValue }
}
