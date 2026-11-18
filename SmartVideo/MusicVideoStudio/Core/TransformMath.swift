import Foundation
import CoreGraphics

extension MusicVideoStudio {
    /// Alignment lines to draw while a drag is snapped (normalised canvas coordinates).
    struct TransformGuides: Equatable {
        var x: Double?
        var y: Double?
        var rotationSnapped = false
        var isEmpty: Bool { x == nil && y == nil && !rotationSnapped }
    }

    /// One drag / pinch / rotate on the canvas. The three components arrive from three
    /// gestures at different times; the result is always computed from the ORIGINAL
    /// transforms, so it never drifts and one gesture is one undo step.
    struct TransformSession {
        var originals: [UUID: LayerTransform]
        /// The layer whose centre snaps; the others keep their offset from it.
        var anchor: UUID
        var targetsX: [Double]
        var targetsY: [Double]
        /// Snap distance in normalised units (a few points on screen).
        var thresholdX: Double
        var thresholdY: Double
        /// Normalised translation (fraction of canvas width / height).
        var dx = 0.0
        var dy = 0.0
        var scale = 1.0
        var rotation = 0.0
    }

    enum TransformMath {
        static let snapPoints = 6.0
        static let rotationStep = 45.0
        static let rotationThreshold = 3.0
        /// Canvas edges, the 5 % safe margins and the centre.
        static let baseTargets: [Double] = [0, 0.05, 0.5, 0.95, 1]

        /// Snap targets: the canvas lines plus the centres of the layers that are NOT moving.
        static func targets(from others: [LayerCore]) -> (x: [Double], y: [Double]) {
            var xs = baseTargets, ys = baseTargets
            for core in others where core.isVisible && core.transform.x.isFinite && core.transform.y.isFinite {
                xs.append(core.transform.x)
                ys.append(core.transform.y)
            }
            return (xs, ys)
        }

        /// The nearest target within `threshold`, or the value untouched.
        static func snap(_ value: Double, to targets: [Double], threshold: Double) -> (value: Double, target: Double?) {
            var best: Double?
            var bestDistance = threshold
            for target in targets {
                let distance = abs(value - target)
                if distance <= bestDistance { best = target; bestDistance = distance }
            }
            if let best { return (best, best) }
            return (value, nil)
        }

        /// Snaps to multiples of 45 degrees when within 3 degrees.
        static func snapRotation(_ degrees: Double) -> (value: Double, snapped: Bool) {
            guard degrees.isFinite else { return (0, false) }
            let nearest = (degrees / rotationStep).rounded() * rotationStep
            if abs(degrees - nearest) <= rotationThreshold { return (nearest, true) }
            return (degrees, false)
        }

        static func resolve(_ session: TransformSession) -> (transforms: [UUID: LayerTransform], guides: TransformGuides) {
            guard let anchor = session.originals[session.anchor] else { return ([:], TransformGuides()) }
            var dx = session.dx.isFinite ? session.dx : 0
            var dy = session.dy.isFinite ? session.dy : 0
            var guides = TransformGuides()
            if dx != 0 {
                let result = snap(anchor.x + dx, to: session.targetsX, threshold: session.thresholdX)
                if let target = result.target { dx = result.value - anchor.x; guides.x = target }
            }
            if dy != 0 {
                let result = snap(anchor.y + dy, to: session.targetsY, threshold: session.thresholdY)
                if let target = result.target { dy = result.value - anchor.y; guides.y = target }
            }
            let factor = session.scale.isFinite && session.scale > 0 ? session.scale : 1
            var turn = session.rotation.isFinite ? session.rotation : 0
            if turn != 0 {
                let result = snapRotation(anchor.rotation + turn)
                if result.snapped { turn = result.value - anchor.rotation; guides.rotationSnapped = true }
            }
            var out: [UUID: LayerTransform] = [:]
            for (id, original) in session.originals {
                var t = original
                t.x = original.x + dx
                t.y = original.y + dy
                t.scale = original.scale * factor
                t.rotation = (original.rotation + turn).truncatingRemainder(dividingBy: 360)
                out[id] = t.sanitized
            }
            return (out, guides)
        }
    }

    /// Where a layer sits on the canvas, for tapping and for starting a drag.
    /// Boxes are close estimates (text and lyrics width depend on the font), enough to pick a layer.
    enum LayerHitTest {
        static func boxSize(of item: RenderItem, canvas: CGSize) -> CGSize {
            switch item {
            case .photo(let layer):
                if layer.fit == .fill { return canvas }
                let ratio = CGFloat(layer.aspectRatio), canvasRatio = canvas.width / max(1, canvas.height)
                return ratio > canvasRatio ? CGSize(width: canvas.width, height: canvas.width / ratio)
                                           : CGSize(width: canvas.height * ratio, height: canvas.height)
            case .text(let layer):
                let font = CGFloat(layer.fontSize) * canvas.height
                let rows = layer.text.components(separatedBy: .newlines)
                let longest = CGFloat(rows.map(\.count).max() ?? 1)
                return CGSize(width: min(canvas.width * 0.92, max(font, longest * font * 0.6)) + 8,
                              height: font * 1.35 * CGFloat(max(1, rows.count)) + 8)
            case .lyrics(let layer):
                let font = CGFloat(layer.fontSize) * canvas.height
                return CGSize(width: canvas.width * 0.9, height: font * (layer.showNextLine ? 2.8 : 1.5))
            case .vinyl(let layer):
                let side = CGFloat(layer.size) * min(canvas.width, canvas.height)
                return CGSize(width: side, height: side)
            case .visualizer(let layer):
                return CGSize(width: canvas.width * CGFloat(layer.width), height: canvas.height * CGFloat(layer.height))
            }
        }

        static func contains(_ point: CGPoint, item: RenderItem, canvas: CGSize) -> Bool {
            let t = item.core.transform
            guard point.x.isFinite, point.y.isFinite, t.scale > 0 else { return false }
            let size = boxSize(of: item, canvas: canvas)
            let center = CGPoint(x: canvas.width * CGFloat(t.x), y: canvas.height * CGFloat(t.y))
            // Into the layer's own axes: undo rotation, then scale.
            let angle = -t.rotation * Double.pi / 180
            let dx = Double(point.x - center.x), dy = Double(point.y - center.y)
            let lx = (dx * cos(angle) - dy * sin(angle)) / t.scale
            let ly = (dx * sin(angle) + dy * cos(angle)) / t.scale
            return abs(lx) <= Double(size.width) / 2 && abs(ly) <= Double(size.height) / 2
        }

        /// `items` in draw order (back to front); the front-most hit wins. Hidden layers are skipped.
        static func topmost(at point: CGPoint, items: [RenderItem], canvas: CGSize) -> UUID? {
            for item in items.reversed() where item.core.isVisible && contains(point, item: item, canvas: canvas) {
                return item.id
            }
            return nil
        }
    }
}
