import SwiftUI

extension MusicVideoStudio {
    /// Draws the nine styles. Everything is a function of its inputs (levels, bass, beat pulse
    /// and the clock), so the same frame always looks the same, in preview and in export.
    enum VisualizerPainter {
        private static func color(_ hex: String) -> Color {
            let c = HexColor.components(hex) ?? (r: 1, g: 1, b: 1)
            return Color(red: c.r, green: c.g, blue: c.b)
        }

        /// Deterministic 0...1 value for (index, salt): drives the particles.
        static func unit(_ index: Int, _ salt: Int) -> Double {
            var x = UInt64(truncatingIfNeeded: index) &* 0x9E3779B97F4A7C15 &+ UInt64(truncatingIfNeeded: salt) &* 0xBF58476D1CE4E5B9
            x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
            x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
            x ^= x >> 31
            return Double(x % 100_000) / 100_000
        }

        static func paint(layer: VisualizerLayer, frame: VisualizerFrame, time: Double,
                          context: inout GraphicsContext, size: CGSize) {
            let first = color(layer.colorHex), second = color(layer.secondColorHex)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [first, second]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
            let values: [CGFloat] = frame.bands.map { CGFloat(min(1, max(0, Double($0) * layer.sensitivity))) }
            guard !values.isEmpty, size.width > 1, size.height > 1 else { return }
            switch layer.style {
            case .bars: bars(layer, values, shading, &context, size, mirrored: false)
            case .mirror: bars(layer, values, shading, &context, size, mirrored: true)
            case .wave: wave(layer, values, shading, &context, size)
            case .area: area(layer, values, shading, &context, size)
            case .dots: dots(layer, values, shading, &context, size)
            case .circle: circle(layer, values, shading, &context, size, time: time)
            case .ring: ring(layer, values, first, shading, &context, size)
            case .pulse: pulse(layer, frame, first, second, &context, size)
            case .particles: particles(layer, values, frame, first, second, &context, size, time: time)
            }
        }

        private static func bars(_ layer: VisualizerLayer, _ values: [CGFloat], _ shading: GraphicsContext.Shading,
                                 _ context: inout GraphicsContext, _ size: CGSize, mirrored: Bool) {
            let slot = size.width / CGFloat(values.count)
            let barWidth = max(1, slot * CGFloat(layer.thickness))
            for (i, v) in values.enumerated() {
                let h = max(2, v * size.height)
                let y = mirrored ? (size.height - h) / 2 : size.height - h
                let rect = CGRect(x: CGFloat(i) * slot + (slot - barWidth) / 2, y: y, width: barWidth, height: h)
                context.fill(layer.rounded ? Path(roundedRect: rect, cornerRadius: barWidth / 2) : Path(rect), with: shading)
            }
        }

        private static func wavePoints(_ values: [CGFloat], _ size: CGSize) -> [CGPoint] {
            let slot = size.width / CGFloat(values.count)
            let mid = size.height / 2
            return values.enumerated().map { i, v in
                CGPoint(x: slot * (CGFloat(i) + 0.5), y: mid + (i % 2 == 0 ? -1 : 1) * v * size.height / 2)
            }
        }

        private static func smoothPath(_ points: [CGPoint], start: CGPoint, end: CGPoint) -> Path {
            var path = Path()
            path.move(to: start)
            var previous = start
            for point in points {
                let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
                previous = point
            }
            path.addQuadCurve(to: end, control: previous)
            return path
        }

        private static func wave(_ layer: VisualizerLayer, _ values: [CGFloat], _ shading: GraphicsContext.Shading,
                                 _ context: inout GraphicsContext, _ size: CGSize) {
            let mid = size.height / 2
            let path = smoothPath(wavePoints(values, size), start: CGPoint(x: 0, y: mid), end: CGPoint(x: size.width, y: mid))
            let width = max(2, size.height * 0.05 * CGFloat(layer.thickness + 0.4))
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }

