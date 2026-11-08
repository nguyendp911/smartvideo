import SwiftUI

/// Timeline markers shared by moving video and title tracks.
struct MultiTrackKeyframeTimelineStrip: View {
    let frames: [OverlayKeyframe]
    let start: Double
    let duration: Double
    let totalDuration: Double
    let onScrub: (Double) -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.caption2)
                .foregroundStyle(.orange)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange.opacity(0.08))
                    ForEach(frames) { frame in
                        let timelineTime = start + duration * frame.progress
                        let fraction = min(1, max(0,
                            timelineTime / max(0.1, totalDuration)))
                        Button {
                            onScrub(timelineTime)
                        } label: {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(
                            x: min(geo.size.width - 11,
                                   max(11, geo.size.width * fraction)),
                            y: geo.size.height / 2
                        )
                    }
                }
            }
        }
        .frame(height: 22)
        .accessibilityLabel(
            "Keyframe: \(frames.count) mốc chuyển động"
        )
    }
}
