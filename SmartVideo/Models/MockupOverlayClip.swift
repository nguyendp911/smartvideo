import Foundation

/// Local, non-destructive light/shadow layers. Effects are generated offline
/// from vector paths or user-imported media, never downloaded or streamed.
enum MockupCategory: String, Codable, CaseIterable, Identifiable {
    case windows = "Cửa sổ"
    case leaves = "Bóng cây"
    case flares = "Tia sáng"
    case reflections = "Phản chiếu"
    case atmosphere = "Không khí"
    case motion = "Chuyển động"
    var id: String { rawValue }
}

enum MockupBlendMode: String, Codable, CaseIterable, Identifiable {
    case normal = "Normal"
    case multiply = "Multiply"
    case screen = "Screen"
    case overlay = "Overlay"
    case softLight = "Soft Light"
    case hardLight = "Hard Light"
    case add = "Add"
    case darken = "Darken"
    case lighten = "Lighten"
    var id: String { rawValue }
}

enum MockupDepthMode: String, Codable, CaseIterable, Identifiable {
    case front = "Trước người"
    case behindPerson = "Sau người"
    var id: String { rawValue }
}

enum MockupAnimationStyle: String, Codable, CaseIterable, Identifiable {
    case still = "Tĩnh"
    case drift = "Trôi"
    case sway = "Đung đưa"
    case pulse = "Nhịp sáng"
    case flicker = "Lập lòe"
    case sweep = "Quét ngang"
    var id: String { rawValue }
}

