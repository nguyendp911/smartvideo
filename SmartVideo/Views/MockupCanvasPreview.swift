import SwiftUI

/// Lightweight preview of the same procedural textures used by Core Image
/// in the final MP4. The actual Vision person-depth compositing is evaluated
/// when the user renders the synchronized 720p preview or finished MP4.
struct MockupCanvasPreview: View {
    let mockups: [MockupOverlayClip]
    let second: Double
    let canvas: CGSize

    var body: some View {
        ZStack {
            ForEach(mockups.prefix(12)) { layer in
                if MockupAnimationSampler.active(layer, at: second),
                   let asset = MockupAssetLibrary.asset(layer.assetID) {
                    let state = MockupAnimationSampler.sample(
                        layer, at: second
                    )
                    Image(uiImage: MockupOverlayRenderer.texture(
                        for: asset
                    ))
                    .resizable()
                    .frame(
                        width: max(canvas.width, canvas.height)
                            * CGFloat(state.scale),
                        height: max(canvas.width, canvas.height)
                            * CGFloat(state.scale)
                    )
                    .scaleEffect(
                        x: layer.flipHorizontal ? -1 : 1,
                        y: layer.flipVertical ? -1 : 1
                    )
                    .rotationEffect(
                        .degrees(state.rotation)
                    )
                    .blur(radius: min(12, layer.blurRadius *
                                      Double(canvas.width) / 640))
                    .opacity(state.opacity)
                    .blendMode(blend(layer.blendMode))
                    .position(
                        x: canvas.width * CGFloat(state.x),
                        y: canvas.height * CGFloat(state.y)
                    )
                }
            }
        }
        .frame(width: canvas.width,
               height: canvas.height)
        .clipped()
        .allowsHitTesting(false)
    }

    private func blend(_ mode: MockupBlendMode) -> BlendMode {
        switch mode {
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
