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
        if overlay.pathMode == .curved {
            return sample(frames: frames(for: overlay),
                          easing: overlay.easing, path: .curved,
                          atProgress: raw)
        }
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

    static func frames(for overlay: VideoOverlayClip) -> [OverlayKeyframe] {
        clean(overlay.keyframes) ?? [
            OverlayKeyframe(progress: 0, x: overlay.startX, y: overlay.startY,
                            scale: overlay.width, opacity: overlay.opacity,
                            rotationDegrees: 0),
            OverlayKeyframe(progress: 1, x: overlay.endX, y: overlay.endY,
                            scale: overlay.width, opacity: overlay.opacity,
                            rotationDegrees: 0)
        ]
    }

    static func frames(for overlay: TextOverlayClip) -> [OverlayKeyframe] {
        clean(overlay.keyframes) ?? [
            OverlayKeyframe(progress: 0, x: overlay.startX, y: overlay.startY,
                            scale: 0.45, opacity: overlay.opacity,
                            rotationDegrees: 0),
            OverlayKeyframe(progress: 1, x: overlay.endX, y: overlay.endY,
                            scale: 0.45, opacity: overlay.opacity,
                            rotationDegrees: 0)
        ]
    }

    static func sample(_ overlay: VideoOverlayClip,
                       atProgress progress: Double) -> OverlayKeyframe {
        sample(frames: frames(for: overlay), easing: overlay.easing,
               path: overlay.pathMode, atProgress: progress)
    }

    static func sample(_ overlay: TextOverlayClip,
                       atProgress progress: Double) -> OverlayKeyframe {
        sample(frames: frames(for: overlay), easing: overlay.easing,
               path: overlay.pathMode, atProgress: progress)
    }

    static func clean(_ frames: [OverlayKeyframe]) -> [OverlayKeyframe]? {
        guard frames.count >= 2 else { return nil }
        let sorted = frames.filter {
            $0.progress.isFinite && $0.x.isFinite && $0.y.isFinite &&
            $0.scale.isFinite && $0.opacity.isFinite &&
            $0.rotationDegrees.isFinite
        }.sorted { $0.progress < $1.progress }
        var result: [OverlayKeyframe] = []
        for var f in sorted.prefix(16) {
            f.progress = min(1, max(0, f.progress))
            f.x = min(1, max(0, f.x))
            f.y = min(1, max(0, f.y))
            f.scale = min(0.95, max(0.1, f.scale))
            f.opacity = min(1, max(0, f.opacity))
            f.rotationDegrees = min(360, max(-360, f.rotationDegrees))
            if let prior = result.last, f.progress - prior.progress < 0.0005 {
                continue
            }
            result.append(f)
        }
        return result.count >= 2 ? result : nil
    }

    static func sample(frames input: [OverlayKeyframe],
                       easing: OverlayEasing, path: OverlayMotionPath,
                       atProgress raw: Double) -> OverlayKeyframe {
        let frames = clean(input) ?? input
        let progress = min(1, max(0, raw.isFinite ? raw : 0))
        guard let first = frames.first else {
            return OverlayKeyframe(progress: progress, x: 0.5, y: 0.5,
                                   scale: 0.45, opacity: 1, rotationDegrees: 0)
        }
        if progress <= first.progress { return first }
        guard let last = frames.last else { return first }
        if progress >= last.progress { return last }
        for index in 0..<(frames.count - 1) {
            let a = frames[index], b = frames[index + 1]
            guard progress >= a.progress && progress <= b.progress else {
                continue
            }
            let part = (progress - a.progress) /
                max(0.00001, b.progress - a.progress)
            let t = ease(part, mode: easing)
            func lerp(_ v: Double, _ w: Double) -> Double {
                v + (w - v) * t
            }
            func curved(_ v0: Double, _ v1: Double,
                        _ v2: Double, _ v3: Double) -> Double {
                // Catmull-Rom Hermite: passes exactly through every authored
                // point while creating curved XY trajectories.
                let m1 = 0.5 * (v2 - v0)
                let m2 = 0.5 * (v3 - v1)
                let t2 = t * t
                let t3 = t2 * t
                return (2 * t3 - 3 * t2 + 1) * v1 +
                    (t3 - 2 * t2 + t) * m1 +
                    (-2 * t3 + 3 * t2) * v2 +
                    (t3 - t2) * m2
            }
            let previous = frames[max(0, index - 1)]
            let next = frames[min(frames.count - 1, index + 2)]
            let x = path == .curved && frames.count > 2 ?
                curved(previous.x, a.x, b.x, next.x) : lerp(a.x, b.x)
            let y = path == .curved && frames.count > 2 ?
                curved(previous.y, a.y, b.y, next.y) : lerp(a.y, b.y)
            return OverlayKeyframe(
                progress: progress,
                x: min(1, max(0, x)),
                y: min(1, max(0, y)),
                scale: lerp(a.scale, b.scale),
                opacity: lerp(a.opacity, b.opacity),
                rotationDegrees: lerp(a.rotationDegrees, b.rotationDegrees)
            )
        }
        return last
    }

    static func samples(frames: [OverlayKeyframe], easing: OverlayEasing,
                        path: OverlayMotionPath, stepsPerSegment: Int = 8
    ) -> [OverlayKeyframe] {
        guard let valid = clean(frames) else { return frames }
        let count = min(12, max(2, stepsPerSegment))
        var samples: [OverlayKeyframe] = []
        for index in 0..<(valid.count - 1) {
            let a = valid[index], b = valid[index + 1]
            for step in 0..<count {
                let t = a.progress +
                    (b.progress - a.progress) * Double(step) / Double(count)
                samples.append(sample(frames: valid, easing: easing,
                                      path: path, atProgress: t))
            }
        }
        if let last = valid.last { samples.append(last) }
        return samples
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
