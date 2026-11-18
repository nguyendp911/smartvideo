import Foundation

/// Per-layer soft mask. The shape is described in normalised coordinates of
/// the CANVAS (origin top-left), so it behaves the same in the preview, the
/// still export and the video export.
enum MockupMaskKind: String, Codable, CaseIterable, Identifiable {
    case none = "Không mask"
    case fadeTop = "Mờ dần từ trên"
    case fadeBottom = "Mờ dần từ dưới"
    case fadeLeft = "Mờ dần từ trái"
    case fadeRight = "Mờ dần từ phải"
    case radialKeep = "Giữ vùng tròn giữa"
    case radialHole = "Khoét vùng tròn giữa"
    case frame = "Chỉ giữ viền khung"
    var id: String { rawValue }
}

struct MockupMask: Codable, Equatable {
    var kind: MockupMaskKind = .none
    /// 0...1: how much of the canvas is hidden / how large the shape is.
    var size: Double = 0.35
    /// 0...1: softness of the edge.
    var feather: Double = 0.35
    var invert: Bool = false

    var isActive: Bool { kind != .none }

    init(kind: MockupMaskKind = .none, size: Double = 0.35,
         feather: Double = 0.35, invert: Bool = false) {
        self.kind = kind
        self.size = size
        self.feather = feather
        self.invert = invert
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(MockupMaskKind.self, forKey: .kind) ?? .none
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0.35
        feather = try c.decodeIfPresent(Double.self, forKey: .feather) ?? 0.35
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false
    }
}

enum MockupMaskMath {
    private static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard b > a else { return x < a ? 0 : 1 }
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Visibility 0 (hidden) ... 1 (fully visible) at normalised (x, y).
    static func alpha(_ mask: MockupMask, x: Double, y: Double) -> Double {
        guard mask.isActive else { return 1 }
        let size = min(1, max(0, mask.size.isFinite ? mask.size : 0.35))
        let feather = max(0.02, min(1, mask.feather.isFinite ? mask.feather : 0.35))
        var value: Double
        switch mask.kind {
        case .none:
            value = 1
        case .fadeTop, .fadeBottom, .fadeLeft, .fadeRight:
            let t: Double
            switch mask.kind {
            case .fadeTop: t = y
            case .fadeBottom: t = 1 - y
            case .fadeLeft: t = x
            default: t = 1 - x
            }
            let hidden = size * 0.8
            value = smoothstep(hidden, hidden + feather * 0.9, t)
        case .radialKeep, .radialHole:
            let distance = (((x - 0.5) * (x - 0.5) + (y - 0.5) * (y - 0.5)).squareRoot()) / 0.5
            let radius = 0.15 + size * 0.85
            let inside = 1 - smoothstep(radius - feather * 0.25, radius + feather * 0.25, distance)
            value = mask.kind == .radialKeep ? inside : 1 - inside
        case .frame:
            let edge = min(min(x, 1 - x), min(y, 1 - y))        // 0 at the border ... 0.5 centre
            let width = 0.05 + size * 0.4
            value = 1 - smoothstep(width - feather * 0.12, width + feather * 0.12, edge)
        }
        if mask.invert { value = 1 - value }
        return min(1, max(0, value))
    }
}
