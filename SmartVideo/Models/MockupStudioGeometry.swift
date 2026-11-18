import Foundation
import CoreGraphics

/// Canvas geometry shared by hit-testing, selection outlines and snapping.
/// Positions are normalised (0...1, origin top-left); the canvas size is in points.
enum MockupStudioGeometry {
    /// Free-floating overlays are square textures scaled so that
    /// `scale == 1` covers the longer canvas side (same rule as the renderer).
    static func overlaySide(canvas: CGSize, scale: Double) -> CGFloat {
        max(canvas.width, canvas.height) * CGFloat(scale)
    }

    static func center(of clip: MockupOverlayClip, canvas: CGSize) -> CGPoint {
        CGPoint(x: canvas.width * CGFloat(clip.centerX), y: canvas.height * CGFloat(clip.centerY))
    }

    /// Is `point` (canvas coordinates) inside the layer's rotated square?
    static func contains(_ point: CGPoint, clip: MockupOverlayClip, canvas: CGSize) -> Bool {
        let c = center(of: clip, canvas: canvas)
        let half = overlaySide(canvas: canvas, scale: clip.scale) / 2
        let angle = -CGFloat(clip.rotationDegrees) * .pi / 180
        let dx = point.x - c.x, dy = point.y - c.y
        let rx = dx * cos(angle) - dy * sin(angle)
        let ry = dx * sin(angle) + dy * cos(angle)
        return abs(rx) <= half && abs(ry) <= half
    }

    /// Top-most layer under `point`, honouring visibility, locks and z-order
    /// (later in the array = higher). Only free-floating `candidates` are tested.
    static func hitTest(_ point: CGPoint, layers: [MockupOverlayClip], canvas: CGSize,
                        isFreeFloating: (MockupOverlayClip) -> Bool) -> MockupOverlayClip? {
        for layer in layers.reversed() where !layer.isHidden && isFreeFloating(layer) {
            if contains(point, clip: layer, canvas: canvas) { return layer }
        }
        return nil
    }

    /// Snap `value` to `target` when closer than `tolerance`.
    static func snap(_ value: Double, to target: Double = 0.5, tolerance: Double = 0.012) -> (value: Double, snapped: Bool) {
        abs(value - target) <= tolerance ? (target, true) : (value, false)
    }

    /// Normalised position after dragging by `translation` points.
    static func moved(from start: CGPoint, by translation: CGSize, canvas: CGSize) -> CGPoint {
        guard canvas.width > 0, canvas.height > 0 else { return start }
        return CGPoint(
            x: min(1.4, max(-0.4, start.x + translation.width / canvas.width)),
            y: min(1.4, max(-0.4, start.y + translation.height / canvas.height))
        )
    }

    static func clampedScale(_ value: Double, kind: MockupStudioKind?) -> Double {
        switch kind {
        case .scene: return min(4, max(1, value))
        case .background: return min(1.2, max(0.4, value))
        default: return min(3, max(0.1, value))
        }
    }

    /// Where an asset drawn with CSS-style `cover` lands in the canvas (top-left origin).
    static func coverRect(art: CGSize, in canvas: CGSize) -> CGRect {
        guard art.width > 0, art.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let scale = max(canvas.width / art.width, canvas.height / art.height)
        let size = CGSize(width: art.width * scale, height: art.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The transparent window of a scene mockup in canvas coordinates (top-left origin).
    static func windowRect(slot: MockupStudioSlot, art: CGSize, canvas: CGSize) -> CGRect {
        let cover = coverRect(art: art, in: canvas)
        return CGRect(x: cover.minX + CGFloat(slot.x) * cover.width,
                      y: cover.minY + CGFloat(slot.y) * cover.height,
                      width: CGFloat(slot.width) * cover.width,
                      height: CGFloat(slot.height) * cover.height)
    }

    /// Inset photo card of a background mockup (top-left origin); mirrors the renderer.
    static func backgroundCardRect(canvas: CGSize, scale: Double, centerX: Double, centerY: Double) -> CGRect {
        let card = CGFloat(min(0.95, max(0.3, 0.78 * scale)))
        let size = CGSize(width: canvas.width * card, height: canvas.height * card)
        let cx = canvas.width * CGFloat(min(1, max(0, centerX)))
        let cy = canvas.height * CGFloat(min(1, max(0, centerY)))
        return CGRect(x: cx - size.width / 2, y: cy - size.height / 2, width: size.width, height: size.height)
    }

    /// Wrap an angle to -180...180.
    static func wrappedDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}
