import Foundation
import Vision
import UIKit
import CoreImage

/// Genuine on-device Vision face rectangles plus luminance-based placement.
/// Privacy: no server requests; the only frame analyzed is the selected
/// clip's local still / a frame from its AVAsset.
enum MockupFaceAwareLayout {
    struct Suggestion {
        var x: Double
        var y: Double
        var opacity: Double
        var rotation: Double
    }

    static func faceRectangles(_ image: CIImage) -> [CGRect] {
        let rect = image.extent
        guard rect.width > 0 && rect.height > 0 else {
            return []
        }
        let scale = min(1, 640 / max(rect.width, rect.height))
        let small = image.transformed(
            by: CGAffineTransform(
                scaleX: scale, y: scale
            )
        )
        let request = VNDetectFaceRectanglesRequest()
        do {
            try VNImageRequestHandler(
                ciImage: small, options: [:]
            ).perform([request])
            return request.results?.map { $0.boundingBox } ?? []
        } catch {
            return []
        }
    }

    /// White retains the mockup, black restores the original around a face.
    /// This is alpha-aware, not a global opacity reduction. A coarse face
    /// matte is regenerated only when Avoid Face is selected for export.
    static func protectionMask(
        _ source: CIImage
    ) -> CIImage? {
        let faces = faceRectangles(source)
        guard !faces.isEmpty else { return nil }
        let extent = source.extent
        let scale = min(1, 512 / max(
            extent.width, extent.height
        ))
        let canvas = CGSize(
            width: max(1, floor(extent.width * scale)),
            height: max(1, floor(extent.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let bitmap = UIGraphicsImageRenderer(
            size: canvas, format: format
        ).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(
                origin: .zero, size: canvas
            ))
            UIColor.black.setFill()
            for face in faces {
                let box = CGRect(
                    x: face.minX * canvas.width,
                    y: (1 - face.maxY) * canvas.height,
                    width: face.width * canvas.width,
                    height: face.height * canvas.height
                ).insetBy(
                    dx: -face.width * canvas.width * 0.35,
                    dy: -face.height * canvas.height * 0.32
                )
                UIBezierPath(ovalIn: box).fill()
            }
        }
        guard let cg = bitmap.cgImage else { return nil }
        return CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(
                scaleX: 1 / scale, y: 1 / scale
            ))
            .transformed(by: CGAffineTransform(
                translationX: extent.minX,
                y: extent.minY
            ))
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur",
                            parameters: [kCIInputRadiusKey: 12])
            .cropped(to: extent)
    }

    static func suggest(
        image: CGImage,
        category: MockupCategory
    ) -> Suggestion {
        let ci = CIImage(cgImage: image)
        let faces = faceRectangles(ci).map {
            CGRect(
                x: $0.midX, y: 1 - $0.midY,
                width: $0.width, height: $0.height
            )
        }
        // Read 4x4 average samples to find a physically plausible light
        // entry corner rather than blindly putting every flare top-left.
        let width = 4, height = 4
        var bytes = [UInt8](
            repeating: 0, count: width * height * 4
        )
        let context = CIContext()
        let resized = ci.transformed(by: CGAffineTransform(
            scaleX: CGFloat(width) / max(1, ci.extent.width),
            y: CGFloat(height) / max(1, ci.extent.height)
        ))
        bytes.withUnsafeMutableBytes { buffer in
            guard let pointer = buffer.baseAddress else { return }
            context.render(
                resized, toBitmap: pointer,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0,
                               width: width, height: height),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        let topCorners: [(Double, Double, Int)] = [
            (0.22, 0.24, 12), (0.78, 0.24, 15),
            (0.22, 0.75, 0), (0.78, 0.75, 3)
        ]
        let lightEffect = category == .flares ||
            category == .reflections ||
            category == .atmosphere
        var best: (Double, Double) = (0.22, 0.24)
        var bestScore = -Double.infinity
        for (x, y, index) in topCorners {
            let offset = index * 4
            let brightness = (Double(bytes[offset]) +
                Double(bytes[offset + 1]) +
                Double(bytes[offset + 2])) / (3 * 255)
            let facePenalty = faces.reduce(0.0) {
                total, face in
                let dx = x - Double(face.midX)
                let dy = y - Double(face.midY)
                let distance = hypot(dx, dy)
                return total + max(0, 0.48 - distance) * 6
            }
            let score = (lightEffect ? brightness :
                1 - brightness) - facePenalty
            if score > bestScore {
                bestScore = score
                best = (x, y)
            }
        }
        return Suggestion(
            x: best.0, y: best.1,
            opacity: faces.isEmpty ? 0.60 : 0.44,
            rotation: best.0 > 0.5 ? -12 : 12
        )
    }
}
