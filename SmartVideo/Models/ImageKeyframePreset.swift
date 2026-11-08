import Foundation

enum ImageKeyframePreset: String, CaseIterable, Identifiable {
    case punchIn = "Zoom điện ảnh"
    case slideUp = "Trượt từ dưới"
    case pulse = "Nhịp phóng"
    case spin = "Xoay 360°"
    case fade = "Xuất hiện / tan"

    var id: String { rawValue }

    func makeFrames(from overlay: ImageOverlayClip) -> [OverlayKeyframe] {
        let x = overlay.startX
        let y = overlay.startY
        let scale = min(0.95, max(0.1, overlay.scale))
        func point(_ t: Double, _ x: Double, _ y: Double,
                   _ z: Double, _ alpha: Double, _ rotation: Double = 0
        ) -> OverlayKeyframe {
            OverlayKeyframe(
                progress: t, x: x, y: y, scale: z,
                opacity: alpha, rotationDegrees: rotation
            )
        }
        switch self {
        case .punchIn:
            return [point(0, x, y, max(0.1, scale * 0.60), 0.25),
                    point(0.24, x, y, scale, 1),
                    point(1, x, y, min(0.95, scale * 1.27), 1)]
        case .slideUp:
            return [point(0, x, 0.96, scale, 0.25),
                    point(0.30, x, y, scale, 1),
                    point(0.85, x, y, scale, 1),
                    point(1, x, 0.04, scale, 0)]
        case .pulse:
            return [point(0, x, y, scale, 1),
                    point(0.33, x, y, min(0.95, scale * 1.35), 1),
                    point(0.68, x, y, scale, 1),
                    point(1, x, y, min(0.95, scale * 1.15), 1)]
        case .spin:
            return [point(0, x, y, scale, 0.3, 0),
                    point(0.30, x, y, scale, 1, 120),
                    point(0.66, x, y, scale, 1, 240),
                    point(1, x, y, scale, 1, 360)]
        case .fade:
            return [point(0, x, y, scale, 0),
                    point(0.16, x, y, scale, 1),
                    point(0.80, x, y, scale, 1),
                    point(1, x, y, scale, 0)]
        }
    }
}
