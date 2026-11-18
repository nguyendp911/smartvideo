import SwiftUI

extension MusicVideoStudio {
    /// Gestures on the canvas: tap selects, drag moves, pinch scales, twist rotates the
    /// selected (unlocked) layers. Pure maths in `TransformMath`; this view only forwards touches.
    struct TransformOverlay: View {
        @ObservedObject var model: MusicVideoEditorModel
        let canvas: CGSize
        let items: [RenderItem]
        @GestureState private var dragging = false
        @GestureState private var pinching = false
        @GestureState private var rotating = false

        var body: some View {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: canvas.width, height: canvas.height)
                .gesture(SpatialTapGesture().onEnded { model.selectLayer(at: $0.location, canvas: canvas, items: items) })
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($dragging) { _, state, _ in state = true }
                        .onChanged { model.transformDrag(translation: $0.translation, start: $0.startLocation, canvas: canvas, items: items) }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($pinching) { _, state, _ in state = true }
                        .onChanged { model.transformPinch(scale: Double($0), canvas: canvas, items: items) }
                )
                .simultaneousGesture(
                    RotationGesture()
                        .updating($rotating) { _, state, _ in state = true }
                        .onChanged { model.transformRotate(degrees: $0.degrees, canvas: canvas, items: items) }
                )
                .onChange(of: dragging || pinching || rotating) { active in
                    if !active { model.endTransform() }
                }
                .accessibilityHidden(true)
        }
    }

    /// Snap lines (while dragging) and the optional centre cross + safe-area frame.
    struct TransformGuidesView: View {
        let guides: TransformGuides
        let showSafeArea: Bool
        let canvas: CGSize

        var body: some View {
            Canvas { context, size in
                if showSafeArea {
                    let inset = TransformMath.baseTargets[1]
                    let frame = CGRect(x: size.width * inset, y: size.height * inset,
                                       width: size.width * (1 - 2 * inset), height: size.height * (1 - 2 * inset))
                    context.stroke(Path(frame), with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    var cross = Path()
                    cross.move(to: CGPoint(x: size.width / 2, y: 0)); cross.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                    cross.move(to: CGPoint(x: 0, y: size.height / 2)); cross.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(cross, with: .color(.white.opacity(0.18)), lineWidth: 1)
                }
                let color = Color(red: 1, green: 0.25, blue: 0.7)
                if let x = guides.x {
                    var line = Path()
                    line.move(to: CGPoint(x: size.width * x, y: 0)); line.addLine(to: CGPoint(x: size.width * x, y: size.height))
                    context.stroke(line, with: .color(color), lineWidth: 1.5)
                }
                if let y = guides.y {
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: size.height * y)); line.addLine(to: CGPoint(x: size.width, y: size.height * y))
                    context.stroke(line, with: .color(color), lineWidth: 1.5)
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .allowsHitTesting(false)
        }
    }
}