        private static func area(_ layer: VisualizerLayer, _ values: [CGFloat], _ shading: GraphicsContext.Shading,
                                 _ context: inout GraphicsContext, _ size: CGSize) {
            let slot = size.width / CGFloat(values.count)
            let points = values.enumerated().map { i, v in
                CGPoint(x: slot * (CGFloat(i) + 0.5), y: size.height - max(2, v * size.height))
            }
            var path = smoothPath(points, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            var faded = context
            faded.opacity = 0.85
            faded.fill(path, with: shading)
            context.stroke(smoothPath(points, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: size.height)),
                           with: shading, lineWidth: 2)
        }

        private static func dots(_ layer: VisualizerLayer, _ values: [CGFloat], _ shading: GraphicsContext.Shading,
                                 _ context: inout GraphicsContext, _ size: CGSize) {
            let rows = 12
            let slot = size.width / CGFloat(values.count)
            let cell = size.height / CGFloat(rows)
            let diameter = max(2, min(slot * CGFloat(layer.thickness), cell * 0.85))
            for (i, v) in values.enumerated() {
                let lit = max(1, Int((v * CGFloat(rows)).rounded()))
                for r in 0..<lit {
                    let center = CGPoint(x: slot * (CGFloat(i) + 0.5), y: size.height - (CGFloat(r) + 0.5) * cell)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                        width: diameter, height: diameter)), with: shading)
                }
            }
        }

        private static func circle(_ layer: VisualizerLayer, _ values: [CGFloat], _ shading: GraphicsContext.Shading,
                                   _ context: inout GraphicsContext, _ size: CGSize, time: Double) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let shortSide = min(size.width, size.height)
            let inner = shortSide * 0.22, longest = shortSide * 0.28
            let width = max(1.5, 2 * .pi * inner / CGFloat(values.count) * CGFloat(layer.thickness))
            let spin = time * 0.2
            for (i, v) in values.enumerated() {
                let angle = spin + 2 * Double.pi * Double(i) / Double(values.count)
                let length = max(2, v * longest)
                var path = Path()
                path.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner))
                path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * (inner + length), y: center.y + CGFloat(sin(angle)) * (inner + length)))
                context.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: layer.rounded ? .round : .butt))
            }
        }

        private static func ring(_ layer: VisualizerLayer, _ values: [CGFloat], _ first: Color, _ shading: GraphicsContext.Shading,
                                 _ context: inout GraphicsContext, _ size: CGSize) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let shortSide = min(size.width, size.height)
            let base = shortSide * 0.28, amplitude = shortSide * 0.2
            let n = values.count
            var points: [CGPoint] = []
            for i in 0..<n {
                let smoothed = (values[(i + n - 1) % n] + values[i] * 2 + values[(i + 1) % n]) / 4      // closed loop
                let angle = 2 * Double.pi * Double(i) / Double(n) - Double.pi / 2
                let radius = base + smoothed * amplitude
                points.append(CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius))
            }
            var path = Path()
            path.addLines(points)
            path.closeSubpath()
            context.fill(path, with: .color(first.opacity(0.18)))
            context.stroke(path, with: shading, style: StrokeStyle(lineWidth: max(2, shortSide * 0.02 * CGFloat(layer.thickness + 0.4)), lineJoin: .round))
        }

        private static func pulse(_ layer: VisualizerLayer, _ frame: VisualizerFrame, _ first: Color, _ second: Color,
                                  _ context: inout GraphicsContext, _ size: CGSize) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) * 0.22
            let boost = 1 + 0.35 * CGFloat(min(1, frame.bass * layer.sensitivity)) + 0.4 * CGFloat(frame.pulse)
            for ring in 0..<4 {
                let radius = base * (0.5 + 0.5 * CGFloat(ring)) * boost
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                var layerContext = context
                layerContext.opacity = 1 - Double(ring) * 0.22
                if ring == 0 { layerContext.fill(Path(ellipseIn: rect), with: .color(first.opacity(0.6))) }
                layerContext.stroke(Path(ellipseIn: rect), with: .color(ring % 2 == 0 ? first : second),
                                    lineWidth: max(1.5, CGFloat(4 - ring) * CGFloat(layer.thickness + 0.4)))
            }
        }

        private static func particles(_ layer: VisualizerLayer, _ values: [CGFloat], _ frame: VisualizerFrame, _ first: Color, _ second: Color,
                                      _ context: inout GraphicsContext, _ size: CGSize, time: Double) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = min(size.width, size.height) * 0.5
            let energy = CGFloat(min(1, frame.bass * layer.sensitivity))
            for i in 0..<72 {
                let speed = 0.08 + 0.22 * unit(i, 1)
                let life = (abs(time) * speed + unit(i, 2)).truncatingRemainder(dividingBy: 1)
                let angle = unit(i, 3) * 2 * Double.pi
                let radius = CGFloat(life) * reach * (1 + 0.4 * energy)
                let level = values[i % values.count]
                let diameter = CGFloat(2 + 7 * unit(i, 4)) * (0.5 + level)
                var particle = context
                particle.opacity = (1 - life) * (0.45 + 0.55 * Double(level))
                let p = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
                particle.fill(Path(ellipseIn: CGRect(x: p.x - diameter / 2, y: p.y - diameter / 2, width: diameter, height: diameter)),
                              with: .color(i % 2 == 0 ? first : second))
            }
        }
    }

    struct VisualizerCanvas: View {
        let layer: VisualizerLayer
        let frame: VisualizerFrame
        let time: Double

        var body: some View {
            Canvas { context, size in
                VisualizerPainter.paint(layer: layer, frame: frame, time: time, context: &context, size: size)
            }
        }
    }

    /// One visualizer placed on the canvas (position / scale / rotation / opacity from its core).
    struct VisualizerLayerView: View {
        let layer: VisualizerLayer
        let canvas: CGSize
        let frame: VisualizerFrame
        let time: Double
        let selected: Bool

        var body: some View {
            let t = layer.core.transform
            let glow = CGFloat(layer.glow)
            let tint = HexColor.components(layer.colorHex) ?? (r: 0.3, g: 0.8, b: 0.9)
            ZStack {
                VisualizerCanvas(layer: layer, frame: frame, time: time)
                    .frame(width: canvas.width * CGFloat(layer.width), height: canvas.height * CGFloat(layer.height))
                    .shadow(color: Color(red: tint.r, green: tint.g, blue: tint.b).opacity(Double(glow) * 0.9), radius: glow * 14)
                    .overlay { if selected { Rectangle().strokeBorder(Color.cyan, lineWidth: 2) } }
                    .scaleEffect(CGFloat(t.scale) * (1 + CGFloat(layer.beatPulse * 0.12 * frame.pulse)))
                    .rotationEffect(.degrees(t.rotation))
                    .position(x: canvas.width * CGFloat(t.x), y: canvas.height * CGFloat(t.y))
                    .opacity(t.opacity)
            }
            .frame(width: canvas.width, height: canvas.height)
        }
    }

    /// "Cut photos on the beat" control for the audio inspector.
    struct BeatCutControl: View {
        @ObservedObject var model: MusicVideoEditorModel
        @State private var every = 4
        @State private var working = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Stepper("Đổi ảnh mỗi \(every) nhịp", value: $every, in: 1...16).font(.caption)
                Button {
                    working = true
                    Task { await model.cutPhotosOnBeats(every: every); working = false }
                } label: {
                    Label(working ? "Đang phân tích nhịp…" : "Cắt ảnh theo nhịp nhạc", systemImage: "metronome").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).font(.caption)
                .disabled(working || model.project.photos.isEmpty)
            }
        }
    }
}
