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
            case .peakBars: VisualizerExtraStyles.peakBars(layer, values, frame, shading, second, &context, size)
            case .sineWaves: VisualizerExtraStyles.sineWaves(layer, values, shading, &context, size, time: time)
            case .flower: VisualizerExtraStyles.flower(layer, values, first, second, &context, size, time: time)
            case .bubbles: VisualizerExtraStyles.bubbles(layer, values, first, second, &context, size, time: time)
            case .starfield: VisualizerExtraStyles.starfield(layer, values, frame, first, second, &context, size, time: time)
            case .ledMatrix: VisualizerExtraStyles.ledMatrix(layer, values, &context, size)
            }
        }

        static func bars(_ layer: VisualizerLayer, _ values: [CGFloat], _ shading: GraphicsContext.Shading,
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

    /// The six newer styles (kept apart from the first nine).
    enum VisualizerExtraStyles {
        static func color(_ hex: String) -> Color {
            let c = HexColor.components(hex) ?? (r: 1, g: 1, b: 1)
            return Color(red: c.r, green: c.g, blue: c.b)
        }

        private static func average(_ values: [CGFloat], _ from: Int, _ to: Int) -> CGFloat {
            let lo = max(0, min(values.count - 1, from)), hi = max(lo + 1, min(values.count, to))
            return values[lo..<hi].reduce(0, +) / CGFloat(hi - lo)
        }

        static func peakBars(_ layer: VisualizerLayer, _ values: [CGFloat], _ frame: VisualizerFrame, _ shading: GraphicsContext.Shading,
                             _ cap: Color, _ context: inout GraphicsContext, _ size: CGSize) {
            VisualizerPainter.bars(layer, values, shading, &context, size, mirrored: false)
            let peaks = frame.peaks.isEmpty ? values : frame.peaks.map { CGFloat(min(1, max(0, Double($0) * layer.sensitivity))) }
            let slot = size.width / CGFloat(values.count)
            let barWidth = max(1, slot * CGFloat(layer.thickness))
            let capHeight = max(2, size.height * 0.022)
            for (i, p) in peaks.enumerated() where i < values.count {
                let y = max(0, size.height - max(2, p * size.height) - capHeight * 1.6)
                let rect = CGRect(x: CGFloat(i) * slot + (slot - barWidth) / 2, y: y, width: barWidth, height: capHeight)
                context.fill(layer.rounded ? Path(roundedRect: rect, cornerRadius: capHeight / 2) : Path(rect), with: .color(cap))
            }
        }

        static func sineWaves(_ layer: VisualizerLayer, _ values: [CGFloat], _ shading: GraphicsContext.Shading,
                              _ context: inout GraphicsContext, _ size: CGSize, time: Double) {
            let n = values.count
            let levels = [average(values, 0, n / 3), average(values, n / 3, 2 * n / 3), average(values, 2 * n / 3, n)]
            let mid = size.height / 2
            for k in 0..<3 {
                let amplitude = (0.08 + levels[k] * 0.92) * size.height * 0.45 * (1 - 0.18 * CGFloat(k))
                let cycles = 1.4 + 0.9 * Double(k)
                let phase = abs(time) * (1.3 + 0.5 * Double(k))
                var path = Path()
                let steps = 90
                for s in 0...steps {
                    let u = Double(s) / Double(steps)
                    let envelope = sin(Double.pi * u)
                    let y = mid + CGFloat(sin(2 * Double.pi * cycles * u + phase) * envelope) * amplitude
                    let p = CGPoint(x: CGFloat(u) * size.width, y: y)
                    if s == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                var wave = context
                wave.opacity = [1, 0.7, 0.45][k]
                wave.stroke(path, with: shading, style: StrokeStyle(lineWidth: max(2, size.height * 0.045 * CGFloat(layer.thickness + 0.4)) * (1 - 0.2 * CGFloat(k)),
                                                                   lineCap: .round, lineJoin: .round))
            }
        }

        static func flower(_ layer: VisualizerLayer, _ values: [CGFloat], _ first: Color, _ second: Color,
                           _ context: inout GraphicsContext, _ size: CGSize, time: Double) {
            let petals = 12
            let n = values.count
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let shortSide = min(size.width, size.height)
            let inner = shortSide * 0.08
            for p in 0..<petals {
                let level = average(values, p * n / petals, (p + 1) * n / petals)
                let length = shortSide * (0.14 + 0.3 * level)
                let width = max(3, shortSide * 0.12 * CGFloat(layer.thickness + 0.3))
                var petal = context
                petal.translateBy(x: center.x, y: center.y)
                petal.rotate(by: .radians(abs(time) * 0.15 + Double(p) * 2 * Double.pi / Double(petals)))
                petal.opacity = 0.62
                petal.fill(Path(ellipseIn: CGRect(x: inner, y: -width / 2, width: length, height: width)),
                           with: .color(p % 2 == 0 ? first : second))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)), with: .color(first))
        }

        static func bubbles(_ layer: VisualizerLayer, _ values: [CGFloat], _ first: Color, _ second: Color,
                            _ context: inout GraphicsContext, _ size: CGSize, time: Double) {
            for i in 0..<40 {
                let speed = 0.05 + 0.12 * EffectMath.unit(i, 21)
                let life = (abs(time) * speed + EffectMath.unit(i, 22)).truncatingRemainder(dividingBy: 1)
                let level = values[i % values.count]
                let radius = CGFloat(3 + 12 * EffectMath.unit(i, 23)) * (0.5 + level) * max(0.5, size.height / 200)
                let sway = CGFloat(sin(abs(time) * speed * 8 + Double(i))) * size.width * 0.015
                let center = CGPoint(x: CGFloat(EffectMath.unit(i, 24)) * size.width + sway, y: size.height * CGFloat(1 - life) + radius)
                var bubble = context
                bubble.opacity = min(1, (1 - life) * 1.6) * (0.5 + 0.5 * Double(level))
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                let tint = i % 2 == 0 ? first : second
                bubble.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.2)))
                bubble.stroke(Path(ellipseIn: rect), with: .color(tint), lineWidth: 1.4)
            }
        }

        static func starfield(_ layer: VisualizerLayer, _ values: [CGFloat], _ frame: VisualizerFrame, _ first: Color, _ second: Color,
                              _ context: inout GraphicsContext, _ size: CGSize, time: Double) {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = hypot(size.width, size.height) / 2
            let energy = CGFloat(min(1, frame.bass * layer.sensitivity))
            for i in 0..<110 {
                let life = (abs(time) * (0.15 + 0.25 * EffectMath.unit(i, 31)) + EffectMath.unit(i, 32)).truncatingRemainder(dividingBy: 1)
                let depth = CGFloat(life * life)
                let angle = EffectMath.unit(i, 33) * 2 * Double.pi
                let radius = depth * reach
                let tail = radius * (0.1 + 0.25 * energy + 0.3 * CGFloat(frame.pulse))
                var streak = Path()
                streak.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * max(0, radius - tail), y: center.y + CGFloat(sin(angle)) * max(0, radius - tail)))
                streak.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius))
                var star = context
                star.opacity = min(1, Double(depth) * 1.8)
                star.stroke(streak, with: .color(i % 2 == 0 ? first : second),
                            style: StrokeStyle(lineWidth: 0.7 + 2.4 * depth * (0.6 + values[i % values.count]), lineCap: .round))
            }
        }

        static func ledMatrix(_ layer: VisualizerLayer, _ values: [CGFloat], _ context: inout GraphicsContext, _ size: CGSize) {
            let columns = max(1, min(32, values.count)), rows = 10
            let a = HexColor.components(layer.colorHex) ?? (r: 0.3, g: 0.8, b: 0.9)
            let b = HexColor.components(layer.secondColorHex) ?? (r: 0.9, g: 0.25, b: 0.98)
            let cellW = size.width / CGFloat(columns), cellH = size.height / CGFloat(rows)
            let side = min(cellW, cellH) * CGFloat(0.55 + 0.35 * layer.thickness)
            for c in 0..<columns {
                let level = values[min(values.count - 1, c * values.count / columns)]
                let lit = Int((level * CGFloat(rows)).rounded())
                for r in 0..<rows {
                    let t = Double(r) / Double(max(1, rows - 1))
                    let tint = Color(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t)
                    let rect = CGRect(x: (CGFloat(c) + 0.5) * cellW - side / 2, y: size.height - (CGFloat(r) + 0.5) * cellH - side / 2, width: side, height: side)
                    context.fill(layer.rounded ? Path(roundedRect: rect, cornerRadius: side * 0.25) : Path(rect),
                                 with: .color(tint.opacity(r < lit ? 1 : 0.1)))
                }
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
