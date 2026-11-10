import Foundation

enum StudioPresetCategory: String, CaseIterable, Identifiable {
    case cinematic = "Cinematic"
    case creator = "Social / Reels"
    case lifestyle = "Lifestyle"
    case editorial = "Editorial"
    case retro = "Retro"
    case commerce = "Product / Brand"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cinematic: return "film.stack"
        case .creator: return "bolt.fill"
        case .lifestyle: return "sun.max.fill"
        case .editorial: return "text.alignleft"
        case .retro: return "camera.aperture"
        case .commerce: return "shippingbox.fill"
        }
    }

    var colors: [String] {
        switch self {
        case .cinematic: return ["356C85", "101B29"]
        case .creator: return ["EA60A9", "4C2A9B"]
        case .lifestyle: return ["F1BD90", "825878"]
        case .editorial: return ["7A8592", "1B2737"]
        case .retro: return ["CA9974", "593447"]
        case .commerce: return ["79BEDC", "153B54"]
        }
    }
}

/// Curated editing recipes use only in-app Core Image and procedural VFX.
/// Image grades operate on still photos; video is styled with composition VFX.
struct StudioPreset: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let category: StudioPresetCategory
    let imageLook: ImageLook
    let motion: ImageMotion
    let effects: [VFXPreset]
    let intensity: Double
    let transition: VideoTransition
    let titleMotion: ImageKeyframePreset
    let textColor: String
    let subtitleStyle: SubtitleAppearance.Preset

    init(id: String, title: String, subtitle: String,
         category: StudioPresetCategory, imageLook: ImageLook,
         motion: ImageMotion, effects: [VFXPreset],
         intensity: Double, transition: VideoTransition,
         titleMotion: ImageKeyframePreset,
         textColor: String,
         subtitles: SubtitleAppearance.Preset) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.imageLook = imageLook
        self.motion = motion
        self.effects = effects
        self.intensity = intensity
        self.transition = transition
        self.titleMotion = titleMotion
        self.textColor = textColor
        self.subtitleStyle = subtitles
    }

    static let all: [StudioPreset] = [
        .init(id: "neo-cinema", title: "Neo Cinema", subtitle: "Teal/Orange, hạt phim cao cấp", category: .cinematic,
              imageLook: .tealOrange, motion: .zoomIn, effects: [.vignette, .grain],
              intensity: 0.28, transition: .dissolve, titleMotion: .punchIn,
              textColor: "FFFFFF", subtitles: .classic),
        .init(id: "noir-luxe", title: "Noir Luxe", subtitle: "Đen trắng tối giản, tương phản sâu", category: .cinematic,
              imageLook: .noir, motion: .panRight, effects: [.vignette, .cinemaBars],
              intensity: 0.26, transition: .dissolve, titleMotion: .fade,
              textColor: "E6E1D8", subtitles: .minimal),
        .init(id: "golden-film", title: "Golden Film", subtitle: "Tông hoàng hôn, ánh sáng phim", category: .cinematic,
              imageLook: .golden, motion: .zoomIn, effects: [.dust, .lightLeak],
              intensity: 0.24, transition: .dissolve, titleMotion: .slideUp,
              textColor: "FFDFAB", subtitles: .classic),
        .init(id: "midnight-thriller", title: "Midnight Thriller", subtitle: "Sắc xanh thẫm, không khí kịch tính", category: .cinematic,
              imageLook: .midnight, motion: .panLeft, effects: [.vignette, .lightStreak],
              intensity: 0.3, transition: .cut, titleMotion: .punchIn,
              textColor: "B3DDE6", subtitles: .highContrast),
        .init(id: "viral-pop", title: "Viral Pop", subtitle: "Tươi sáng, nhịp nhanh cho Reels", category: .creator,
              imageLook: .neon, motion: .zoomIn, effects: [.bokeh, .flash],
              intensity: 0.2, transition: .cut, titleMotion: .pulse,
              textColor: "FFD972", subtitles: .yellow),
        .init(id: "neon-pulse", title: "Neon Pulse", subtitle: "Vệt sáng mạnh, năng lượng công nghệ", category: .creator,
              imageLook: .neon, motion: .panRight, effects: [.lightStreak, .scanlines],
              intensity: 0.27, transition: .cut, titleMotion: .pulse,
              textColor: "A4F6FF", subtitles: .yellow),
        .init(id: "flash-cut", title: "Flash Cut", subtitle: "Dựng cắt ngắn, flash vừa phải", category: .creator,
              imageLook: .clean, motion: .panRight, effects: [.flash, .lightStreak],
              intensity: 0.15, transition: .cut, titleMotion: .spin,
              textColor: "FFFFFF", subtitles: .classic),
        .init(id: "digital-edge", title: "Digital Edge", subtitle: "Scanline sắc, tia sáng nhẹ", category: .creator,
              imageLook: .cool, motion: .zoomOut, effects: [.scanlines, .sparks],
              intensity: 0.18, transition: .cut, titleMotion: .punchIn,
              textColor: "99E6FF", subtitles: .classic),
        .init(id: "soft-morning", title: "Soft Morning", subtitle: "Màu pastel nhẹ, không khí dịu", category: .lifestyle,
              imageLook: .pastel, motion: .zoomOut, effects: [.dust],
              intensity: 0.16, transition: .dissolve, titleMotion: .fade,
              textColor: "FFF5E9", subtitles: .minimal),
        .init(id: "sunset-diary", title: "Sunset Diary", subtitle: "Ấm và lãng mạn, bokeh tinh tế", category: .lifestyle,
              imageLook: .golden, motion: .zoomIn, effects: [.lightLeak, .bokeh],
              intensity: 0.19, transition: .dissolve, titleMotion: .slideUp,
              textColor: "FFDFC2", subtitles: .classic),
        .init(id: "clean-vlog", title: "Clean Vlog", subtitle: "Sáng thoáng, cân bằng đơn giản", category: .lifestyle,
              imageLook: .clean, motion: .panLeft, effects: [.vignette],
              intensity: 0.1, transition: .dissolve, titleMotion: .slideUp,
              textColor: "FFFFFF", subtitles: .minimal),
        .init(id: "rose-bloom", title: "Rose Bloom", subtitle: "Chất hồng phim, ánh sáng mềm", category: .lifestyle,
              imageLook: .rose, motion: .zoomIn, effects: [.bokeh, .dust],
              intensity: 0.19, transition: .dissolve, titleMotion: .fade,
              textColor: "FFE7F0", subtitles: .classic),
        .init(id: "mono-editorial", title: "Mono Editorial", subtitle: "Đen trắng kiểu tạp chí", category: .editorial,
              imageLook: .noir, motion: .panRight, effects: [.grain],
              intensity: 0.2, transition: .cut, titleMotion: .slideUp,
              textColor: "FFFFFF", subtitles: .highContrast),
        .init(id: "minimal-vision", title: "Minimal Vision", subtitle: "Sạch, gọn, không phụ kiện thừa", category: .editorial,
              imageLook: .editorial, motion: .none, effects: [],
              intensity: 0.12, transition: .cut, titleMotion: .fade,
              textColor: "FFFFFF", subtitles: .minimal),
        .init(id: "gallery-white", title: "Gallery White", subtitle: "Studio sáng, không gian thoáng", category: .editorial,
              imageLook: .clean, motion: .zoomOut, effects: [],
              intensity: 0.11, transition: .dissolve, titleMotion: .fade,
              textColor: "FFFFFF", subtitles: .minimal),
        .init(id: "quiet-luxury", title: "Quiet Luxury", subtitle: "Màu kem sang trọng, chi tiết tinh tế", category: .editorial,
              imageLook: .creamy, motion: .panLeft, effects: [.vignette],
              intensity: 0.12, transition: .dissolve, titleMotion: .punchIn,
              textColor: "FBE6CA", subtitles: .minimal),
        .init(id: "analog-35", title: "Analog 35", subtitle: "Hạt và xước phim cổ điển", category: .retro,
              imageLook: .vintage, motion: .zoomIn, effects: [.grain, .filmScratch],
              intensity: 0.22, transition: .dissolve, titleMotion: .slideUp,
              textColor: "F5DCB5", subtitles: .classic),
        .init(id: "vhs-tape", title: "VHS Tape", subtitle: "Quét băng cũ, chất hoài niệm", category: .retro,
              imageLook: .moody, motion: .panRight, effects: [.scanlines, .filmScratch],
              intensity: 0.26, transition: .cut, titleMotion: .fade,
              textColor: "C8DEDB", subtitles: .classic),
        .init(id: "y2k-lights", title: "Y2K Lights", subtitle: "Neon pha retro thập niên 2000", category: .retro,
              imageLook: .neon, motion: .zoomIn, effects: [.bokeh, .lightStreak],
              intensity: 0.24, transition: .cut, titleMotion: .spin,
              textColor: "F5A8EF", subtitles: .yellow),
        .init(id: "memory-film", title: "Memory Film", subtitle: "Ký ức ấm, bụi phim mềm", category: .retro,
              imageLook: .vintage, motion: .zoomOut, effects: [.dust, .vignette],
              intensity: 0.18, transition: .dissolve, titleMotion: .fade,
              textColor: "FFE3B2", subtitles: .classic),
        .init(id: "product-hero", title: "Product Hero", subtitle: "Sản phẩm gọn, ánh sáng điểm nhấn", category: .commerce,
              imageLook: .clean, motion: .zoomIn, effects: [.lightStreak],
              intensity: 0.12, transition: .dissolve, titleMotion: .punchIn,
              textColor: "FFFFFF", subtitles: .minimal),
        .init(id: "luxury-reveal", title: "Luxury Reveal", subtitle: "Sang trọng, khung hình đậm nét", category: .commerce,
              imageLook: .cinematic, motion: .zoomOut, effects: [.vignette, .cinemaBars],
              intensity: 0.18, transition: .dissolve, titleMotion: .fade,
              textColor: "F2DDAC", subtitles: .minimal),
        .init(id: "tech-launch", title: "Tech Launch", subtitle: "Giới thiệu công nghệ xanh lạnh", category: .commerce,
              imageLook: .cool, motion: .zoomIn, effects: [.lightStreak, .scanlines],
              intensity: 0.19, transition: .cut, titleMotion: .slideUp,
              textColor: "9FE7FF", subtitles: .classic),
        .init(id: "food-glow", title: "Food Glow", subtitle: "Món ăn ấm áp, sắc tươi", category: .commerce,
              imageLook: .golden, motion: .zoomIn, effects: [.lightLeak],
              intensity: 0.12, transition: .dissolve, titleMotion: .punchIn,
              textColor: "FFF0BD", subtitles: .minimal),
        .init(id: "laptop-review", title: "Laptop Review", subtitle: "Review laptop và thiết bị công nghệ", category: .commerce,
              imageLook: .clean, motion: .panRight, effects: [.vignette],
              intensity: 0.10, transition: .dipWhite, titleMotion: .slideUp,
              textColor: "FFFFFF", subtitles: .highContrast),
        .init(id: "product-discount", title: "Sale Flash", subtitle: "Giới thiệu ưu đãi sản phẩm ngắn", category: .commerce,
              imageLook: .neon, motion: .zoomIn, effects: [.flash, .lightStreak],
              intensity: 0.16, transition: .cut, titleMotion: .punchIn,
              textColor: "FFE75E", subtitles: .yellow),
        .init(id: "lesson-explainer", title: "Lesson Explainer", subtitle: "Video hướng dẫn và bài học rõ nét", category: .editorial,
              imageLook: .clean, motion: .none, effects: [],
              intensity: 0.05, transition: .dipWhite, titleMotion: .slideUp,
              textColor: "FFFFFF", subtitles: .highContrast),
        .init(id: "travel-recap", title: "Travel Recap", subtitle: "Tổng kết du lịch và chuyển cảnh mềm", category: .lifestyle,
              imageLook: .golden, motion: .panLeft, effects: [.lightLeak, .dust],
              intensity: 0.16, transition: .dissolve, titleMotion: .fade,
              textColor: "FFF2DB", subtitles: .classic),
        .init(id: "daily-story", title: "Daily Story", subtitle: "Câu chuyện đời thường dọc 9:16", category: .creator,
              imageLook: .pastel, motion: .zoomIn, effects: [.bokeh],
              intensity: 0.12, transition: .dipWhite, titleMotion: .fade,
              textColor: "FFFFFF", subtitles: .minimal),
        .init(id: "dramatic-portrait", title: "Portrait Hero", subtitle: "Chân dung với ánh sáng tương phản", category: .cinematic,
              imageLook: .moody, motion: .zoomIn, effects: [.vignette, .grain],
              intensity: 0.16, transition: .dipBlack, titleMotion: .punchIn,
              textColor: "F5F0E8", subtitles: .classic)
    ]

    static func find(_ id: String?) -> StudioPreset? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}
