import Foundation

struct MockupDefinition: Identifiable {
    let id: String
    let name: String
    let category: MockupCategory
    let icon: String
    let blend: MockupBlendMode
    let opacity: Double
    let animation: MockupAnimationStyle
    let depth: MockupDepthMode
    let variant: Int

    func makeClip(start: Double, duration: Double) -> MockupOverlayClip {
        var result = MockupOverlayClip(
            effectID: id, name: name, category: category
        )
        result.start = max(0, start)
        result.duration = max(0.1, duration)
        result.blendMode = blend
        result.opacity = opacity
        result.animationStyle = animation
        result.depthMode = depth
        result.blurRadius = category == .windows ||
            category == .leaves ? 4 : 1
        result.scale = 1.15
        return result
    }
}

/// All 42 bundled effects are procedural, offline, and genuinely distinct
/// via their unique variant/geometry/seed. No internet, paid stock licenses,
/// external model downloads or zipped alpha videos are required.
enum MockupAssetLibrary {
    private static func definition(
        _ id: String, _ name: String, _ category: MockupCategory,
        _ icon: String, _ blend: MockupBlendMode,
        _ opacity: Double, _ animation: MockupAnimationStyle = .still,
        _ depth: MockupDepthMode = .front, _ variant: Int
    ) -> MockupDefinition {
        MockupDefinition(
            id: id, name: name, category: category,
            icon: icon, blend: blend, opacity: opacity,
            animation: animation, depth: depth, variant: variant
        )
    }

    static let all: [MockupDefinition] = [
        // Bóng cửa sổ – 8
        definition("win-soft", "Window Shadow Soft", .windows, "window.shade.open", .multiply, 0.48, .still, .behindPerson, 0),
        definition("win-hard", "Window Shadow Hard", .windows, "window.shade.closed", .multiply, 0.73, .still, .behindPerson, 1),
        definition("win-grid", "Window Grid", .windows, "square.grid.3x3", .multiply, 0.60, .still, .behindPerson, 2),
        definition("win-blinds", "Blinds Shadow", .windows, "line.3.horizontal", .multiply, 0.53, .still, .behindPerson, 3),
        definition("win-curtain", "Curtain Light", .windows, "curtains.closed", .screen, 0.42, .drift, .front, 4),
        definition("win-morning", "Morning Window Glow", .windows, "sunrise", .screen, 0.36, .still, .front, 5),
        definition("win-afternoon", "Afternoon Window Beam", .windows, "sun.max", .screen, 0.55, .still, .front, 6),
        definition("win-side", "Side Window Shadow", .windows, "rectangle.split.2x1", .multiply, 0.54, .still, .behindPerson, 7),
        // Bóng cây và lá – 8
        definition("leaf-soft", "Leaf Shadow Soft", .leaves, "leaf", .multiply, 0.42, .sway, .behindPerson, 0),
        definition("leaf-dense", "Leaf Shadow Dense", .leaves, "leaf.fill", .multiply, 0.66, .drift, .behindPerson, 1),
        definition("leaf-moving", "Leaf Shadow Moving", .leaves, "wind", .multiply, 0.44, .sway, .behindPerson, 2),
        definition("leaf-branch", "Branch Shadow", .leaves, "tree", .multiply, 0.55, .still, .behindPerson, 3),
        definition("leaf-tropical", "Tropical Leaf Shadow", .leaves, "leaf", .multiply, 0.61, .sway, .behindPerson, 4),
        definition("leaf-dappled", "Dappled Sunlight", .leaves, "sun.haze", .softLight, 0.55, .drift, .front, 5),
        definition("leaf-garden", "Garden Shadow", .leaves, "tree.fill", .multiply, 0.48, .drift, .behindPerson, 6),
        definition("leaf-palm", "Palm Leaf Shadow", .leaves, "leaf", .multiply, 0.62, .sway, .behindPerson, 7),
        // Tia sáng và flare – 8
        definition("flare-left", "Sun Flare Left", .flares, "sun.max", .screen, 0.55, .drift, .front, 0),
        definition("flare-right", "Sun Flare Right", .flares, "sun.max", .screen, 0.53, .drift, .front, 1),
        definition("flare-golden", "Golden Hour Flare", .flares, "sunset.fill", .screen, 0.64, .pulse, .front, 2),
        definition("flare-leak", "Light Leak Warm", .flares, "camera.filters", .screen, 0.49, .drift, .front, 3),
        definition("flare-film", "Film Light Leak", .flares, "film", .screen, 0.45, .flicker, .front, 4),
        definition("flare-soft", "Soft Lens Flare", .flares, "camera.aperture", .screen, 0.37, .drift, .front, 5),
        definition("flare-sharp", "Sharp Lens Flare", .flares, "sparkle", .add, 0.43, .sweep, .front, 6),
        definition("flare-dust", "Sunbeam Dust", .flares, "sun.haze.fill", .screen, 0.60, .drift, .front, 7),
        // Phản chiếu & nội thất – 8
        definition("reflect-window", "Window Reflection", .reflections, "square.on.square", .screen, 0.35, .still, .front, 0),
        definition("reflect-glass", "Glass Reflection", .reflections, "rectangle.on.rectangle", .screen, 0.42, .drift, .front, 1),
        definition("reflect-lamp", "Warm Lamp Glow", .reflections, "lightbulb", .screen, 0.55, .flicker, .front, 2),
        definition("reflect-cafe", "Cafe Light Shadow", .reflections, "cup.and.saucer", .softLight, 0.39, .pulse, .front, 3),
        definition("reflect-neon", "Neon Reflection", .reflections, "light.beacon.max", .add, 0.39, .flicker, .front, 4),
        definition("reflect-phone", "Phone Screen Glow", .reflections, "iphone", .screen, 0.45, .pulse, .front, 5),
        definition("reflect-led", "LED Accent", .reflections, "lightbulb.led", .add, 0.41, .pulse, .front, 6),
        definition("reflect-street", "Street Light Sweep", .reflections, "light.beacon.max", .screen, 0.50, .sweep, .front, 7),
        // Không khí / texture – 6
        definition("air-dust", "Dust Particles", .atmosphere, "sparkles", .screen, 0.43, .drift, .front, 0),
        definition("air-bokeh", "Bokeh Overlay", .atmosphere, "circle.hexagongrid", .screen, 0.42, .drift, .front, 1),
        definition("air-haze", "Haze Light", .atmosphere, "cloud.sun", .screen, 0.41, .pulse, .front, 2),
        definition("air-mist", "Mist Beam", .atmosphere, "cloud.fog", .screen, 0.36, .drift, .front, 3),
        definition("air-fog", "Soft Fog Glow", .atmosphere, "cloud", .screen, 0.32, .pulse, .front, 4),
        definition("air-film", "Film Bloom", .atmosphere, "camera", .softLight, 0.38, .pulse, .front, 5),
        // Motion series – 4
        definition("motion-leaf", "Moving Leaf Shadow", .motion, "leaf", .multiply, 0.51, .sway, .behindPerson, 0),
        definition("motion-sweep", "Slow Light Sweep", .motion, "sun.max", .screen, 0.50, .sweep, .front, 1),
        definition("motion-lamp", "Lamp Flicker", .motion, "lightbulb", .screen, 0.55, .flicker, .front, 2),
        definition("motion-dust", "Drifting Dust", .motion, "sparkles", .screen, 0.46, .drift, .front, 3)
    ]

