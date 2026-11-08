import Foundation
import QuartzCore
import AVFoundation
import UIKit

enum TextOverlayRenderer {
    static func attach(_ overlays: [TextOverlayClip], to parent: CALayer,
                       canvas: CGSize, duration: Double) {
        guard duration.isFinite && duration > 0 else { return }
        for item in overlays where !item.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            let begin = min(max(0, item.start), duration)
            let end = min(duration, max(begin, item.end))
            guard end > begin + 0.04 else { continue }
            let fontSize = CGFloat(min(160, max(15, item.fontSize)))
            let width = canvas.width * 0.85
            let height = min(canvas.height * 0.5, fontSize * 3.5)
            let frames = OverlayKeyframeSampler.frames(for: item)
            guard let first = frames.first else { continue }

            // The gate controls the global time range; the title layer is
            // independently animated in XY, zoom, rotation and alpha.
            let gate = CALayer()
            gate.frame = CGRect(origin: .zero, size: canvas)
            gate.opacity = 0
            parent.addSublayer(gate)

            let outer = CALayer()
            outer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            outer.cornerRadius = fontSize * 0.20
            if item.useBackground {
                outer.backgroundColor = UIColor.black.withAlphaComponent(0.52).cgColor
            }
            outer.position = position(first, canvas: canvas)
            outer.opacity = Float(first.opacity)
            outer.transform = transform(first)
            gate.addSublayer(outer)

            let title = CATextLayer()
            title.frame = outer.bounds.insetBy(dx: 9, dy: 5)
            title.string = item.text
            title.font = UIFont.boldSystemFont(ofSize: fontSize)
            title.fontSize = fontSize
            title.alignmentMode = .center
            title.foregroundColor = uiColor(hex: item.colorHex).cgColor
            title.isWrapped = true
            title.contentsScale = 2
            outer.addSublayer(title)

            let visible = CAKeyframeAnimation(keyPath: "opacity")
            visible.values = [0, 1, 1, 0]
            visible.keyTimes = [0, 0.002, 0.998, 1]
            visible.beginTime = AVCoreAnimationBeginTimeAtZero + begin
            visible.duration = end - begin
            visible.fillMode = .forwards
            visible.isRemovedOnCompletion = false
            gate.add(visible, forKey: "text-visibility-\(item.id)")

            // Dense, linear Core Animation samples match the same per-segment
            // easing and curved path used by the preview.
            let samples = OverlayKeyframeSampler.samples(
                frames: frames, easing: item.easing,
                path: item.pathMode, stepsPerSegment: 8
            )
            let times = samples.map { NSNumber(value: $0.progress) }
            animate(outer, "position",
                    samples.map { NSValue(cgPoint: position($0, canvas: canvas)) },
                    times: times, begin: begin, duration: item.duration)
            animate(outer, "transform.scale",
                    samples.map { NSNumber(value: $0.scale / 0.45) },
                    times: times, begin: begin, duration: item.duration)
            animate(outer, "transform.rotation.z",
                    samples.map {
                        NSNumber(value: $0.rotationDegrees * .pi / 180)
                    },
                    times: times, begin: begin, duration: item.duration)
            animate(outer, "opacity",
                    samples.map { NSNumber(value: $0.opacity) },
                    times: times, begin: begin, duration: item.duration)
        }
    }

    private static func position(_ frame: OverlayKeyframe,
                                 canvas: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(frame.x) * canvas.width,
                y: (1 - CGFloat(frame.y)) * canvas.height)
    }

    private static func transform(_ frame: OverlayKeyframe) -> CATransform3D {
        let scale = CGFloat(frame.scale / 0.45)
        return CATransform3DConcat(
            CATransform3DMakeScale(scale, scale, 1),
            CATransform3DMakeRotation(
                CGFloat(frame.rotationDegrees) * .pi / 180, 0, 0, 1
            )
        )
    }

    private static func animate(
        _ layer: CALayer, _ keyPath: String,
        _ values: [Any], times: [NSNumber],
        begin: Double, duration: Double
    ) {
        guard values.count >= 2 && values.count == times.count else { return }
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.calculationMode = .linear
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + begin
        animation.duration = max(0.05, duration)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "title-\(keyPath)")
    }

    static func easing(_ mode: OverlayEasing) -> CAMediaTimingFunctionName {
        switch mode {
        case .linear: return .linear
        case .easeIn: return .easeIn
        case .easeOut: return .easeOut
        case .easeInOut: return .easeInEaseOut
        }
    }

    static func uiColor(hex: String) -> UIColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let number = UInt32(cleaned, radix: 16), cleaned.count == 6 else {
            return .white
        }
        return UIColor(red: CGFloat((number >> 16) & 255) / 255,
                       green: CGFloat((number >> 8) & 255) / 255,
                       blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}
