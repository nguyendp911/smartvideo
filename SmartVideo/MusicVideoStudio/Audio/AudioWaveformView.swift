import SwiftUI

extension MusicVideoStudio {
    /// The real waveform of the file, drawn for exactly the part of the file this
    /// clip plays (trim point, looping and length all respected).
    struct AudioWaveformView: View {
        let layer: AudioLayer
        let url: URL
        @State private var waveform: Waveform?

        var body: some View {
            GeometryReader { geo in
                Canvas { context, size in
                    guard let waveform else { return }
                    let columns = max(1, Int(size.width / 2))
                    let peaks = WaveformMath.clipColumns(
                        waveform, sourceStart: layer.sourceStart, sourceDuration: layer.sourceDuration,
                        clipDuration: layer.core.duration.seconds, loops: layer.loops, count: columns)
                    let width = size.width / CGFloat(columns)
                    let mid = size.height / 2
                    for (i, peak) in peaks.enumerated() {
                        let h = max(1, CGFloat(peak) * size.height * 0.92)
                        let rect = CGRect(x: CGFloat(i) * width, y: mid - h / 2, width: max(1, width - 0.5), height: h)
                        context.fill(Path(rect), with: .color(.white.opacity(0.85)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .task(id: url) {
                waveform = WaveformCache.shared.cached(for: url)
                if waveform == nil { waveform = await WaveformCache.shared.waveform(for: url) }
            }
            .accessibilityHidden(true)
        }
    }

    /// Whole-file waveform with two handles: drag to choose which part of the song plays.
    struct AudioTrimmerView: View {
        @ObservedObject var model: MusicVideoEditorModel
        let layer: AudioLayer
        @State private var waveform: Waveform?
        @State private var dragging = false

        private var url: URL { model.manager.mediaURL(projectID: model.project.id, file: layer.mediaFile) }
        private var sourceEnd: Double { layer.sourceStart + (layer.loops ? layer.availableSource : min(layer.availableSource, layer.core.duration.seconds)) }

        var body: some View {
            GeometryReader { geo in
                let total = max(0.1, layer.sourceDuration)
                let width = geo.size.width
                func x(_ seconds: Double) -> CGFloat { CGFloat(seconds / total) * width }
                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.05)))
                        let columns = max(1, Int(size.width / 2))
                        if let waveform {
                            let peaks = WaveformMath.clipColumns(waveform, sourceStart: 0, sourceDuration: total,
                                                                 clipDuration: total, loops: false, count: columns)
                            let w = size.width / CGFloat(columns)
                            for (i, peak) in peaks.enumerated() {
                                let h = max(1, CGFloat(peak) * size.height * 0.9)
                                context.fill(Path(CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 0.5), height: h)),
                                             with: .color(.white.opacity(0.7)))
                            }
                        }
                        // Dim what is trimmed away.
                        let a = x(layer.sourceStart), b = x(min(total, sourceEnd))
                        context.fill(Path(CGRect(x: 0, y: 0, width: a, height: size.height)), with: .color(.black.opacity(0.55)))
                        context.fill(Path(CGRect(x: b, y: 0, width: size.width - b, height: size.height)), with: .color(.black.opacity(0.55)))
                    }
                    handle(at: x(layer.sourceStart)) { value in
                        let seconds = Double(value / width) * total
                        model.setAudioTrim(layer.core.id, sourceStart: seconds, sourceEnd: sourceEnd)
                    }
                    handle(at: x(min(total, sourceEnd))) { value in
                        let seconds = Double(value / width) * total
                        model.setAudioTrim(layer.core.id, sourceStart: layer.sourceStart, sourceEnd: seconds)
                    }
                }
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .coordinateSpace(name: "mv-trimmer")
            .task(id: url) {
                waveform = WaveformCache.shared.cached(for: url)
                if waveform == nil { waveform = await WaveformCache.shared.waveform(for: url) }
            }
        }

        private func handle(at x: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
            Capsule().fill(Color.green).frame(width: 6, height: 56)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .offset(x: x - 11)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("mv-trimmer"))
                    .onChanged { value in
                        if !dragging { model.beginEdit(); dragging = true }
                        onDrag(value.location.x)
                    }
                    .onEnded { _ in dragging = false })
        }
    }
}
