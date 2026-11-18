import SwiftUI

extension MusicVideoStudio {
    /// Word timing of ONE lyric line: coloured blocks on a time axis with a draggable
    /// handle at the start of every word (and one at the end of the last word).
    /// Times are seconds of the audio file, like the words themselves.
    struct LyricsTimelineView: View {
        let line: LyricLine
        let lineIndex: Int
        /// Seconds of the file currently at the playhead (drawn as a cursor).
        let playheadSource: Double
        let onBeginDrag: () -> Void
        let onMoveStart: (_ word: Int, _ time: Double) -> Void
        let onMoveEnd: (_ word: Int, _ time: Double) -> Void

        private let padding = 0.6

        var body: some View {
            GeometryReader { geo in
                let lower = max(0, line.start - padding)
                let span = max(0.5, line.end + padding - lower)
                let pps = geo.size.width / CGFloat(span)
                let x = { (t: Double) -> CGFloat in CGFloat(t - lower) * pps }
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05))
                    ForEach(Array(line.words.enumerated()), id: \.element.id) { index, word in
                        let width = max(6, CGFloat(word.duration) * pps - 1)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.yellow.opacity(index % 2 == 0 ? 0.55 : 0.35))
                            .overlay(Text(word.text).font(.caption2).foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 2))
                            .frame(width: width, height: 34)
                            .offset(x: x(word.start), y: 22)
                    }
                    ForEach(Array(line.words.enumerated()), id: \.element.id) { index, word in
                        BoundaryHandle(time: word.start, pixelsPerSecond: pps, onBegin: onBeginDrag) { onMoveStart(index, $0) }
                            .offset(x: x(word.start) - 11, y: 14)
                    }
                    if let last = line.words.last {
                        BoundaryHandle(time: last.end, pixelsPerSecond: pps, onBegin: onBeginDrag, tint: .orange) {
                            onMoveEnd(line.words.count - 1, $0)
                        }
                        .offset(x: x(last.end) - 11, y: 14)
                    }
                    if playheadSource >= lower, playheadSource <= lower + span {
                        Rectangle().fill(Color.cyan).frame(width: 2, height: 62).offset(x: x(playheadSource) - 1)
                    }
                    Text(String(format: "%.2fs", line.start)).font(.system(size: 9)).foregroundStyle(.secondary)
                        .offset(x: 4, y: 0)
                }
            }
            .frame(height: 64)
            .accessibilityLabel("Thời gian từng từ của dòng \(lineIndex + 1)")
        }
    }

    /// A draggable boundary. The time under the finger is the start time plus the
    /// drag distance, so it never drifts as the line re-renders.
    struct BoundaryHandle: View {
        let time: Double
        let pixelsPerSecond: CGFloat
        let onBegin: () -> Void
        var tint: Color = .cyan
        let onMove: (Double) -> Void
        @State private var origin: Double?

        var body: some View {
            Capsule()
                .fill(tint)
                .frame(width: 8, height: 46)
                .frame(width: 22, height: 46)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if origin == nil { origin = time; onBegin() }
                            onMove((origin ?? time) + Double(value.translation.width / max(pixelsPerSecond, 1)))
                        }
                        .onEnded { _ in origin = nil }
                )
        }
    }
}
