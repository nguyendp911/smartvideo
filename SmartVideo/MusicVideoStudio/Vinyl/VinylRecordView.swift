import SwiftUI

extension MusicVideoStudio {
    /// The record. Rotation angle = `VinylMath.angle(rpm, local time)`: a function of the
    /// clock, so pause stops it and a seek puts it exactly where it would be. The tonearm,
    /// the beat swell and the equalizer ring are functions of the clock / the analysed spectrum too.
    struct VinylLayerView: View {
        let layer: VinylLayer
        let canvas: CGSize
        let time: ProjectTime
        let coverURL: URL?
        let selected: Bool
        var audio: VisualizerFrame?
        @State private var cover: UIImage?

        init(layer: VinylLayer, canvas: CGSize, time: ProjectTime, coverURL: URL?, selected: Bool, audio: VisualizerFrame? = nil) {
            self.layer = layer
            self.canvas = canvas
            self.time = time
            self.coverURL = coverURL
            self.selected = selected
            self.audio = audio
            if let coverURL {
                _cover = State(initialValue: PhotoImageCache.shared.cached(coverURL, maxPixel: 512))
            }
        }

        var body: some View {
            let t = layer.core.transform
            let swell = audio.map { 1 + CGFloat(min(1, max(0, layer.beatPulse)) * 0.07 * $0.pulse) } ?? 1
            let diameter = VinylMath.diameter(canvas: canvas, size: layer.size) * CGFloat(t.scale) * swell
            let local = VinylMath.localSeconds(layerStart: layer.core.start, at: time)
            let angle = VinylMath.angle(rpm: layer.rpm, localSeconds: local, phase: layer.phase, spinUp: layer.spinUp)
            let head = VinylMath.tonearmHeadRadius(localSeconds: local + layer.phase, duration: layer.core.duration.seconds + layer.phase,
                                                   innerRadius: layer.labelScale + 0.08)
            ZStack {
                if layer.turntable { TurntableBase(diameter: diameter) }
                if layer.equalizerRing, let audio {
                    EqualizerRing(bands: audio.bands, diameter: diameter, colorHex: layer.ringColorHex, time: local)
                }
                VinylRecordView(layer: layer, diameter: diameter, angle: angle, cover: cover,
                                glowBoost: audio.map { min(1, $0.pulse) * layer.beatPulse * 0.5 } ?? 0)
                if layer.tonearm { TonearmView(diameter: diameter, headRadius: head) }
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

    /// Dark plinth with a platter ring and two knobs.
    struct TurntableBase: View {
        let diameter: CGFloat

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: diameter * 0.07)
                    .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: diameter * 1.38, height: diameter * 1.22)
                    .overlay(RoundedRectangle(cornerRadius: diameter * 0.07).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.55), radius: diameter * 0.05, x: 0, y: diameter * 0.03)
                Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: max(1, diameter * 0.012))
                    .frame(width: diameter * 1.06, height: diameter * 1.06)
                Circle().fill(Color(white: 0.3)).frame(width: diameter * 0.07, height: diameter * 0.07)
                    .offset(x: -diameter * 0.55, y: diameter * 0.47)
                Circle().fill(Color(white: 0.3)).frame(width: diameter * 0.05, height: diameter * 0.05)
                    .offset(x: -diameter * 0.43, y: diameter * 0.5)
            }
        }
    }

    /// Bars around the record that follow the music.
    struct EqualizerRing: View {
        let bands: [Float]
        let diameter: CGFloat
        let colorHex: String
        let time: Double

        var body: some View {
            let c = HexColor.components(colorHex) ?? (r: 0.3, g: 0.8, b: 0.9)
            let tint = Color(red: c.r, green: c.g, blue: c.b)
            Canvas { context, size in
                guard !bands.isEmpty else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = diameter / 2
                let inner = radius * 1.07
                let width = max(1.5, 2 * .pi * inner / CGFloat(bands.count) * 0.55)
                let spin = time * 0.08
                for (i, level) in bands.enumerated() {
                    let angle = spin + 2 * Double.pi * Double(i) / Double(bands.count) - Double.pi / 2
                    let length = max(2, CGFloat(min(1, max(0, level))) * radius * 0.4)
                    var path = Path()
                    path.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner))
                    path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * (inner + length), y: center.y + CGFloat(sin(angle)) * (inner + length)))
                    context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            .frame(width: diameter * 2, height: diameter * 2)
            .shadow(color: tint.opacity(0.7), radius: diameter * 0.03)
            .allowsHitTesting(false)
        }
    }

    /// Arm, counterweight and headshell. `headRadius` is in units of the record's radius.
    struct TonearmView: View {
        let diameter: CGFloat
        let headRadius: Double

        var body: some View {
            let angleDegrees = VinylMath.armAngle(headRadius: headRadius)
            Canvas { context, size in
                let unit = diameter / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: center.x + CGFloat(x) * unit, y: center.y + CGFloat(y) * unit) }
                let pivot = point(VinylMath.armPivot.x, VinylMath.armPivot.y)
                let tip = VinylMath.headPosition(armAngle: angleDegrees)
                let head = point(tip.x, tip.y)
                let dx = Double(head.x - pivot.x), dy = Double(head.y - pivot.y)
                let length = max(1, hypot(dx, dy))
                let ux = CGFloat(dx / length), uy = CGFloat(dy / length)
                // Counterweight behind the pivot.
                var back = Path()
                back.move(to: pivot)
                back.addLine(to: CGPoint(x: pivot.x - ux * unit * 0.3, y: pivot.y - uy * unit * 0.3))
                context.stroke(back, with: .color(Color(white: 0.25)), style: StrokeStyle(lineWidth: unit * 0.13, lineCap: .round))
                // The arm.
                var arm = Path()
                arm.move(to: pivot)
                arm.addLine(to: head)
                context.stroke(arm, with: .color(Color(white: 0.82)), style: StrokeStyle(lineWidth: unit * 0.045, lineCap: .round))
                // Headshell with the needle.
                var shell = Path()
                shell.move(to: head)
                shell.addLine(to: CGPoint(x: head.x + ux * unit * 0.16, y: head.y + uy * unit * 0.16))
                context.stroke(shell, with: .color(Color(white: 0.18)), style: StrokeStyle(lineWidth: unit * 0.11, lineCap: .round))
                // Pivot.
                context.fill(Path(ellipseIn: CGRect(x: pivot.x - unit * 0.12, y: pivot.y - unit * 0.12, width: unit * 0.24, height: unit * 0.24)),
                             with: .color(Color(white: 0.55)))
                context.fill(Path(ellipseIn: CGRect(x: pivot.x - unit * 0.05, y: pivot.y - unit * 0.05, width: unit * 0.1, height: unit * 0.1)),
                             with: .color(Color(white: 0.15)))
            }
            .frame(width: diameter * 2.6, height: diameter * 2.6)
            .shadow(color: .black.opacity(0.5), radius: diameter * 0.02, x: diameter * 0.01, y: diameter * 0.02)
            .allowsHitTesting(false)
        }
    }

    struct VinylRecordView: View {
        let layer: VinylLayer
        let diameter: CGFloat
        let angle: Double
        let cover: UIImage?
        var glowBoost = 0.0

        private func color(_ hex: String, _ fallback: Color) -> Color {
            guard let c = HexColor.components(hex) else { return fallback }
            return Color(red: c.r, green: c.g, blue: c.b)
        }

        /// The surface of the disc for the chosen style (grooves are drawn on top).
        @ViewBuilder private func surface(_ labelD: CGFloat) -> some View {
            let tint = color(layer.discColorHex, .purple)
            let accent = color(layer.accentColorHex, .yellow)
            switch layer.style {
            case .classic:
                Circle().fill(RadialGradient(colors: [Color(white: 0.17), Color(white: 0.035)],
                                             center: .center, startRadius: 0, endRadius: diameter / 2))
            case .colored:
                Circle().fill(RadialGradient(colors: [tint, tint.opacity(0.55), Color.black.opacity(0.85)],
                                             center: .center, startRadius: 0, endRadius: diameter / 2))
            case .splatter:
                ZStack {
                    Circle().fill(Color(white: 0.06))
                    Canvas { context, size in
                        let radius = min(size.width, size.height) / 2
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for i in 0..<34 {
                            let angle = EffectMath.unit(i, 11) * 2 * Double.pi
                            let distance = radius * CGFloat(0.2 + 0.78 * EffectMath.unit(i, 12))
                            let blob = radius * CGFloat(0.03 + 0.11 * EffectMath.unit(i, 13))
                            let p = CGPoint(x: center.x + CGFloat(cos(angle)) * distance, y: center.y + CGFloat(sin(angle)) * distance)
                            context.fill(Path(ellipseIn: CGRect(x: p.x - blob, y: p.y - blob * 0.7, width: blob * 2, height: blob * 1.4)),
                                         with: .color((i % 3 == 0 ? accent : tint).opacity(0.88)))
                        }
                    }
                }.clipShape(Circle())
            case .picture:
                ZStack {
                    Circle().fill(Color(white: 0.1))
                    if let cover { Image(uiImage: cover).resizable().scaledToFill().frame(width: diameter, height: diameter) }
                    Circle().fill(Color.black.opacity(0.18))
                }.clipShape(Circle())
            case .neon:
                ZStack {
                    Circle().fill(Color(white: 0.02))
                    Canvas { context, size in
                        let radius = min(size.width, size.height) / 2
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for (k, f) in [0.97, 0.84, 0.7, 0.56].enumerated() {
                            let r = radius * CGFloat(f)
                            context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                           with: .color(tint.opacity(k == 0 ? 1 : 0.7)), lineWidth: max(1.5, radius * (k == 0 ? 0.03 : 0.015)))
                        }
                    }
                    .shadow(color: tint, radius: diameter * 0.025)
                }
            case .gold:
                Circle().fill(AngularGradient(gradient: Gradient(colors: [
                    Color(red: 0.98, green: 0.84, blue: 0.4), Color(red: 0.62, green: 0.45, blue: 0.12),
                    Color(red: 1.0, green: 0.92, blue: 0.62), Color(red: 0.55, green: 0.38, blue: 0.08),
                    Color(red: 0.98, green: 0.84, blue: 0.4)]), center: .center))
            }
        }

        var body: some View {
            let labelD = diameter * CGFloat(min(0.7, max(0.15, layer.labelScale)))
            let grooveOpacity = layer.style == .classic ? 1.0 : (layer.style == .neon ? 0.3 : 0.55)
            ZStack {
                // Glow behind the disc.
                let glowColor = color([VinylStyle.colored, .splatter, .neon].contains(layer.style) ? layer.discColorHex : layer.glowColorHex, .cyan)
                Circle().fill(RadialGradient(colors: [glowColor, glowColor.opacity(0)], center: .center,
                                             startRadius: diameter * 0.4, endRadius: diameter * 0.66))
                    .frame(width: diameter * 1.32, height: diameter * 1.32)
                    .opacity(min(1, max(0, layer.glow + glowBoost)) * 0.9)

                // Soft shadow under the disc. It does not turn, so it is not recomputed while the record spins.
                Circle().fill(Color.black).frame(width: diameter, height: diameter)
                    .shadow(color: .black.opacity(min(1, max(0, layer.shadow)) * 0.75),
                            radius: diameter * 0.05, x: diameter * 0.015, y: diameter * 0.04)

                // The disc itself (this part turns).
                ZStack {
                    surface(labelD)
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let radius = min(size.width, size.height) / 2
                        let inner = radius * CGFloat(min(0.7, max(0.15, layer.labelScale))) * 1.05
                        var r = inner
                        var i = 0
                        while r < radius * 0.985 {
                            let shade = (0.025 + 0.04 * Double((i * 37) % 11) / 10) * grooveOpacity          // deterministic grooves
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
                            context.stroke(gap, with: .color(.black.opacity(0.7 * grooveOpacity)), lineWidth: max(1.5, radius / 90))
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
                        if let cover, layer.style != .picture {
                            Image(uiImage: cover).resizable().scaledToFill().frame(width: labelD, height: labelD).clipShape(Circle())
                        }
                        Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: max(1, labelD * 0.02))
                        Circle().fill(Color.black.opacity(0.85)).frame(width: labelD * 0.09, height: labelD * 0.09)
                        Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1).frame(width: labelD * 0.09, height: labelD * 0.09)
                    }
                    .frame(width: labelD, height: labelD)
                }
                .frame(width: diameter, height: diameter)
                .drawingGroup()                                  // grooves are drawn once; only the turn is repeated
                .rotationEffect(.degrees(angle))

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
                    .opacity(min(1, max(0, layer.reflection)) * 0.4)
                    .allowsHitTesting(false)
            }
        }
    }
}
