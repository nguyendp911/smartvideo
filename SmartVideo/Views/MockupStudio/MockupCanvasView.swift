import SwiftUI

/// The editing canvas. The picture is the REAL Core Image composition (same
/// renderer as the exported file); this view only adds interaction on top:
/// tap to select, drag to move (snaps to the centre), pinch to scale, twist to
/// rotate, and drops from the library. Frames/products pan/zoom the photo in
/// their window, backgrounds move/resize the photo card.
struct MockupCanvasView: View {
    @ObservedObject var session: MockupStudioSession
    @ObservedObject var model: EditorViewModel

    @State private var dragStart: DragStart?
    @State private var pinchStart: (id: UUID, scale: Double)?
    @State private var twistStart: (id: UUID, degrees: Double)?
    @State private var guideX = false
    @State private var guideY = false
    @State private var dropTargeted = false

    private struct DragStart {
        var id: UUID?
        var centerX: Double
        var centerY: Double
        var kind: MockupStudioKind
        var checkpointed = false
    }

    var body: some View {
        GeometryReader { geo in
            let canvas = fitted(session.sourceSize, in: geo.size)
            ZStack {
                if session.hasSource {
                    ZStack {
                        if let image = session.rendered {
                            Image(uiImage: image).resizable().frame(width: canvas.width, height: canvas.height)
                        } else {
                            Color.black.frame(width: canvas.width, height: canvas.height)
                        }
                        selectionOutline(canvas: canvas)
                        guides(canvas: canvas)
                        if session.isRendering {
                            ProgressView().controlSize(.small).padding(6)
                                .background(.black.opacity(0.5), in: Capsule())
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(8)
                        }
                    }
                    .frame(width: canvas.width, height: canvas.height)
                    .clipped()
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(dropTargeted ? Color.cyan : Color.white.opacity(0.12), lineWidth: dropTargeted ? 3 : 1))
                    .contentShape(Rectangle())
                    .gesture(dragGesture(canvas: canvas))
                    .simultaneousGesture(magnifyGesture)
                    .simultaneousGesture(rotateGesture)
                    .dropDestination(for: String.self) { items, location in
                        guard let raw = items.first, raw.hasPrefix("mockup:"),
                              let asset = MockupStudioCatalog.asset(String(raw.dropFirst(7))) else { return false }
                        session.add(asset, at: CGPoint(x: location.x / canvas.width, y: location.y / canvas.height))
                        return true
                    } isTargeted: { dropTargeted = $0 }
                    .shadow(color: .black.opacity(0.5), radius: 12)
                } else {
                    emptyState
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
            Text(model.clips.isEmpty ? "Thêm ảnh hoặc video vào dự án trước, rồi mở lại Mockup Studio."
                                      : "Đang tải khung hình…")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
        }
    }

    private func fitted(_ source: CGSize, in available: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let pad: CGFloat = 16
        let box = CGSize(width: max(1, available.width - pad * 2), height: max(1, available.height - pad * 2))
        let scale = min(box.width / source.width, box.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    // MARK: Selection overlay

    @ViewBuilder
    private func selectionOutline(canvas: CGSize) -> some View {
        if let layer = session.selectedLayer, !layer.isHidden,
           MockupAnimationSampler.active(layer, at: session.context?.second ?? 0) {
            let kind = session.kindOf(layer)
            switch kind {
            case .overlay:
                let side = MockupStudioGeometry.overlaySide(canvas: canvas, scale: layer.scale)
                let c = MockupStudioGeometry.center(of: layer, canvas: canvas)
                outline(layer.locked).frame(width: side, height: side)
                    .rotationEffect(.degrees(layer.rotationDegrees))
                    .position(x: c.x, y: c.y)
            case .scene:
                if let asset = MockupStudioCatalog.asset(layer.assetID), let slot = asset.slot {
                    let r = MockupStudioGeometry.windowRect(
                        slot: slot, art: CGSize(width: asset.pixelWidth, height: asset.pixelHeight), canvas: canvas)
                    outline(layer.locked).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
                }
            case .background:
                let r = MockupStudioGeometry.backgroundCardRect(
                    canvas: canvas, scale: layer.scale, centerX: layer.centerX, centerY: layer.centerY)
                outline(layer.locked).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            }
        }
    }

    private func outline(_ locked: Bool) -> some View {
        Rectangle()
            .strokeBorder(locked ? Color.orange : Color.cyan, style: StrokeStyle(lineWidth: 1.5, dash: locked ? [] : [6, 4]))
            .allowsHitTesting(false)
    }

    private func guides(canvas: CGSize) -> some View {
        ZStack {
            if guideX { Rectangle().fill(Color.cyan.opacity(0.9)).frame(width: 1, height: canvas.height).position(x: canvas.width / 2, y: canvas.height / 2) }
            if guideY { Rectangle().fill(Color.cyan.opacity(0.9)).frame(width: canvas.width, height: 1).position(x: canvas.width / 2, y: canvas.height / 2) }
        }
        .allowsHitTesting(false)
    }

    // MARK: Gestures

    private func dragGesture(canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil { beginDrag(at: value.startLocation, canvas: canvas) }
                guard var start = dragStart, let id = start.id,
                      let index = model.mockupOverlays.firstIndex(where: { $0.id == id }),
                      !model.mockupOverlays[index].locked else { return }
                let moved = hypot(value.translation.width, value.translation.height)
                guard moved > 3 || start.checkpointed else { return }
                if !start.checkpointed {
                    session.beginEdit()
                    start.checkpointed = true
                    dragStart = start
                }
                switch start.kind {
                case .overlay, .background:
                    let p = MockupStudioGeometry.moved(
                        from: CGPoint(x: start.centerX, y: start.centerY), by: value.translation, canvas: canvas)
                    let sx = MockupStudioGeometry.snap(Double(p.x)), sy = MockupStudioGeometry.snap(Double(p.y))
                    guideX = sx.snapped; guideY = sy.snapped
                    model.mockupOverlays[index].centerX = sx.value
                    model.mockupOverlays[index].centerY = sy.value
                case .scene:
                    // Dragging moves the photo inside the window.
                    model.mockupOverlays[index].centerX = min(1, max(0, start.centerX - Double(value.translation.width / canvas.width)))
                    model.mockupOverlays[index].centerY = min(1, max(0, start.centerY - Double(value.translation.height / canvas.height)))
                }
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                if moved <= 3, dragStart?.id == nil { session.selectedID = nil }
                dragStart = nil
                guideX = false; guideY = false
            }
    }

    private func beginDrag(at point: CGPoint, canvas: CGSize) {
        let second = session.context?.second ?? 0
        let layers = session.clipLayers.filter { MockupAnimationSampler.active($0, at: second) }
        func free(_ layer: MockupOverlayClip) -> Bool { session.kindOf(layer) == .overlay }
        var target: MockupOverlayClip?
        if let selected = session.selectedLayer, free(selected), !selected.isHidden,
           MockupStudioGeometry.contains(point, clip: selected, canvas: canvas) {
            target = selected
        } else {
            target = MockupStudioGeometry.hitTest(point, layers: layers, canvas: canvas, isFreeFloating: free)
        }
        // Nothing free-floating under the finger: the frame/background itself.
        if target == nil {
            target = layers.last { session.kindOf($0) != .overlay && !$0.isHidden }
        }
        guard let target else { dragStart = DragStart(id: nil, centerX: 0, centerY: 0, kind: .overlay); return }
        session.selectedID = target.id
        dragStart = DragStart(id: target.id, centerX: target.centerX, centerY: target.centerY, kind: session.kindOf(target))
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard let layer = session.selectedLayer, !layer.locked else { return }
                if pinchStart == nil {
                    session.beginEdit()
                    pinchStart = (layer.id, layer.scale)
                }
                guard let start = pinchStart, let index = model.mockupOverlays.firstIndex(where: { $0.id == start.id }) else { return }
                let kind = session.kindOf(model.mockupOverlays[index])
                model.mockupOverlays[index].scale = MockupStudioGeometry.clampedScale(start.scale * Double(value), kind: kind)
            }
            .onEnded { _ in pinchStart = nil }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .onChanged { angle in
                guard let layer = session.selectedLayer, !layer.locked, session.kindOf(layer) == .overlay else { return }
                if twistStart == nil {
                    session.beginEdit()
                    twistStart = (layer.id, layer.rotationDegrees)
                }
                guard let start = twistStart, let index = model.mockupOverlays.firstIndex(where: { $0.id == start.id }) else { return }
                var degrees = MockupStudioGeometry.wrappedDegrees(start.degrees + angle.degrees)
                if abs(degrees) < 2.5 { degrees = 0 }
                model.mockupOverlays[index].rotationDegrees = degrees
            }
            .onEnded { _ in twistStart = nil }
    }
}
