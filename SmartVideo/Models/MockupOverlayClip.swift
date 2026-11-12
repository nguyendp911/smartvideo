import Foundation

enum MockupCategory: String, CaseIterable, Codable, Identifiable {
    case window = "Bóng cửa sổ"
    case leaf = "Bóng cây"
    case flare = "Tia sáng"
    case reflection = "Phản chiếu"
    case atmosphere = "Không khí"
    case motion = "Chuyển động"
    var id: String { rawValue }
}
enum MockupBlendMode: String, CaseIterable, Codable, Identifiable {
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
enum MockupDepthMode: String, CaseIterable, Codable, Identifiable {
    case front = "Trước người"
    case behindPerson = "Sau người"
    var id: String { rawValue }
}
enum MockupAnimationStyle: String, CaseIterable, Codable, Identifiable {
    case none = "Tĩnh"
    case drift = "Trôi"
    case flicker = "Nhấp nháy"
    case pulse = "Nhịp sáng"
    case sway = "Đung đưa"
    case sweep = "Quét sáng"
    var id: String { rawValue }
}

/// Built-in, procedural assets: no third-party footage or downloads required.
/// Independent layers are saved with the project and timed on the timeline.
struct MockupOverlayClip: Identifiable, Codable, Equatable {
    var id = UUID()
    var assetID: String = "window-soft"
    var start: Double = 0
    var duration: Double = 3
    var opacity: Double = 0.6
    var blendMode: MockupBlendMode = .multiply
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var scale: Double = 1
    var rotationDegrees: Double = 0
    var flipHorizontal = false
    var flipVertical = false
    var blurRadius: Double = 9
    var feather: Double = 0.1
    var brightness: Double = 0
    var contrast: Double = 1
    var warmth: Double = 0
    var animationStyle: MockupAnimationStyle = .none
    var animationSpeed: Double = 1
    var animationAmount: Double = 0.35
    var depthMode: MockupDepthMode = .front
    var avoidFace = false
    var loop = true
    var locked = false
    var isHidden = false

    var end: Double { start + duration }
}
struct MockupAsset: Identifiable {
    let id: String
    let name: String
    let category: MockupCategory
    let style: Int
    let recommendedBlend: MockupBlendMode
    let animated: Bool
}

/// Forty-two *distinct parametrized procedural* patterns. Shadows, beams,
/// reflections and particles render directly to pixels in the app, so
/// the shipped IPA does not rely on external PNG/MOV/CDN availability.
enum MockupAssetLibrary {
    private static func group(_ category: MockupCategory,
                              _ names: [String],
                              _ ids: [String],
                              mode: MockupBlendMode,
                              animatedFrom: Int = 99) -> [MockupAsset] {
        zip(names, ids).enumerated().map { index, pair in
            MockupAsset(id: pair.1, name: pair.0, category: category,
                        style: index, recommendedBlend: mode,
                        animated: index >= animatedFrom)
        }
    }
    static let all: [MockupAsset] =
        group(.window,
              ["Window Shadow Soft", "Window Shadow Hard",
               "Window Grid", "Blinds Shadow", "Curtain Light",
               "Morning Window Glow", "Afternoon Window Beam",
               "Side Window Shadow"],
              ["window-soft","window-hard","window-grid","window-blinds",
               "window-curtain","window-morning","window-afternoon",
               "window-side"], mode: .multiply)
        + group(.leaf,
                ["Leaf Shadow Soft", "Leaf Shadow Dense",
                 "Leaf Shadow Moving", "Branch Shadow",
                 "Tropical Leaf", "Dappled Light",
                 "Garden Shadow", "Palm Shadow"],
                ["leaf-soft","leaf-dense","leaf-moving","leaf-branch",
                 "leaf-tropical","leaf-dappled","leaf-garden","leaf-palm"],
                mode: .multiply, animatedFrom: 2)
        + group(.flare,
                ["Sun Flare Left", "Sun Flare Right",
                 "Golden Hour Flare", "Light Leak Warm",
                 "Light Leak Film", "Lens Flare Soft",
                 "Lens Flare Sharp", "Sunbeam Dust"],
                ["flare-left","flare-right","flare-golden","flare-warm",
                 "flare-film","flare-soft","flare-sharp","flare-dust"],
                mode: .screen)
        + group(.reflection,
                ["Window Reflection", "Glass Reflection",
                 "Warm Lamp Glow", "Cafe Light",
                 "Neon Reflection", "Phone Screen Glow",
                 "LED Accent", "Street Light Sweep"],
                ["reflect-window","reflect-glass","reflect-lamp",
                 "reflect-cafe","reflect-neon","reflect-phone",
                 "reflect-led","reflect-street"], mode: .screen)
        + group(.atmosphere,
                ["Dust Particles","Bokeh Overlay","Haze Light",
                 "Mist Beam","Soft Fog Glow","Film Bloom"],
                ["air-dust","air-bokeh","air-haze","air-mist",
                 "air-fog","air-bloom"], mode: .screen)
        + group(.motion,
                ["Moving Leaf Shadow","Slow Light Sweep",
                 "Flicker Lamp Glow","Drift Dust Layer"],
                ["motion-leaf","motion-sweep","motion-lamp",
                 "motion-dust"], mode: .screen, animatedFrom: 0)

