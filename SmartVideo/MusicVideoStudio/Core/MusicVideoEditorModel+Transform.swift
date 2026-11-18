import SwiftUI

extension MusicVideoStudio.MusicVideoEditorModel {
    typealias Studio = MusicVideoStudio

    /// Taps on the canvas pick the front-most layer under the finger (or clear the selection).
    func selectLayer(at point: CGPoint, canvas: CGSize, items: [Studio.RenderItem]) {
        if let id = Studio.LayerHitTest.topmost(at: point, items: items, canvas: canvas) {
            select(id, additive: false)
        } else if !multiSelect {
            clearSelection()
        }
    }

    /// Starts a gesture on `ids` (the editable selection). Returns false when there is nothing to move.
    private func beginTransform(canvas: CGSize, items: [Studio.RenderItem], anchor: UUID?) -> Bool {
        guard canvas.width > 1, canvas.height > 1 else { return false }
        let ids = editableSelection
        guard !ids.isEmpty else {
            if !selection.isEmpty { setStatus("Lớp đang bị khóa: mở khóa để di chuyển.") }
            return false
        }
        var originals: [UUID: Studio.LayerTransform] = [:]
        for core in project.allCores where ids.contains(core.id) { originals[core.id] = core.transform }
        guard let first = anchor.flatMap({ originals[$0] != nil ? $0 : nil }) ?? originals.keys.first else { return false }
        let others = items.map(\.core).filter { !ids.contains($0.id) }
        let targets = Studio.TransformMath.targets(from: others)
        beginEdit()                                           // the whole gesture is one undo step
        transformSession = Studio.TransformSession(
            originals: originals, anchor: first, targetsX: targets.x, targetsY: targets.y,
            thresholdX: Studio.TransformMath.snapPoints / Double(canvas.width),
            thresholdY: Studio.TransformMath.snapPoints / Double(canvas.height))
        return true
    }

    private func applyTransformSession() {
        guard let session = transformSession else { return }
        let result = Studio.TransformMath.resolve(session)
        mutate { project in
            for (id, transform) in result.transforms { _ = project.updateCore(id) { $0.transform = transform } }
        }
        if transformGuides != result.guides { transformGuides = result.guides }
    }

    /// One-finger drag. `start` is where the finger first touched, in canvas points.
    func transformDrag(translation: CGSize, start: CGPoint, canvas: CGSize, items: [Studio.RenderItem]) {
        if transformSession == nil {
            var anchor = items.reversed().first {
                editableSelection.contains($0.id) && Studio.LayerHitTest.contains(start, item: $0, canvas: canvas)
            }?.id
            if anchor == nil, let top = Studio.LayerHitTest.topmost(at: start, items: items, canvas: canvas) {
                select(top, additive: false)                  // dragging an unselected layer selects it
                anchor = top
            }
            guard anchor != nil, beginTransform(canvas: canvas, items: items, anchor: anchor) else { return }
        }
        transformSession?.dx = Double(translation.width / max(1, canvas.width))
        transformSession?.dy = Double(translation.height / max(1, canvas.height))
        applyTransformSession()
    }

    func transformPinch(scale: Double, canvas: CGSize, items: [Studio.RenderItem]) {
        if transformSession == nil, !beginTransform(canvas: canvas, items: items, anchor: nil) { return }
        transformSession?.scale = scale
        applyTransformSession()
    }

    func transformRotate(degrees: Double, canvas: CGSize, items: [Studio.RenderItem]) {
        if transformSession == nil, !beginTransform(canvas: canvas, items: items, anchor: nil) { return }
        transformSession?.rotation = degrees
        applyTransformSession()
    }

    func endTransform() {
        transformSession = nil
        if !transformGuides.isEmpty { transformGuides = Studio.TransformGuides() }
    }
}
