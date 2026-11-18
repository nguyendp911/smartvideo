import SwiftUI

extension MusicVideoStudio {
    /// The record. Rotation angle = `VinylMath.angle(rpm, local time)`: a function of the
    /// clock, so pause stops it and a seek puts it exactly where it would be.
    struct VinylLayerView: View {
        let layer: VinylLayer
        let canvas: CGSize
        let time: ProjectTime
        let coverURL: URL?
        let selected: Bool
        @State private var cover: UIImage?

        init(layer: VinylLayer, canvas: CGSize, time: ProjectTime, coverURL: URL?, selected: Bool) {
            self.layer = layer
            self.canvas = canvas
            self.time = time
            self.coverURL = coverURL
            self.selected = selected
            if let coverURL {
                _cover = State(initialValue: PhotoImageCache.shared.cached(coverURL, maxPixel: 512))
            }
        }

        var body: some View {
            let t = layer.core.transform
            let diameter = VinylMath.diameter(canvas: canvas, size: layer.size) * CGFloat(t.scale)
            let angle = VinylMath.angle(rpm: layer.rpm,
                                        localSeconds: VinylMath.localSeconds(layerStart: layer.core.start, at: time),
                                        phase: layer.phase)
            ZStack {
                VinylRecordView(layer: layer, diameter: diameter, angle: angle, cover: cover)
                if selected { Circle().strokeBorder(Color.cyan, lineWidth: 2).frame(width: diameter, height: diameter) }
            }
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(t.rotation))
            .position(x: canvas.width * CGFloat(t.x), y: canvas.height * CGFloat(t.y))
            .opacity(t.opacity)
            .frame(width: canvas.width, height: canvas.height)
            .task(id: coverURL) {
                guard let coverURL else { cover = nil; return }
                if cover == nil { cover = PhotoImageCache.shared.cached(coverURL, maxPixel: 512) }
                if cover == nil { cover = await PhotoImageCache.shared.load(coverURL, maxPixel: 512) }
            }
        }
    }

    struct VinylRecordView: View {
        let layer: VinylLayer
        let diameter: CGFloat
        let angle: Double
        let cover: UIImage?

        private func color(_ hex: String, _ fallback: Color) -> Color {
            guard let c = HexColor.components(hex) else { return fallback }
            return Color(red: c.r, green: c.g, blue: c.b)
        }

        var body: some View {
            let labelD = diameter * CGFloat(min(0.7, max(0.15, layer.labelScale)))
            ZStack {
                // Glow behind the disc.
                Circle().fill(color(layer.glowColorHex, .cyan))
                    .frame(width: diameter * 1.02, height: diameter * 1.02)
                    .blur(radius: diameter * 0.12)
                    .opacity(min(1, max(0, layer.glow)) * 0.9)

                // The disc itself (this part turns).
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(white: 0.17), Color(white: 0.035)],
                                                 center: .center, startRadius: 0, endRadius: diameter / 2))
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = min(size.width, size.height) / 2
                        let inner = radius * CGFloat(min(0.7, max(0.15, layer.labelScale))) * 1.05
                        var r = inner
                        var i = 0
                        while r < radius * 0.985 {
                            let shade = 0.025 + 0.04 * Double((i * 37) % 11) / 10          // deterministic grooves
                            var path = Path()
                            path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                            context.stroke(path, with: .color(.white.opacity(shade)), lineWidth: 0.6)
                            r += max(1.4, radius / 120)
                            i += 1
                        }
                        // Track gaps: darker rings between songs.
                        for f in [0.55, 0.72, 0.86] {
                            let gr = radius * CGFloat(f)
                            guard gr > inner else { continue }
                            var gap = Path()
                            gap.addEllipse(in: CGRect(x: center.x - gr, y: center.y - gr, width: gr * 2, height: gr * 2))
                            context.stroke(gap, with: .color(.black.opacity(0.7)), lineWidth: max(1.5, radius / 90))
                        }
                        // A few scratches / dust specks that rotate with the record (makes the spin visible).
                        for k in 0..<7 {
                            let a = Double(k) * 0.9 + 0.3
                            let rr = radius * CGFloat(0.45 + 0.07 * Double(k % 5))
                            var scratch = Path()
                            scratch.addArc(center: center, radius: rr, startAngle: .radians(a), endAngle: .radians(a + 0.16), clockwise: false)
                            context.stroke(scratch, with: .color(.white.opacity(0.22)), lineWidth: 1)
                        }
                    }
                    // Label with the cover.
                    ZStack {
                        Circle().fill(color(layer.labelColorHex, .red))
                        if let cover {
                            Image(uiImage: cover).resizable().scaledToFill().frame(width: labelD, height: labelD).clipShape(Circle())
                        }
                        Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: max(1, labelD * 0.02))
                        Circle().fill(Color.black.opacity(0.85)).frame(width: labelD * 0.09, height: labelD * 0.09)
                        Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1).frame(width: labelD * 0.09, height: labelD * 0.09)
                    }
                    .frame(width: labelD, height: labelD)
                }
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(min(1, max(0, layer.shadow)) * 0.75),
                        radius: diameter * 0.05, x: diameter * 0.015, y: diameter * 0.04)

                // Light reflection: fixed in the room, so it does NOT turn with the disc.
                Circle()
                    .fill(AngularGradient(gradient: Gradient(stops: [
                        .init(color: .white.opacity(0), location: 0.00),
                        .init(color: .white.opacity(0.55), location: 0.08),
                        .init(color: .white.opacity(0), location: 0.17),
                        .init(color: .white.opacity(0), location: 0.50),
                        .init(color: .white.opacity(0.4), location: 0.58),
                        .init(color: .white.opacity(0), location: 0.67),
                        .init(color: .white.opacity(0), location: 1.00)
                    ]), center: .center, angle: .degrees(-35)))
                    .frame(width: diameter, height: diameter)
                    .opacity(min(1, max(0, layer.reflection)) * 0.55)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
    }
}
