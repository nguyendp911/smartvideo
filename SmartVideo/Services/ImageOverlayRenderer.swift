import Foundation
import AVFoundation
import QuartzCore
import UIKit

/// Burn image overlays into the existing subtitle/VFX Core Animation stack.
/// This avoids adding an expensive second video-composition pass.
enum ImageOverlayRenderer {
    static func attach(_ overlays: [ImageOverlayClip],
                       to parent: CALayer,
                       canvas: CGSize,
                       timelineDuration: Double) {
        guard timelineDuration.isFinite, timelineDuration > 0 else { return }
        let videoWidth = canvas.width
        let videoHeight = canvas.height

        for item in overlays {
            guard let originalImage = UIImage(contentsOfFile: item.fileURL.path) else {
                continue
            }
            let image = ChromaKeyProcessor.render(
                originalImage, enabled: item.chromaEnabled,
                color: item.chromaColor,
                tolerance: item.chromaTolerance,
                softness: item.chromaSoftness
            ) ?? originalImage
            guard let cgImage = image.cgImage else { continue }

            let begin = max(0, min(timelineDuration, item.start))
            let end = min(timelineDuration, max(begin, item.end))
            guard end > begin + 0.04 else { continue }
            let safeWidth = CGFloat(min(1, max(0.1, item.scale))) * videoWidth
            let aspect = CGFloat(cgImage.height) / CGFloat(max(cgImage.width, 1))
            let safeHeight = min(videoHeight * 1.5, safeWidth * aspect)

            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: safeWidth, height: safeHeight)
            layer.contents = cgImage
            layer.contentsGravity = .resizeAspect
            layer.contentsScale = 2
            layer.opacity = 0
            layer.transform = CATransform3DMakeRotation(
                CGFloat(item.rotationDegrees) * .pi / 180, 0, 0, 1
            )

            // Core Animation uses bottom-left coordinates for the output.
            let startPoint = CGPoint(x: item.startX * videoWidth,
                                     y: (1 - item.startY) * videoHeight)
            let endPoint = CGPoint(x: item.endX * videoWidth,
                                   y: (1 - item.endY) * videoHeight)
            layer.position = startPoint
            parent.addSublayer(layer)

            let visible = CAKeyframeAnimation(keyPath: "opacity")
            visible.values = [0, Float(min(1, max(0, item.opacity))),
                              Float(min(1, max(0, item.opacity))), 0]
            visible.keyTimes = [0, 0.01, 0.99, 1]
            visible.beginTime = AVCoreAnimationBeginTimeAtZero + begin
            visible.duration = end - begin
            visible.fillMode = .forwards
            visible.isRemovedOnCompletion = false
            layer.add(visible, forKey: "viepn-overlay-opacity-\(item.id)")

            if abs(startPoint.x - endPoint.x) + abs(startPoint.y - endPoint.y) > 0.5 {
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(cgPoint: startPoint)
                move.toValue = NSValue(cgPoint: endPoint)
                move.beginTime = AVCoreAnimationBeginTimeAtZero + begin
                move.duration = end - begin
                move.timingFunction = CAMediaTimingFunction(
                    name: TextOverlayRenderer.easing(item.easing))
                move.fillMode = .forwards
                move.isRemovedOnCompletion = false
                layer.add(move, forKey: "viepn-overlay-move-\(item.id)")
            }
        }
    }
}
