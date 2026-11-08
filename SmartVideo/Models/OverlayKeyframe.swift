import Foundation

/// A point on an image overlay's animation curve. Progress is normalized to
/// 0...1 of the overlay duration, so trimming duration preserves the motion.
struct OverlayKeyframe: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var progress: Double
    var x: Double
    var y: Double
    var scale: Double
    var opacity: Double
    var rotationDegrees: Double

    init(progress: Double, x: Double, y: Double,
         scale: Double, opacity: Double, rotationDegrees: Double) {
        self.progress = progress
        self.x = x
        self.y = y
        self.scale = scale
        self.opacity = opacity
        self.rotationDegrees = rotationDegrees
    }
}

/// Shared sampler for preview and exported animation. Easing is applied on
/// every segment, not across the whole track; this keeps the chosen points
/// fixed when the overlay contains three or more keyframes.
enum OverlayKeyframeSampler {
    static func frames(for overlay: ImageOverlayClip) -> [OverlayKeyframe] {
        if overlay.keyframes.count >= 2 {
            let sorted = overlay.keyframes
                .filter { $0.progress.isFinite }
                .sorted { $0.progress < $1.progress }
            if sorted.count >= 2 {
                var valid: [OverlayKeyframe] = []
                for var frame in sorted {
                    frame.progress = min(1, max(0, frame.progress))
                    frame.x = min(1, max(0, frame.x))
                    frame.y = min(1, max(0, frame.y))
                    frame.scale = min(0.95, max(0.10, frame.scale))
                    frame.opacity = min(1, max(0, frame.opacity))
                    frame.rotationDegrees = min(360, max(-360, frame.rotationDegrees))
                    if let last = valid.last,
                       frame.progress - last.progress < 0.0005 { continue }
                    valid.append(frame)
                }
                if valid.count >= 2 { return valid }
            }
        }
        // Backwards compatibility for images made in v2.9–v3.6:
        // animate only the original two position points.
        return [
            OverlayKeyframe(
                progress: 0, x: overlay.startX, y: overlay.startY,
                scale: overlay.scale, opacity: overlay.opacity,
                rotationDegrees: overlay.rotationDegrees
            ),
            OverlayKeyframe(
                progress: 1, x: overlay.endX, y: overlay.endY,
                scale: overlay.scale, opacity: overlay.opacity,
                rotationDegrees: overlay.rotationDegrees
            )
        ]
    }

    static func sample(_ overlay: ImageOverlayClip,
                       atProgress raw: Double) -> OverlayKeyframe {
        let frames = frames(for: overlay)
        let progress = min(1, max(0, raw.isFinite ? raw : 0))
        guard let first = frames.first, let last = frames.last else {
            return OverlayKeyframe(
                progress: progress, x: 0.5, y: 0.5, scale: 0.45,
                opacity: 1, rotationDegrees: 0
            )
        }
        if progress <= first.progress { return first }
        if progress >= last.progress { return last }

        for i in 0..<(frames.count - 1) {
            let a = frames[i], b = frames[i + 1]
            if progress < a.progress || progress > b.progress { continue }
            let range = max(0.0001, b.progress - a.progress)
            let fraction = (progress - a.progress) / range
            let t = ease(fraction, mode: overlay.easing)
            func mix(_ x: Double, _ y: Double) -> Double {
                x + (y - x) * t
            }
            return OverlayKeyframe(
                progress: progress,
                x: mix(a.x, b.x),
                y: mix(a.y, b.y),
                scale: mix(a.scale, b.scale),
                opacity: mix(a.opacity, b.opacity),
                rotationDegrees: mix(a.rotationDegrees, b.rotationDegrees)
            )
        }
        return last
    }

    static func ease(_ value: Double, mode: OverlayEasing) -> Double {
        let t = min(1, max(0, value))
        switch mode {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInOut: return t * t * (3 - 2 * t)
        }
    }
}