    static func find(_ id: String) -> MockupDefinition? {
        all.first { $0.id == id }
    }
}

struct MockupMoodPreset: Identifiable {
    let id: String
    let name: String
    let effectIDs: [String]

    static let all: [MockupMoodPreset] = [
        .init(id: "morning", name: "Nắng cửa sổ", effectIDs: ["win-soft", "win-morning"]),
        .init(id: "leaf-product", name: "Bóng lá sản phẩm", effectIDs: ["leaf-soft", "air-bokeh"]),
        .init(id: "golden", name: "Golden Hour", effectIDs: ["flare-golden", "air-dust"]),
        .init(id: "cafe", name: "Cafe Warm", effectIDs: ["reflect-lamp", "air-haze"]),
        .init(id: "glass", name: "Glass Luxury", effectIDs: ["reflect-glass", "flare-soft"]),
        .init(id: "laptop", name: "Laptop Showcase", effectIDs: ["reflect-led", "reflect-glass"]),
        .init(id: "interior", name: "Interior Soft Sun", effectIDs: ["win-blinds", "flare-dust"]),
        .init(id: "fashion", name: "Fashion Lifestyle", effectIDs: ["leaf-tropical", "flare-soft"]),
        .init(id: "neon", name: "Neon Night", effectIDs: ["reflect-neon", "reflect-street"]),
        .init(id: "cinematic", name: "Dusty Cinematic", effectIDs: ["flare-film", "air-dust"]),
        .init(id: "showroom", name: "Showroom", effectIDs: ["win-afternoon", "reflect-window"]),
        .init(id: "street", name: "Street Sunset", effectIDs: ["motion-sweep", "air-haze"])
    ]
}
