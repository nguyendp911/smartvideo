import Foundation

/// A title/text layer independent of the subtitle track.
struct TextOverlayClip: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String = "Nhập chữ ở đây"
    var start: Double = 0
    var duration: Double = 3
    var startX: Double = 0.5
    var startY: Double = 0.5
    var endX: Double = 0.5
    var endY: Double = 0.5
    var fontSize: Double = 48
    var colorHex: String = "FFFFFF"
    var useBackground: Bool = true
    var opacity: Double = 1
    var easing: OverlayEasing = .easeInOut

    var end: Double { start + duration }
}