    static func asset(_ id: String) -> MockupAsset? {
        all.first(where: { $0.id == id })
    }
    static func makeClip(_ asset: MockupAsset,
                         at time: Double, duration: Double) -> MockupOverlayClip {
        var clip = MockupOverlayClip()
        clip.assetID = asset.id
        clip.start = max(0, time)
        clip.duration = max(0.25, duration)
        clip.blendMode = asset.recommendedBlend
        clip.opacity = asset.category == .flare ? 0.52 : 0.62
        clip.blurRadius = asset.category == .window ? 8 :
            (asset.category == .leaf ? 12 : 5)
        clip.animationStyle = asset.animated ?
            (asset.category == .leaf ? .sway :
             asset.category == .motion ? .drift : .pulse) : .none
        return clip
    }
}
struct MockupPreset: Identifiable {
    let id: String
    let name: String
    let ids: [String]
    static let all: [MockupPreset] = [
        .init(id:"morning", name:"Nắng cửa sổ",ids:["window-soft","flare-golden"]),
        .init(id:"leaf-product",name:"Bóng lá sản phẩm",ids:["leaf-soft","air-bokeh"]),
        .init(id:"golden",name:"Golden Hour",ids:["flare-golden","flare-warm"]),
        .init(id:"cafe",name:"Cafe Chill",ids:["reflect-lamp","window-curtain"]),
        .init(id:"glass",name:"Kính sang trọng",ids:["reflect-glass","flare-soft"]),
        .init(id:"interior",name:"Nội thất sáng",ids:["window-grid","air-haze"]),
        .init(id:"laptop",name:"Laptop Showcase",ids:["reflect-led","reflect-glass"]),
        .init(id:"cinematic",name:"Nắng điện ảnh",ids:["window-afternoon","air-dust"]),
        .init(id:"neon",name:"Neon Night",ids:["reflect-neon","air-bokeh"]),
        .init(id:"fashion",name:"Fashion Lookbook",ids:["leaf-moving","reflect-window"]),
        .init(id:"rain",name:"Ánh sáng qua kính",ids:["reflect-glass","air-mist"]),
        .init(id:"studio",name:"Studio Glow",ids:["reflect-lamp","air-bloom"])
    ]
}

/// Deterministic motion and timeline math shared by preview/export.
enum MockupAnimationSampler {
    struct State {
        let x: Double, y: Double, scale: Double, rotation: Double, opacity: Double
    }
    static func sample(_ c: MockupOverlayClip, at t: Double) -> State {
        let base = max(0, t - c.start) * max(0.1, c.animationSpeed)
        // Non-looped animation freezes at its final motion pose.
        // Looped animation is phase-continuous across the timed clip.
        let phase = c.loop ? base :
            min(base, 2 * Double.pi)
        let amount = min(2, max(0, c.animationAmount))
        var x = c.centerX, y = c.centerY, scale = c.scale
        var angle = c.rotationDegrees, alpha = c.opacity
        switch c.animationStyle {
        case .none: break
        case .drift: x += 0.035 * amount * sin(phase)
            y += 0.025 * amount * cos(phase * 0.75)
        case .flicker: alpha *= 0.88 + 0.12 * sin(phase * 9) * sin(phase * 3.3)
        case .pulse: alpha *= 0.85 + 0.15 * sin(phase * 2.4)
            scale *= 1 + 0.025 * amount * sin(phase * 2.4)
        case .sway: angle += 6 * amount * sin(phase * 1.4)
            x += 0.018 * amount * sin(phase * 1.2)
        case .sweep: x += 0.2 * amount * sin(phase * 0.7)
        }
        return State(x: min(1.4,max(-0.4,x)),
                     y: min(1.4,max(-0.4,y)),
                     scale: min(4,max(0.1,scale)),
                     rotation: angle,
                     opacity: min(1,max(0,alpha)))
    }
    static func active(_ clip: MockupOverlayClip, at time: Double) -> Bool {
        !clip.isHidden && time.isFinite && clip.start <= time &&
        clip.duration > 0 && time < clip.end
    }
}
