import Foundation

struct MusicHighlight: Identifiable, Equatable {
    let id = UUID()
    let start: Double
    let duration: Double
    let score: Double
}

struct VideoHighlight: Identifiable, Equatable {
    let id = UUID()
    /// Seconds measured from the beginning of the selected timeline clip.
    let start: Double
    let duration: Double
    let score: Double
    let reason: String
}
