import SwiftUI

/// Zoomable, source-time waveform editor shared by music and SFX.
/// The highlighted region is the actual non-destructive trim; dragging the
/// two cyan handles updates sourceStart / output duration in the project.
/// All waveform requests decode only the visible source-time window.
struct AudioWaveformTrimView: View {
    let url: URL
    let sourceDuration: Double
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    let title: String
    var playheadSource: Double? = nil

    @State private var viewportStart: Double = 0
    @State private var viewportSpan: Double = 30
    @State private var bars: [Double] = []
    @State private var isLoading = false
    @State private var draggingStart: Bool?

    private var total: Double { max(0.1, sourceDuration) }
    private var span: Double { min(total, max(0.5, viewportSpan)) }
    private var maxStart: Double { max(0, total - span) }
    private var viewStart: Double { min(maxStart, max(0, viewportStart)) }
    private var viewEnd: Double { viewStart + span }
    private var requestKey: String {
        "\(url.path)|\(Int(viewStart * 4))|\(Int(span * 4))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(title, systemImage: "waveform.path.ecg")
                    .font(.caption.bold())
                Spacer()
                if isLoading { ProgressView().controlSize(.mini) }
                Text(String(format: "%.2f – %.2fs", trimStart, trimEnd))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            GeometryReader { geo in
                Canvas { context, size in
                    let w = max(1, size.width), h = max(1, size.height)
                    context.fill(
                        Path(roundedRect: CGRect(x: 0, y: 0, width: w,
                                                height: h), cornerRadius: 8),
                        with: .color(Color.white.opacity(0.045))
                    )
                    let x1 = CGFloat((trimStart - viewStart) / span) * w
                    let x2 = CGFloat((trimEnd - viewStart) / span) * w
                    let from = min(w, max(0, x1)), to = min(w, max(0, x2))
                    if to > from {
                        context.fill(Path(CGRect(x: from, y: 0,
                                                 width: to - from, height: h)),
                                     with: .color(Color.cyan.opacity(0.12)))
                    }
                    let heights = bars.isEmpty ?
                        Array(repeating: 0.12, count: 96) : bars
                    let cell = w / CGFloat(heights.count)
                    for (i, peak) in heights.enumerated() {
                        let amplitude = max(3, CGFloat(peak) * (h - 10))
                        let x = CGFloat(i) * cell + cell * 0.15
                        let rect = CGRect(x: x, y: (h - amplitude) * 0.5,
                                          width: max(1, cell * 0.68),
                                          height: amplitude)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                     with: .color(Color.cyan.opacity(0.75)))
                    }
                    func vertical(_ x: CGFloat, _ color: Color,
                                  _ lineWidth: CGFloat) {
                        guard x >= 0, x <= w else { return }
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                        context.stroke(p, with: .color(color),
                                       lineWidth: lineWidth)
                    }
                    vertical(x1, .mint, 3)
                    vertical(x2, .orange, 3)
                    if let playheadSource {
                        let x = CGFloat((playheadSource - viewStart) / span) * w
                        vertical(x, .white.opacity(0.9), 1)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(1, geo.size.width)
                        let x = min(width, max(0, value.location.x))
                        let source = min(total, max(0,
                            viewStart + Double(x / width) * span))
                        if draggingStart == nil {
                            let a = CGFloat((trimStart - viewStart) /
                                             span) * width
                            let b = CGFloat((trimEnd - viewStart) /
                                             span) * width
                            // Ignore an offscreen handle when picking a side.
                            let da = a >= 0 && a <= width ?
                                abs(x - a) : CGFloat.greatestFiniteMagnitude
                            let db = b >= 0 && b <= width ?
                                abs(x - b) : CGFloat.greatestFiniteMagnitude
                            draggingStart = da <= db
                        }
                        if draggingStart == true {
                            trimStart = min(max(0, source),
                                            max(0, trimEnd - 0.1))
                        } else {
                            trimEnd = max(min(total, source),
                                          min(total, trimStart + 0.1))
                        }
                    }
                    .onEnded { _ in draggingStart = nil })
                .accessibilityLabel(
                    "Sóng âm. Kéo vạch xanh để chỉnh đầu, vạch cam để chỉnh cuối.")
            }
            .frame(height: 90)

            HStack {
                Text(String(format: "%.1fs", viewStart))
                Spacer()
                Text(String(format: "%.1fs", viewEnd))
            }
            .font(.system(size: 10, weight: .medium,
                          design: .monospaced))
            .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Button {
                    viewportStart = max(0, viewStart - span * 0.75)
                } label: { Image(systemName: "chevron.left") }
                .disabled(viewStart <= 0.01)

                Button {
                    let center = viewStart + span / 2
                    viewportSpan = max(2, span / 2)
                    viewportStart = min(max(0, center - viewportSpan / 2),
                                        max(0, total - viewportSpan))
                } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(span <= 2.01)

                Button {
                    let center = viewStart + span / 2
                    viewportSpan = min(total, min(90, span * 2))
                    viewportStart = min(max(0, center - viewportSpan / 2),
                                        max(0, total - viewportSpan))
                } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(span >= min(total, 90) - 0.01)

                Button("Tới đoạn cắt") {
                    viewportStart = min(max(0, trimStart - span * 0.18),
                                        maxStart)
                }
                Spacer(minLength: 0)
                Button {
                    viewportStart = min(maxStart,
                                        viewStart + span * 0.75)
                } label: { Image(systemName: "chevron.right") }
                .disabled(viewStart >= maxStart - 0.01)
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            Text("Kéo vạch xanh (đầu) hoặc cam (cuối). Dùng +/− để phóng to sóng âm; mọi thay đổi không sửa tệp gốc.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .task(id: requestKey) {
            isLoading = true
            bars = []
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                let samples = try await AudioWaveformSampler.sample(
                    url: url, count: 112, from: viewStart, window: span
                )
                try Task.checkCancellation()
                bars = samples
            } catch {
                // Ignore cancellation from viewport scrubbing/zoom changes.
            }
            isLoading = false
        }
    }
}
