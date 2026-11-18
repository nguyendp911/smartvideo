import SwiftUI

extension MusicVideoStudio {
    /// Time ruler. Tap or drag anywhere on it to move the playhead.
    struct TimelineRulerView: View {
        let scale: TimelineScale
        let duration: ProjectTime
        let onSeek: (ProjectTime) -> Void
        static let height: CGFloat = 26

        var body: some View {
            let width = scale.contentWidth(duration: duration)
            Canvas { context, size in
                let visible = 0...max(0.1, Double(size.width) / scale.pixelsPerSecond)
                for tick in scale.ticks(visible: visible) {
                    let x = CGFloat(scale.x(for: tick.time))
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: tick.isMajor ? 12 : 19))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(.white.opacity(tick.isMajor ? 0.55 : 0.25)), lineWidth: 1)
                    if let label = tick.label {
                        context.draw(
                            Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.7)),
                            at: CGPoint(x: x + 3, y: 6), anchor: .leading)
                    }
                }
                // End-of-project marker.
                let end = CGFloat(scale.x(for: duration))
                context.fill(Path(CGRect(x: end, y: 0, width: 2, height: size.height)), with: .color(.cyan.opacity(0.5)))
            }
            .frame(width: width, height: Self.height)
            .background(Color.white.opacity(0.05))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onSeek(scale.time(forX: Double(value.location.x)))
            })
            .accessibilityLabel("Thước thời gian")
        }
    }
}
