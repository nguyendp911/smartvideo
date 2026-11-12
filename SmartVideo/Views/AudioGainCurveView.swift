import SwiftUI

/// The SFX volume-automation curve in local track time.
/// Tap an orange control point to select and edit its gain.
struct AudioGainCurveView: View {
    let frames: [AudioGainKeyframe]
    let selectedID: UUID?
    let playheadProgress: Double
    let onSelect: (UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let w = max(1, size.width)
                let h = max(1, size.height)
                context.fill(Path(roundedRect:
                    CGRect(origin: .zero, size: size), cornerRadius: 7),
                    with: .color(Color.white.opacity(0.055)))
                var line = Path()
                for i in 0...96 {
                    let p = Double(i) / 96
                    let gain = AudioAutomationMath.factor(at: p, frames: frames)
                    let point = CGPoint(
                        x: w * CGFloat(p),
                        y: 6 + (h - 12) * CGFloat(1 - gain)
                    )
                    if i == 0 { line.move(to: point) }
                    else { line.addLine(to: point) }
                }
                context.stroke(line, with: .color(.cyan), lineWidth: 2.5)

                let x = w * CGFloat(AudioAutomationMath.clampProgress(
                    playheadProgress
                ))
                var cursor = Path()
                cursor.move(to: CGPoint(x: x, y: 0))
                cursor.addLine(to: CGPoint(x: x, y: h))
                context.stroke(cursor,
                               with: .color(.white.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                for frame in frames {
                    let point = CGPoint(
                        x: w * CGFloat(frame.progress),
                        y: 6 + (h - 12) * CGFloat(1 - frame.gain)
                    )
                    let selected = frame.id == selectedID
                    let size: CGFloat = selected ? 12 : 9
                    let rect = CGRect(x: point.x - size / 2,
                                      y: point.y - size / 2,
                                      width: size, height: size)
                    context.fill(Path(ellipseIn: rect),
                                 with: .color(selected ? .yellow : .orange))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard !frames.isEmpty else { return }
                let p = Double(location.x / max(1, geo.size.width))
                if let nearest = frames.min(by: {
                    abs($0.progress - p) < abs($1.progress - p)
                }), abs(nearest.progress - p) < 0.09 {
                    onSelect(nearest.id)
                }
            }
        }
        .frame(height: 72)
        .accessibilityLabel("Đường keyframe âm lượng. Chạm chấm màu cam để chọn.")
    }
}
