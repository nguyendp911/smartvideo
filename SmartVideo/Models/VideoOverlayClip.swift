import Foundation

/// Independent muted video picture-in-picture track.
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
    var easing: OverlayEasing = .linear
    var pathMode: OverlayMotionPath = .straight
    var keyframes: [OverlayKeyframe] = []

    var end: Double { start + duration }
    var filename: String { fileURL.lastPathComponent }

    private enum CodingKeys: String, CodingKey {
        case id, fileURL, start, duration, sourceStart, sourceDuration
        case startX, startY, endX, endY, width, opacity
        case easing, pathMode, keyframes
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileURL = try c.decode(URL.self, forKey: .fileURL)
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 3
        sourceStart = try c.decodeIfPresent(Double.self, forKey: .sourceStart) ?? 0
        sourceDuration = try c.decodeIfPresent(Double.self, forKey: .sourceDuration) ?? 3
        startX = try c.decodeIfPresent(Double.self, forKey: .startX) ?? 0.5
        startY = try c.decodeIfPresent(Double.self, forKey: .startY) ?? 0.5
        endX = try c.decodeIfPresent(Double.self, forKey: .endX) ?? 0.5
        endY = try c.decodeIfPresent(Double.self, forKey: .endY) ?? 0.5
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.45
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        easing = try c.decodeIfPresent(OverlayEasing.self, forKey: .easing) ?? .linear
        pathMode = try c.decodeIfPresent(OverlayMotionPath.self,
                                         forKey: .pathMode) ?? .straight
        keyframes = try c.decodeIfPresent([OverlayKeyframe].self,
                                          forKey: .keyframes) ?? []
    }
}

enum OverlayEasing: String, Codable, CaseIterable, Identifiable {
    case linear = "Tuyến tính"
    case easeIn = "Tăng tốc"
    case easeOut = "Giảm tốc"
    case easeInOut = "Mượt hai đầu"

    var id: String { rawValue }
}

/// Smooth curved path passes through user-authored keyframe coordinates.
enum OverlayMotionPath: String, Codable, CaseIterable, Identifiable {
    case straight = "Đường thẳng"
    case curved = "Đường cong"
    var id: String { rawValue }
}
