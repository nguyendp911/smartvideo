import SwiftUI

extension MusicVideoStudio {
    /// Draws the overlay effects. Shake and Beat Pulse draw nothing: they move the picture (`SceneMotion`).
    struct EffectLayerView: View {
        let layer: EffectLayer
        let canvas: CGSize
        let time: ProjectTime
        /// Beats in project seconds (already filtered by `everyBeats`).
        let beats: [Double]
        let selected: Bool

        private func color(_ hex: String) -> Color {
            let c = HexColor.components(hex) ?? (r: 1, g: 1, b: 1)
            return Color(red: c.r, green: c.g, blue: c.b)
        }

        var body: some View {
            let intensity = min(1, max(0, layer.intensity))
            ZStack {
                switch layer.kind {
                case .vignette:
                    RadialGradient(colors: [.clear, Color.black.opacity(0.9 * intensity)],
                                   center: .center, startRadius: min(canvas.width, canvas.height) * 0.3,
                                   endRadius: hypot(canvas.width, canvas.height) * 0.55)
                case .grain:
                    Canvas { context, size in
                        let seed = EffectMath.grainFrame(time.seconds)
                        let count = min(5_000, Int(900 * size.width * size.height / 120_000))
                        let unitSize = max(1, size.height / 300)
                        for i in 0..<count {
                            let x = EffectMath.unit(i, seed &* 7 &+ 1) * size.width
                            let y = EffectMath.unit(i, seed &* 7 &+ 2) * size.height
                            let side = unitSize * (1 + EffectMath.unit(i, seed &* 7 &+ 3))
                            let light = EffectMath.unit(i, seed &* 7 &+ 4) > 0.5
                            let alpha = 0.5 * intensity * (0.4 + 0.6 * EffectMath.unit(i, seed &* 7 &+ 5))
                            context.fill(Path(CGRect(x: x, y: y, width: side, height: side)),
                                         with: .color((light ? Color.white : Color.black).opacity(alpha)))
                        }
                    }
                case .lightLeak:
                    let leak = EffectMath.lightLeak(layer, at: time)
                    let tint = color(layer.colorHex)
                    RadialGradient(colors: [tint.opacity(leak.opacity), tint.opacity(0)],
                                   center: UnitPoint(x: leak.x, y: leak.y), startRadius: 0,
                                   endRadius: max(canvas.width, canvas.height) * 0.7)
                        .blendMode(.screen)
                case .flash:
                    color(layer.colorHex).opacity(EffectMath.flash(layer, beats: beats, at: time.seconds))
                case .fadeBlack:
                    Color.black.opacity(EffectMath.fadeBlack(layer, at: time))
                case .scanlines:
                    Canvas { context, size in
                        let spacing = max(2, size.height / 120)
                        var y: CGFloat = 0
                        while y < size.height {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: spacing * 0.45)),
                                         with: .color(Color.black.opacity(0.45 * intensity)))
                            y += spacing
                        }
                    }
                case .shake, .beatPulse:
                    Color.clear
                }
            }
            .frame(width: canvas.width, height: canvas.height)
            .overlay { if selected { Rectangle().strokeBorder(Color.cyan.opacity(0.7), lineWidth: 2) } }
            .opacity(layer.core.transform.opacity)
            .allowsHitTesting(false)
        }
    }

    /// Wipe transition: shows only the left `reveal` fraction. Untouched when there is no wipe.
    struct RevealMaskModifier: ViewModifier {
        let reveal: Double?
        let canvas: CGSize

        @ViewBuilder func body(content: Content) -> some View {
            if let reveal {
                content.mask {
                    Rectangle()
                        .frame(width: canvas.width * CGFloat(min(1, max(0, reveal))), height: canvas.height)
                        .frame(width: canvas.width, height: canvas.height, alignment: .leading)
                }
            } else {
                content
            }
        }
    }

    /// Applies Shake / Beat Pulse to a picture layer.
    struct SceneMotionModifier: ViewModifier {
        let motion: SceneMotion
        let canvas: CGSize

        func body(content: Content) -> some View {
            content
                .scaleEffect(CGFloat(motion.scale))
                .rotationEffect(.degrees(motion.rotation))
                .offset(x: CGFloat(motion.dx) * canvas.width, y: CGFloat(motion.dy) * canvas.height)
        }
    }
}
