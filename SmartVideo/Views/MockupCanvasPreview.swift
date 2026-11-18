import SwiftUI

/// Lightweight SwiftUI preview of free-floating mockup overlays on the main
/// editor canvas. Frames/products and backgrounds re-frame the photo, which
/// only the Core Image renderer can do: they show in Mockup Studio and in the
/// 720p preview / exported file, not in this quick view.
struct MockupCanvasPreview: View {
    let mockups: [MockupOverlayClip]
    let second: Double
    let canvas: CGSize

    var body: some View {
        ZStack {
            ForEach(mockups.prefix(12)) { layer in
                if MockupAnimationSampler.active(layer, at: second),
                   let image = previewImage(for: layer) {
                    layerView(layer, image: image)
                }
            }
        }
        .frame(width: canvas.width,
               height: canvas.height)
        .clipped()
        .allowsHitTesting(false)
    }

    private func previewImage(for layer: MockupOverlayClip) -> CGImage? {
        if let studio = MockupStudioCatalog.asset(layer.assetID), studio.kind != .overlay {
            return nil
        }
        return MockupOverlayRenderer.textureImage(forID: layer.assetID)
    }

    @ViewBuilder
    private func layerView(_ layer: MockupOverlayClip, image: CGImage) -> some View {
        let state = MockupAnimationSampler.sample(layer, at: second)
        let side = max(canvas.width, canvas.height) * CGFloat(state.scale)
        Image(decorative: image, scale: 1)
            .resizable()
            .frame(width: side, height: side)
            .scaleEffect(
                x: layer.flipHorizontal ? -1 : 1,
                y: layer.flipVertical ? -1 : 1
            )
            .rotationEffect(.degrees(state.rotation))
            .saturation(layer.saturation)
            .brightness(layer.brightness)
            .contrast(layer.contrast)
            .blur(radius: min(12, layer.blurRadius * Double(canvas.width) / 640))
            .opacity(state.opacity)
            .blendMode(blend(layer.blendMode))
            .position(
                x: canvas.width * CGFloat(state.x),
                y: canvas.height * CGFloat(state.y)
            )
            .modifier(CanvasMaskModifier(mask: layer.mask, canvas: canvas))
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
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .difference: return .difference
        }
    }
}

/// Applies the layer's soft mask in canvas coordinates.
private struct CanvasMaskModifier: ViewModifier {
    let mask: MockupMask
    let canvas: CGSize

    func body(content: Content) -> some View {
        if let image = MockupMaskRaster.alphaImage(for: mask) {
            content.mask(
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: canvas.width, height: canvas.height)
                    .position(x: canvas.width / 2, y: canvas.height / 2)
            )
        } else {
            content
        }
    }
}
