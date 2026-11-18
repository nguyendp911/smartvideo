import SwiftUI

extension MusicVideoStudio {
    /// Wraps words onto lines, centred / leading / trailing.
    struct WrapLayout: Layout {
        var spacing: CGFloat
        var lineSpacing: CGFloat
        var alignment: TextAlignmentOption

        private struct Item { let index: Int; let size: CGSize }

        private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [[Item]] {
            var rows: [[Item]] = [[]]
            var x: CGFloat = 0
            for (i, view) in subviews.enumerated() {
                let size = view.sizeThatFits(.unspecified)
                if x > 0, x + size.width > maxWidth { rows.append([]); x = 0 }
                rows[rows.count - 1].append(Item(index: i, size: size))
                x += size.width + spacing
            }
            return rows.filter { row in !row.isEmpty }
        }

        private func width(of row: [Item]) -> CGFloat {
            var total: CGFloat = 0
            for item in row { total += item.size.width }
            return total + spacing * CGFloat(max(0, row.count - 1))
        }

        private func height(of row: [Item]) -> CGFloat {
            var tallest: CGFloat = 0
            for item in row { tallest = max(tallest, item.size.height) }
            return tallest
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            let laid = rows(subviews, maxWidth: maxWidth)
            var widest: CGFloat = 0
            var total: CGFloat = 0
            for row in laid { widest = max(widest, width(of: row)); total += height(of: row) }
            total += lineSpacing * CGFloat(max(0, laid.count - 1))
            return CGSize(width: maxWidth.isFinite ? min(widest, maxWidth) : widest, height: total)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var y = bounds.minY
            for row in rows(subviews, maxWidth: bounds.width) {
                let rowWidth = width(of: row)
                var x: CGFloat
                switch alignment {
                case .leading: x = bounds.minX
                case .center: x = bounds.minX + (bounds.width - rowWidth) / 2
                case .trailing: x = bounds.maxX - rowWidth
                }
                for item in row {
                    subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                    x += item.size.width + spacing
                }
                y += height(of: row) + lineSpacing
            }
        }
    }

    /// Karaoke lyrics at one instant. Every animation is a function of the
    /// (audio-file) time, so seeking and pausing always show the right state.
    struct KaraokeLyricsView: View {
        let layer: LyricsLayer
        let canvas: CGSize
        let sourceTime: Double
        let selected: Bool

        private var weight: Font.Weight {
            switch layer.weight {
            case .regular: return .regular
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }

        private func rgb(_ hex: String, _ fallback: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
            HexColor.components(hex) ?? fallback
        }

        var body: some View {
            let t = layer.core.transform
            let fontPx = max(6, CGFloat(layer.fontSize) * canvas.height)
            let current = KaraokeMath.currentLine(layer.lines, at: sourceTime)
            ZStack {
                VStack(spacing: fontPx * 0.45) {
                    if let current {
                        line(layer.lines[current], active: true, fontPx: fontPx)
                        if layer.showNextLine, current + 1 < layer.lines.count {
                            line(layer.lines[current + 1], active: false, fontPx: fontPx)
                                .opacity(0.55)
                        }
                    }
                }
                .frame(maxWidth: canvas.width * 0.9)
                .padding(4)
                .overlay { if selected { Rectangle().strokeBorder(Color.cyan, lineWidth: 2) } }
                .scaleEffect(t.scale)
                .rotationEffect(.degrees(t.rotation))
                .position(x: canvas.width * CGFloat(t.x), y: canvas.height * CGFloat(t.y))
                .opacity(t.opacity)
            }
            .frame(width: canvas.width, height: canvas.height)
        }

        private func line(_ line: LyricLine, active: Bool, fontPx: CGFloat) -> some View {
            let normal = rgb(layer.normalColorHex, (r: 1, g: 1, b: 1))
            let highlight = rgb(layer.highlightColorHex, (r: 1, g: 0.84, b: 0.31))
            return WrapLayout(spacing: fontPx * 0.28, lineSpacing: fontPx * 0.2, alignment: layer.alignment) {
                ForEach(line.words) { word in
                    KaraokeWordView(
                        text: word.text,
                        style: active ? KaraokeMath.style(layer.animation, word: word, at: sourceTime)
                                      : KaraokeMath.style(layer.animation, word: word, at: -1),
                        animation: layer.animation, normal: normal, highlight: highlight,
                        fontPx: fontPx, weight: weight, shadow: layer.hasShadow)
                }
            }
        }
    }

    struct KaraokeWordView: View {
        let text: String
        let style: KaraokeMath.WordStyle
        let animation: LyricAnimation
        let normal: (r: Double, g: Double, b: Double)
        let highlight: (r: Double, g: Double, b: Double)
        let fontPx: CGFloat
        let weight: Font.Weight
        let shadow: Bool

        private func color(_ c: (r: Double, g: Double, b: Double)) -> Color { Color(red: c.r, green: c.g, blue: c.b) }

        private var mixed: Color {
            let k = min(1, max(0, style.colorMix))
            return Color(red: normal.r + (highlight.r - normal.r) * k,
                         green: normal.g + (highlight.g - normal.g) * k,
                         blue: normal.b + (highlight.b - normal.b) * k)
        }

        var body: some View {
            let font = Font.system(size: fontPx, weight: weight)
            let shown = style.visibleCharacters.map { String(text.prefix($0)) } ?? text
            ZStack(alignment: .leading) {
                Text(text).font(font).opacity(0)                         // reserves the full word width
                if animation == .fill {
                    Text(shown).font(font).foregroundColor(color(normal))
                    Text(shown).font(font).foregroundColor(color(highlight))
                        .mask(alignment: .leading) {
                            GeometryReader { geo in
                                Rectangle().frame(width: geo.size.width * CGFloat(min(1, max(0, style.fill))))
                            }
                        }
                } else {
                    Text(shown).font(font).foregroundColor(mixed)
                }
            }
            .scaleEffect(style.scale)
            .opacity(style.opacity)
            .shadow(color: shadow ? Color.black.opacity(0.6) : .clear, radius: fontPx * 0.08, x: 0, y: 2)
            .shadow(color: color(highlight).opacity(style.glow), radius: fontPx * 0.5 * CGFloat(style.glow))
        }
    }

    /// `ColorPicker` <-> `#RRGGBB` string.
    static func colorBinding(_ hex: Binding<String>, beginEdit: @escaping () -> Void) -> Binding<Color> {
        Binding(
            get: {
                let c = HexColor.components(hex.wrappedValue) ?? (1, 1, 1)
                return Color(red: c.r, green: c.g, blue: c.b)
            },
            set: { color in
                var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
                UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
                beginEdit()
                hex.wrappedValue = HexColor.string(r: Double(r), g: Double(g), b: Double(b))
            })
    }
}
