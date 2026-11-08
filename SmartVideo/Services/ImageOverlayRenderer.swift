import Foundation
import AVFoundation
import QuartzCore
import UIKit

/// Burn movable image layers into the existing Core Animation composition.
/// v3.7 supports several position, zoom, rotation and opacity keyframes.
enum ImageOverlayRenderer {
    static func attach(
        _ overlays: [ImageOverlayClip], to parent: CALayer,
        canvas: CGSize, timelineDuration: Double
    ) {
        guard timelineDuration.isFinite, timelineDuration > 0,
              canvas.width > 0, canvas.height > 0 else { return }

        for item in overlays {
            guard let original = UIImage(contentsOfFile: item.fileURL.path) else {
                continue
            }
            let image = ChromaKeyProcessor.render(
                original, enabled: item.chromaEnabled,
                color: item.chromaColor,
                tolerance: item.chromaTolerance,
                softness: item.chromaSoftness
            ) ?? original
            guard let bitmap = image.cgImage else { continue }

            let begin = max(0, min(timelineDuration, item.start))
            let end = min(timelineDuration, max(begin, item.end))
            guard end > begin + 0.05 else { continue }
            let duration = end - begin
            let frames = OverlayKeyframeSampler.frames(for: item)
            guard frames.count >= 2, let first = frames.first else { continue }

            // Separate the timeline visibility gate from the animated alpha.
            // This keeps an overlay invisible both before and after its range.
            let gate = CALayer()
            gate.frame = CGRect(origin: .zero, size: canvas)
            gate.opacity = 0
            parent.addSublayer(gate)

            let baseWidth = canvas.width * 0.45
            let aspect = CGFloat(bitmap.height) / CGFloat(max(bitmap.width, 1))
            let baseHeight = min(canvas.height * 1.5, baseWidth * aspect)
            let artwork = CALayer()
            artwork.bounds = CGRect(
                x: 0, y: 0, width: baseWidth, height: baseHeight
            )
            artwork.contents = bitmap
            artwork.contentsGravity = .resizeAspect
            artwork.contentsScale = 2
            artwork.position = position(first, canvas: canvas)
            artwork.opacity = Float(first.opacity)
            let ratio = CGFloat(first.scale / 0.45)
            artwork.transform = CATransform3DConcat(
                CATransform3DMakeScale(ratio, ratio, 1),
                CATransform3DMakeRotation(
                    CGFloat(first.rotationDegrees) * .pi / 180, 0, 0, 1
                )
            )
            gate.addSublayer(artwork)

            let show = CAKeyframeAnimation(keyPath: "opacity")
            show.values = [0, 1, 1, 0]
            show.keyTimes = [0, 0.002, 0.998, 1]
            show.duration = duration
            show.beginTime = AVCoreAnimationBeginTimeAtZero + begin
            show.fillMode = .forwards
            show.isRemovedOnCompletion = false
            gate.add(show, forKey: "overlay-visibility-\(item.id)")

            let timing = frames.map { frame in
                NSNumber(value: min(1, max(0, frame.progress)))
            }
            let ease = TextOverlayRenderer.easing(item.easing)
            let smooth = Array(
                repeating: CAMediaTimingFunction(name: ease),
                count: max(0, timing.count - 1)
            )

            animate(
                artwork, property: "position",
                values: frames.map { NSValue(cgPoint: position($0, canvas: canvas)) },
                times: timing, easing: smooth, begin: begin, duration: duration,
                key: "position"
            )
            animate(
                artwork, property: "transform.scale",
                values: frames.map { NSNumber(value: $0.scale / 0.45) },
                times: timing, easing: smooth, begin: begin, duration: duration,
                key: "zoom"
            )
            animate(
                artwork, property: "transform.rotation.z",
                values: frames.map {
                    NSNumber(value: $0.rotationDegrees * .pi / 180)
                },
                times: timing, easing: smooth, begin: begin, duration: duration,
                key: "rotation"
            )
            animate(
                artwork, property: "opacity",
                values: frames.map { NSNumber(value: min(1, max(0, $0.opacity))) },
                times: timing, easing: smooth, begin: begin, duration: duration,
                key: "alpha"
            )
        }
    }

    private static func position(
        _ key: OverlayKeyframe, canvas: CGSize
    ) -> CGPoint {
        // Core Animation composition origin is bottom-left.
        CGPoint(
            x: CGFloat(key.x) * canvas.width,
            y: (1 - CGFloat(key.y)) * canvas.height
        )
    }

    private static func animate(
        _ layer: CALayer, property: String,
        values: [Any], times: [NSNumber],
        easing: [CAMediaTimingFunction], begin: Double,
        duration: Double, key: String
    ) {
        guard values.count == times.count, values.count >= 2 else { return }
        let anim = CAKeyframeAnimation(keyPath: property)
        anim.values = values
        anim.keyTimes = times
        anim.timingFunctions = easing
        anim.calculationMode = .linear
        anim.beginTime = AVCoreAnimationBeginTimeAtZero + begin
        anim.duration = duration
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "viepn-keyframe-\(key)")
    }
}