struct MockupOverlayClip: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var effectID: String
    var name: String
    var category: MockupCategory
    /// Imported custom PNG/JPEG; nil means fully offline generated artwork.
    var assetURL: URL? = nil
    var start: Double = 0
    var duration: Double = 3
    var opacity: Double = 0.55
    var blendMode: MockupBlendMode = .screen
    /// Normalized coordinates within the video canvas.
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var scale: Double = 1
    var rotationDegrees: Double = 0
    var flipHorizontal = false
    var flipVertical = false
    var blurRadius: Double = 3
    var feather: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var warmth: Double = 0
    var tint: Double = 0
    var animationStyle: MockupAnimationStyle = .still
    var animationSpeed: Double = 1
    var animationAmount: Double = 0.35
    var loopEnabled = true
    var depthMode: MockupDepthMode = .front
    var avoidFace = false
    var locked = false
    var muted = false

    var end: Double { start + duration }
    var isVisible: Bool { !muted && opacity > 0.001 && duration > 0.05 }

    init(effectID: String, name: String,
         category: MockupCategory) {
        self.effectID = effectID
        self.name = name
        self.category = category
    }

    /// Any project opened from an older/newer version stays editable even
    /// when optional fields are missing. Values are bounded for GPU safety.
    private enum CodingKeys: String, CodingKey {
        case id, effectID, name, category, assetURL, start, duration
        case opacity, blendMode, centerX, centerY, scale, rotationDegrees
        case flipHorizontal, flipVertical, blurRadius, feather
        case brightness, contrast, warmth, tint, animationStyle
        case animationSpeed, animationAmount, loopEnabled, depthMode
        case avoidFace, locked, muted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        effectID = try c.decode(String.self, forKey: .effectID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(
            MockupCategory.self, forKey: .category
        ) ?? .windows
        assetURL = try c.decodeIfPresent(URL.self, forKey: .assetURL)
        start = max(0, try c.decodeIfPresent(
            Double.self, forKey: .start
        ) ?? 0)
        duration = min(600, max(0.1, try c.decodeIfPresent(
            Double.self, forKey: .duration
        ) ?? 3))
        opacity = min(1, max(0, try c.decodeIfPresent(
            Double.self, forKey: .opacity
        ) ?? 0.55))
        blendMode = try c.decodeIfPresent(
            MockupBlendMode.self, forKey: .blendMode
        ) ?? .screen
        centerX = min(1.5, max(-0.5, try c.decodeIfPresent(
            Double.self, forKey: .centerX
        ) ?? 0.5))
        centerY = min(1.5, max(-0.5, try c.decodeIfPresent(
            Double.self, forKey: .centerY
        ) ?? 0.5))
        scale = min(5, max(0.25, try c.decodeIfPresent(
            Double.self, forKey: .scale
        ) ?? 1))
        rotationDegrees = min(360, max(-360,
            try c.decodeIfPresent(Double.self,
                                  forKey: .rotationDegrees) ?? 0))
        flipHorizontal = try c.decodeIfPresent(
            Bool.self, forKey: .flipHorizontal
        ) ?? false
        flipVertical = try c.decodeIfPresent(
            Bool.self, forKey: .flipVertical
        ) ?? false
        blurRadius = min(35, max(0, try c.decodeIfPresent(
            Double.self, forKey: .blurRadius
        ) ?? 3))
        feather = min(30, max(0, try c.decodeIfPresent(
            Double.self, forKey: .feather
        ) ?? 0))
        brightness = min(1, max(-1, try c.decodeIfPresent(
            Double.self, forKey: .brightness
        ) ?? 0))
        contrast = min(2, max(0, try c.decodeIfPresent(
            Double.self, forKey: .contrast
        ) ?? 1))
        warmth = min(1, max(-1, try c.decodeIfPresent(
            Double.self, forKey: .warmth
        ) ?? 0))
        tint = min(1, max(-1, try c.decodeIfPresent(
            Double.self, forKey: .tint
        ) ?? 0))
        animationStyle = try c.decodeIfPresent(
            MockupAnimationStyle.self, forKey: .animationStyle
        ) ?? .still
        animationSpeed = min(4, max(0.1, try c.decodeIfPresent(
            Double.self, forKey: .animationSpeed
        ) ?? 1))
        animationAmount = min(2, max(0, try c.decodeIfPresent(
            Double.self, forKey: .animationAmount
        ) ?? 0.35))
        loopEnabled = try c.decodeIfPresent(
            Bool.self, forKey: .loopEnabled
        ) ?? true
        depthMode = try c.decodeIfPresent(
            MockupDepthMode.self, forKey: .depthMode
        ) ?? .front
        avoidFace = try c.decodeIfPresent(
            Bool.self, forKey: .avoidFace
        ) ?? false
        locked = try c.decodeIfPresent(
            Bool.self, forKey: .locked
        ) ?? false
        muted = try c.decodeIfPresent(
            Bool.self, forKey: .muted
        ) ?? false
    }
}

struct MockupMotionState {
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double
    var opacity: Double
}

enum MockupAnimationSampler {
    static func sample(
        _ item: MockupOverlayClip, atProjectTime second: Double
    ) -> MockupMotionState {
        let raw = max(0, second - item.start)
        let timeline = item.loopEnabled ? raw :
            min(raw, 4 / max(0.1, item.animationSpeed))
        let t = timeline * item.animationSpeed
        let amount = min(2, max(0, item.animationAmount))
        var state = MockupMotionState(
            x: item.centerX, y: item.centerY,
            scale: item.scale, rotation: item.rotationDegrees,
            opacity: item.opacity
        )
        switch item.animationStyle {
        case .still: break
        case .drift:
            state.x += sin(t * 1.1) * 0.045 * amount
            state.y += cos(t * 0.8) * 0.028 * amount
        case .sway:
            state.rotation += sin(t * 1.7) * 8 * amount
            state.x += sin(t) * 0.02 * amount
        case .pulse:
            state.scale *= 1 + sin(t * 2) * 0.065 * amount
            state.opacity *= 0.85 + 0.15 * sin(t * 2) * sin(t * 2)
        case .flicker:
            state.opacity *= 0.84 + 0.16 * abs(
                sin(t * 8.3) * cos(t * 2.7)
            )
        case .sweep:
            state.x += sin(t * 0.9) * 0.18 * amount
        }
        state.opacity = min(1, max(0, state.opacity))
        return state
    }
}
