import Foundation
import CoreGraphics

/// Independent image overlay track: normalized coordinates are in the
/// video canvas, with (0,0) at top-left. Non-destructive project metadata.
struct ImageOverlayClip: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fileURL: URL
    var start: Double = 0
    var duration: Double = 3

    var startX: Double = 0.5
    var startY: Double = 0.5
    var endX: Double = 0.5
    var endY: Double = 0.5

    /// Normalized width relative to canvas width, 0.1 through 1.
    var scale: Double = 0.45
    var opacity: Double = 1
    var rotationDegrees: Double = 0

    var end: Double { start + duration }
    var filename: String { fileURL.lastPathComponent }
}
