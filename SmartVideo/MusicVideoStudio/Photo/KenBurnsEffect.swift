import Foundation

extension MusicVideoStudio {
    enum PhotoMotionPreset: String, Codable, CaseIterable, Identifiable {
        case none = "Không"
        case zoomIn = "Phóng to"
        case zoomOut = "Thu nhỏ"
        case panLeft = "Lướt sang trái"
        case panRight = "Lướt sang phải"
        case panUp = "Lướt lên"
        case panDown = "Lướt xuống"
        case drift = "Trôi chậm"
        var id: String { rawValue }
    }

    /// Ken Burns settings of one photo.
    struct PhotoMotion: Codable, Hashable {
        var preset = PhotoMotionPreset.none
        /// How far the picture travels / zooms, as a fraction of the frame (0.03 ... 0.5).
        var intensity = 0.15

        static let intensityRange = 0.03...0.5
        var isActive: Bool { preset != .none }
    }

    /// Pure Ken Burns maths: the transform is a FUNCTION of the photo's local
    /// progress, so it is identical after any seek, pause or export.
    enum KenBurnsEffect {
        struct Transform: Equatable {
            var scale = 1.0
            /// Offsets are fractions of the canvas width / height.
            var offsetX = 0.0
            var offsetY = 0.0
            static let identity = Transform()
        }

        static func clampedProgress(_ p: Double) -> Double {
            p.isFinite ? min(1, max(0, p)) : 0
        }

        /// Progress 0...1 of `time` inside the layer's range.
        static func progress(start: ProjectTime, duration: ProjectTime, at time: ProjectTime) -> Double {
            guard duration.ticks > 0 else { return 0 }
            return clampedProgress(Double((time - start).ticks) / Double(duration.ticks))
        }

        static func transform(_ motion: PhotoMotion, progress rawProgress: Double) -> Transform {
            guard motion.isActive else { return .identity }
            let p = clampedProgress(rawProgress)
            let i = min(PhotoMotion.intensityRange.upperBound, max(PhotoMotion.intensityRange.lowerBound,
                                                                    motion.intensity.isFinite ? motion.intensity : 0.15))
            func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * p }
            // Panning needs the picture slightly larger than the frame so no edge shows.
            let bleed = 1 + i
            switch motion.preset {
            case .none: return .identity
            case .zoomIn: return Transform(scale: lerp(1, 1 + i))
            case .zoomOut: return Transform(scale: lerp(1 + i, 1))
            case .panLeft: return Transform(scale: bleed, offsetX: lerp(i / 2, -i / 2))
            case .panRight: return Transform(scale: bleed, offsetX: lerp(-i / 2, i / 2))
            case .panUp: return Transform(scale: bleed, offsetY: lerp(i / 2, -i / 2))
            case .panDown: return Transform(scale: bleed, offsetY: lerp(-i / 2, i / 2))
            case .drift: return Transform(scale: lerp(1 + i, 1 + i * 1.6), offsetX: lerp(-i / 3, i / 3), offsetY: lerp(i / 4, -i / 4))
            }
        }
    }
}
