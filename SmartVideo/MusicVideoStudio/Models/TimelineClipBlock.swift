import Foundation

extension MusicVideoStudio {
    /// One block on the timeline UI, derived from a layer. The timeline view
    /// works only with these values, never with the concrete layer types.
    struct TimelineClip: Identifiable, Hashable {
        let id: UUID
        let track: TrackKind
        let title: String
        let range: TimeRange
        let isVisible: Bool
        let isLocked: Bool
    }
}
