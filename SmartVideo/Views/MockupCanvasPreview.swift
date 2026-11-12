import SwiftUI

/// Fast on-canvas position/motion guides. True segmentation and all Core
/// Image blend modes are evaluated in rendered 720p preview/MP4.
struct MockupCanvasPreview: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let second: Double
    let canvas: CGSize
    let editable: Bool

    var body: some View {
        ZStack {
            ForEach(model.mockupOverlays) { item in
                if item.isVisible && second >= item.start &&
                    second <= item.end {
                    MockupCanvasLayer(
                        model: model, selectedID: $selectedID,
                        item: item, second: second,
                        canvas: canvas, editable: editable
                    )
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .allowsHitTesting(editable)
    }
}

private struct MockupCanvasLayer: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let item: MockupOverlayClip
    let second: Double
    let canvas: CGSize
    let editable: Bool
    @State private var artwork: UIImage?

    private var state: MockupMotionState {
        MockupAnimationSampler.sample(
            item, atProjectTime: second
        )
    }

    var body: some View {
        ZStack {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: canvas.width,
                        height: canvas.height
                    )
                    .clipped()
                    .opacity(state.opacity)
                    .scaleEffect(
                        x: CGFloat(state.scale) *
                            (item.flipHorizontal ? -1 : 1),
                        y: CGFloat(state.scale) *
                            (item.flipVertical ? -1 : 1)
                    )
                    .rotationEffect(.degrees(state.rotation))
                    .blur(radius: CGFloat(
                        min(6, item.blurRadius * 0.15)
                    ))
                    .blendMode(blendMode(item.blendMode))
            }
            if editable && selectedID == item.id {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.orange, lineWidth: 1.5)
                    .frame(width: canvas.width * 0.55,
                           height: canvas.height * 0.65)
                    .allowsHitTesting(false)
                Image(systemName: "viewfinder")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .position(
            x: canvas.width * CGFloat(state.x),
            y: canvas.height * CGFloat(state.y)
        )
        .gesture(
            DragGesture(minimumDistance: 0,
                        coordinateSpace: .named("captionCanvas"))
                .onChanged { value in
                    guard editable, !item.locked,
                          let index = model.mockupOverlays.firstIndex(
                            where: { $0.id == item.id }
                          ),
                          canvas.width > 0, canvas.height > 0 else {
                        return
                    }
                    selectedID = item.id
                    model.mockupOverlays[index].centerX =
                        min(1.5, max(-0.5,
                            Double(value.location.x /
                                   canvas.width)))
                    model.mockupOverlays[index].centerY =
                        min(1.5, max(-0.5,
                            Double(value.location.y /
                                   canvas.height)))
                }
        )
        .task(id: "\(item.effectID)|\(item.assetURL?.path ?? "")") {
            if let asset = item.assetURL {
                artwork = UIImage(
                    contentsOfFile: asset.path
                )
            } else {
                artwork = MockupProceduralTexture.artwork(
                    id: item.effectID, preview: true
                )
            }
        }
    }

    private func blendMode(_ item: MockupBlendMode) -> BlendMode {
        switch item {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .add: return .plusLighter
        case .darken: return .darken
        case .lighten: return .lighten
        }
    }
}
