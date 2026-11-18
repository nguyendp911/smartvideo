import Foundation

extension MusicVideoStudio {
    enum PhotoTransitionKind: String, Codable, CaseIterable, Identifiable {
        case none = "Cắt thẳng"
        case crossfade = "Hòa tan"
        case slideLeft = "Trượt từ phải"
        case slideRight = "Trượt từ trái"
        case slideUp = "Trượt từ dưới"
        case zoom = "Phóng vào"
        case slideDown = "Trượt từ trên"
        case spin = "Xoay vào"
        case blur = "Nhòe vào"
        case bounce = "Nảy lên"
        case flip = "Lật"
        case wipe = "Quét ngang"
        var id: String { rawValue }
    }

    /// Transition INTO a photo (played over its first `duration` seconds).
    struct PhotoTransition: Codable, Hashable {
        var kind = PhotoTransitionKind.none
        var duration = 0.8

        static let durationRange = 0.2...3.0
        var isActive: Bool { kind != .none }
    }

    /// Pure transition maths. The incoming photo animates over whatever is
    /// below it; when the previous photo overlaps in time (see
    /// `TimelineEditing.packPhotos`) that is a true cross transition.
    enum PhotoTransitionEngine {
        struct Effect: Equatable {
            var opacity = 1.0
            var scale = 1.0
            /// Fractions of the canvas width / height.
            var offsetX = 0.0
            var offsetY = 0.0
            /// Extra rotation in degrees (Spin).
            var rotation = 0.0
            /// Blur radius as a fraction of the canvas' short side.
            var blur = 0.0
            /// Rotation around the vertical axis in degrees (Flip).
            var flip = 0.0
            /// Fraction of the width revealed from the left; nil = everything (Wipe).
            var reveal: Double?
            static let identity = Effect()
        }

        static func smooth(_ p: Double) -> Double {
            let x = min(1, max(0, p.isFinite ? p : 0))
            return x * x * (3 - 2 * x)
        }

        /// Overshoots 1 a little, then settles (0 -> 1).
        static func easeOutBack(_ p: Double) -> Double {
            let c1 = 1.70158, c3 = c1 + 1
            let x = p - 1
            return 1 + c3 * x * x * x + c1 * x * x
        }

        /// The duration actually used: never longer than 90% of the photo.
        static func effectiveDuration(_ transition: PhotoTransition, layerDuration: ProjectTime) -> ProjectTime {
            let wanted = min(PhotoTransition.durationRange.upperBound,
                             max(PhotoTransition.durationRange.lowerBound, transition.duration.isFinite ? transition.duration : 0.8))
            return ProjectTime(seconds: min(wanted, layerDuration.seconds * 0.9))
        }

        /// Progress 0...1 while the transition plays, nil otherwise.
        static func progress(_ transition: PhotoTransition, start: ProjectTime, duration: ProjectTime,
                             at time: ProjectTime) -> Double? {
            guard transition.isActive else { return nil }
            let length = effectiveDuration(transition, layerDuration: duration)
            guard length.ticks > 0, time >= start, time < start + length else { return nil }
            return Double((time - start).ticks) / Double(length.ticks)
        }

        static func effect(_ kind: PhotoTransitionKind, progress rawProgress: Double) -> Effect {
            let p = smooth(rawProgress)
            switch kind {
            case .none: return .identity
            case .crossfade: return Effect(opacity: p)
            case .slideLeft: return Effect(offsetX: 1 - p)
            case .slideRight: return Effect(offsetX: -(1 - p))
            case .slideUp: return Effect(offsetY: 1 - p)
            case .zoom: return Effect(opacity: p, scale: 1.35 - 0.35 * p)
            case .slideDown: return Effect(offsetY: -(1 - p))
            case .spin: return Effect(opacity: p, scale: 1.4 - 0.4 * p, rotation: -35 * (1 - p))
            case .blur: return Effect(opacity: p, blur: 0.05 * (1 - p))
            case .bounce:
                let raw = min(1, max(0, rawProgress.isFinite ? rawProgress : 0))
                return Effect(opacity: min(1, raw * 4), scale: easeOutBack(raw))
            case .flip: return Effect(flip: -90 * (1 - p))
            case .wipe: return Effect(reveal: p)
            }
        }

        static func effect(for layer: PhotoLayer, at time: ProjectTime) -> Effect {
            guard let p = progress(layer.transitionIn, start: layer.core.start, duration: layer.core.duration, at: time) else {
                return .identity
            }
            return effect(layer.transitionIn.kind, progress: p)
        }
    }
}
