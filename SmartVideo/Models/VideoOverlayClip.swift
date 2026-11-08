import Foundation

/// Independent muted video picture-in-picture track. Video overlays render
/// through AVFoundation video composition, not as a static image animation.
struct VideoOverlayClip: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fileURL: URL
    var start: Double = 0
    var duration: Double = 3
    var sourceStart: Double = 0
    var sourceDuration: Double = 3
    var startX: Double = 0.5
    var startY: Double = 0.5
    var endX: Double = 0.5
    var endY: Double = 0.5
    var width: Double = 0.45
    var opacity: Double = 1
    var end: Double { start + duration }
    var filename: String { fileURL.lastPathComponent }
}

/// Smooth easing for animated graphical layers. Video overlays currently
/// use AVFoundation's linear transform interpolation.
enum OverlayEasing: String, Codable, CaseIterable, Identifiable {
    case linear = "Tuyến tính"
    case easeIn = "Tăng tốc"
    case easeOut = "Giảm tốc"
    case easeInOut = "Mượt hai đầu"

    var id: String { rawValue }
}
