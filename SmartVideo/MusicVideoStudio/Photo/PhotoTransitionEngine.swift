import Foundation

extension MusicVideoStudio {
    enum PhotoTransitionKind: String, Codable, CaseIterable, Identifiable {
        case none = "Cắt thẳng"
        case crossfade = "Hòa tan"
        case slideLeft = "Trượt từ phải"
        case slideRight = "Trượt từ trái"
        case slideUp = "Trượt từ dưới"
        case zoom = "Phóng vào"
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
            static let identity = Effect()
        }

        static func smooth(_ p: Double) -> Double {
            let x = min(1, max(0, p.isFinite ? p : 0))
            return x * x * (3 - 2 * x)
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
