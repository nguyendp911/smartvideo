import Foundation

enum TextDepthMode: String, CaseIterable, Codable, Identifiable {
    case front = "Trước chủ thể"
    case behindPerson = "Sau người"
    var id: String { rawValue }
}

enum TextFillMode: String, CaseIterable, Codable, Identifiable {
    case solid = "Màu đơn"
    case gradient = "Chuyển sắc"
    case image = "Ảnh trong chữ"
    case video = "Video trong chữ"
    var id: String { rawValue }
}

enum TextMaskFit: String, CaseIterable, Codable, Identifiable {
    case fill = "Lấp đầy"
    case fit = "Vừa khung"
    var id: String { rawValue }
}

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
    /// v5.5: real subject-aware text compositing in export (people only).
    var depthMode: TextDepthMode = .front
    var fillMode: TextFillMode = .solid
    var fillAssetURL: URL?
    var maskScale: Double = 1
    var maskOffsetX: Double = 0
    var maskOffsetY: Double = 0
    var maskFit: TextMaskFit = .fill
    var gradientEndHex: String = "18D6F5"
    var strokeWidth: Double = 0
    var strokeHex: String = "FFFFFF"
    var shadowOpacity: Double = 0.4
    var glowRadius: Double = 0
    var fauxDepth: Double = 0
    /// Optional continuous subtle breathing animation.
    var pulseEnabled = false
    /// Ensure large, readable letter edges can remain around the person.
    var behindVisibilityAssist = true

    var end: Double { start + duration }

    private enum CodingKeys: String, CodingKey {
        case id, text, start, duration, startX, startY, endX, endY
        case fontSize, colorHex, useBackground, opacity, easing
        case pathMode, keyframes
        case depthMode, fillMode, fillAssetURL, maskScale,
             maskOffsetX, maskOffsetY, maskFit, gradientEndHex,
             strokeWidth, strokeHex, shadowOpacity, glowRadius,
             fauxDepth, pulseEnabled, behindVisibilityAssist
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
        depthMode = try c.decodeIfPresent(TextDepthMode.self, forKey: .depthMode) ?? .front
        fillMode = try c.decodeIfPresent(TextFillMode.self, forKey: .fillMode) ?? .solid
        fillAssetURL = try c.decodeIfPresent(URL.self, forKey: .fillAssetURL)
        maskScale = min(4, max(0.5,
            try c.decodeIfPresent(Double.self, forKey: .maskScale) ?? 1))
        maskOffsetX = min(1, max(-1,
            try c.decodeIfPresent(Double.self, forKey: .maskOffsetX) ?? 0))
        maskOffsetY = min(1, max(-1,
            try c.decodeIfPresent(Double.self, forKey: .maskOffsetY) ?? 0))
        maskFit = try c.decodeIfPresent(TextMaskFit.self, forKey: .maskFit) ?? .fill
        gradientEndHex = try c.decodeIfPresent(String.self, forKey: .gradientEndHex) ?? "18D6F5"
        strokeWidth = min(12, max(0,
            try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 0))
        strokeHex = try c.decodeIfPresent(String.self, forKey: .strokeHex) ?? "FFFFFF"
        shadowOpacity = min(1, max(0,
            try c.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.4))
        glowRadius = min(20, max(0,
            try c.decodeIfPresent(Double.self, forKey: .glowRadius) ?? 0))
        fauxDepth = min(20, max(0,
            try c.decodeIfPresent(Double.self, forKey: .fauxDepth) ?? 0))
        pulseEnabled = try c.decodeIfPresent(Bool.self, forKey: .pulseEnabled) ?? false
        behindVisibilityAssist = try c.decodeIfPresent(
            Bool.self, forKey: .behindVisibilityAssist
        ) ?? true
    }
}
