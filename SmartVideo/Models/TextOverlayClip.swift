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
    var pathMode: OverlayMotionPath = .straight
    var keyframes: [OverlayKeyframe] = []

    var end: Double { start + duration }

    private enum CodingKeys: String, CodingKey {
        case id, text, start, duration, startX, startY, endX, endY
        case fontSize, colorHex, useBackground, opacity, easing
        case pathMode, keyframes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? "Nhập chữ ở đây"
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 3
        startX = try c.decodeIfPresent(Double.self, forKey: .startX) ?? 0.5
        startY = try c.decodeIfPresent(Double.self, forKey: .startY) ?? 0.5
        endX = try c.decodeIfPresent(Double.self, forKey: .endX) ?? 0.5
        endY = try c.decodeIfPresent(Double.self, forKey: .endY) ?? 0.5
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 48
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "FFFFFF"
        useBackground = try c.decodeIfPresent(Bool.self, forKey: .useBackground) ?? true
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        easing = try c.decodeIfPresent(OverlayEasing.self, forKey: .easing) ?? .easeInOut
        pathMode = try c.decodeIfPresent(OverlayMotionPath.self,
                                         forKey: .pathMode) ?? .straight
        keyframes = try c.decodeIfPresent([OverlayKeyframe].self,
                                          forKey: .keyframes) ?? []
    }
}
