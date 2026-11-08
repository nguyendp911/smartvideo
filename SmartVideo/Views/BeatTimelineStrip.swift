import SwiftUI

/// Compact, read-only rhythm guide aligned to the global video timeline.
/// Real audio analysis is performed separately in MusicBeatAnalyzer.
struct BeatTimelineStrip: View {
    let beatPositions: [Double]
    let totalDuration: Double

    private var visible: [Double] {
        Array(beatPositions.prefix(180))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.06))
                ForEach(visible.indices, id: \.self) { index in
                    let fraction = min(1, max(0, visible[index] /
                                             max(0.1, totalDuration)))
                    Rectangle()
                        .fill(index.isMultiple(of: 4) ?
                              Color.cyan.opacity(0.90) :
                              Color.cyan.opacity(0.38))
                        .frame(width: index.isMultiple(of: 4) ? 2 : 1,
                               height: index.isMultiple(of: 4) ? 22 : 12)
                        .offset(x: max(0, (geometry.size.width - 2) * fraction))
                }
            }
        }
        .accessibilityLabel(
            "Lưới nhịp: \(beatPositions.count) mốc trong video"
        )
    }
}
