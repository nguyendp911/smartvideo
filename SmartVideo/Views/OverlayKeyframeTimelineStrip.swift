import SwiftUI

/// Show where keyframes occur in a global timeline; tap a diamond to scrub
/// directly to its exact keyframe. Read-only: edit values in Overlay Studio.
struct OverlayKeyframeTimelineStrip: View {
    let overlay: ImageOverlayClip
    let totalDuration: Double
    let onScrub: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.08))
                let knots = OverlayKeyframeSampler.frames(for: overlay)
                ForEach(knots) { key in
                    let time = overlay.start +
                        key.progress * overlay.duration
                    let fraction = min(1, max(0,
                        time / max(0.1, totalDuration)))
                    Button {
                        onScrub(time)
                    } label: {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: min(geo.size.width - 12,
                               max(12, geo.size.width * fraction)),
                        y: geo.size.height / 2
                    )
                }
            }
        }
        .frame(height: 22)
    }
}
