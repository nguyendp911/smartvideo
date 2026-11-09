import Foundation
import CoreGraphics

enum ClipKind: String, Codable {
    case image
    case video
}

enum VideoTransition: String, CaseIterable, Identifiable {
    case cut = "Cắt thẳng"
    case dissolve = "Hòa tan"

    var id: String { rawValue }
    var iconName: String { self == .cut ? "scissors" : "square.stack.3d.up" }
}

enum ImageMotion: String, CaseIterable, Identifiable, Codable {
    case none = "Tĩnh"
    case zoomIn = "Zoom in"
    case zoomOut = "Zoom out"
    case panLeft = "Pan trái"
    case panRight = "Pan phải"

    var id: String { rawValue }
}

enum ImageLook: String, CaseIterable, Identifiable, Codable {
    case original = "Nguyên bản"
    case cinematic = "Điện ảnh"
    case mono = "Đen trắng"
    case warm = "Màu ấm"
    case cool = "Màu lạnh"
    case tealOrange = "Teal & Orange"
    case noir = "Noir Luxe"
    case golden = "Golden Hour"
    case pastel = "Soft Pastel"
    case moody = "Moody"
    case clean = "Clean Studio"
    case forest = "Forest"
    case vintage = "Analog 35"
    case rose = "Rose Film"
    case desert = "Desert"
    case midnight = "Midnight"
    case neon = "Neon Pop"
    case editorial = "Editorial"
    case creamy = "Creamy"

    var id: String { rawValue }
}

struct ColorAdjustments: Codable, Hashable {
    var exposureEV: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    /// -1 cools the image, +1 warms it.
    var warmth: Double = 0

    static let neutral = ColorAdjustments()

    var isNeutral: Bool {
        abs(exposureEV) < 0.001 && abs(contrast - 1) < 0.001 &&
        abs(saturation - 1) < 0.001 && abs(warmth) < 0.001
    }

    private enum CodingKeys: String, CodingKey {
        case exposureEV, contrast, saturation, warmth
    }

    init(exposureEV: Double = 0, contrast: Double = 1,
         saturation: Double = 1, warmth: Double = 0) {
        self.exposureEV = Self.clamp(exposureEV, -2...2, fallback: 0)
        self.contrast = Self.clamp(contrast, 0.5...1.5, fallback: 1)
        self.saturation = Self.clamp(saturation, 0...2, fallback: 1)
        self.warmth = Self.clamp(warmth, -1...1, fallback: 0)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            exposureEV: try c.decodeIfPresent(Double.self, forKey: .exposureEV) ?? 0,
            contrast: try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1,
            saturation: try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1,
            warmth: try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        )
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>,
                             fallback: Double) -> Double {
        min(range.upperBound, max(range.lowerBound,
            value.isFinite ? value : fallback))
    }
}

struct TimelineClip: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var kind: ClipKind
    var fileURL: URL
    var duration: Double
    var startTime: Double = 0
    var originalDuration: Double
    var playbackSpeed: Double = 1.0
    var imageMotion: ImageMotion = .none
    /// Reused by both photos and videos as the selected Core Image grade.
    var imageLook: ImageLook = .original
    /// Strength of the selected grade (zero leaves the source unchanged).
    var lookIntensity: Double = 1.0
    var colorAdjustments: ColorAdjustments = .neutral
    var flipHorizontal: Bool = false
    var flipVertical: Bool = false

    init(id: UUID = UUID(), kind: ClipKind, fileURL: URL,
         duration: Double, startTime: Double = 0,
         originalDuration: Double, playbackSpeed: Double = 1.0,
         imageMotion: ImageMotion = .none,
         imageLook: ImageLook = .original,
         lookIntensity: Double = 1.0,
         colorAdjustments: ColorAdjustments = .neutral,
         flipHorizontal: Bool = false, flipVertical: Bool = false) {
        self.id = id
        self.kind = kind
        self.fileURL = fileURL
        self.duration = duration
        self.startTime = startTime
        self.originalDuration = originalDuration
        self.playbackSpeed = playbackSpeed
        self.imageMotion = imageMotion
        self.imageLook = imageLook
        self.lookIntensity = min(1, max(0, lookIntensity))
        self.colorAdjustments = colorAdjustments
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, fileURL, duration, startTime, originalDuration
        case playbackSpeed, imageMotion, imageLook, lookIntensity, colorAdjustments
        case flipHorizontal, flipVertical
    }

    /// Existing projects from 2.x-3.9 never had a lookIntensity key.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(ClipKind.self, forKey: .kind)
        fileURL = try c.decode(URL.self, forKey: .fileURL)
        duration = try c.decode(Double.self, forKey: .duration)
        startTime = try c.decodeIfPresent(Double.self, forKey: .startTime) ?? 0
        originalDuration = try c.decode(Double.self, forKey: .originalDuration)
        playbackSpeed = try c.decodeIfPresent(Double.self,
                                              forKey: .playbackSpeed) ?? 1
        imageMotion = try c.decodeIfPresent(ImageMotion.self,
                                            forKey: .imageMotion) ?? .none
        imageLook = try c.decodeIfPresent(ImageLook.self,
                                          forKey: .imageLook) ?? .original
        let rawStrength = try c.decodeIfPresent(Double.self,
                                                forKey: .lookIntensity) ?? 1
        lookIntensity = min(1, max(0, rawStrength.isFinite ? rawStrength : 1))
        colorAdjustments = try c.decodeIfPresent(ColorAdjustments.self,
                                                 forKey: .colorAdjustments) ?? .neutral
        flipHorizontal = try c.decodeIfPresent(Bool.self,
                                               forKey: .flipHorizontal) ?? false
        flipVertical = try c.decodeIfPresent(Bool.self,
                                             forKey: .flipVertical) ?? false
    }

    var renderedDuration: Double {
        kind == .video ? duration / max(0.25, playbackSpeed) : duration
    }

    var filename: String { fileURL.lastPathComponent }

    var availableDuration: Double {
        kind == .image ? 12.0 : max(0.1, originalDuration - startTime)
    }
}

enum CanvasContentMode: String, CaseIterable, Identifiable {
    case fit = "Vừa khung"
    case fill = "Phủ đầy"

    var id: String { rawValue }
}

enum RenderQuality: String, CaseIterable, Identifiable {
    case hd = "720p"
    case fullHD = "1080p"

    var id: String { rawValue }
    var shortSide: Int { self == .hd ? 720 : 1080 }
    var longSide: Int { self == .hd ? 1280 : 1920 }
    var bitRate: Int { self == .hd ? 4_000_000 : 8_000_000 }
}

enum CanvasFormat: String, CaseIterable, Identifiable {
    case portrait = "Dọc 9:16"
    case landscape = "Ngang 16:9"
    case square = "Vuông 1:1"
    case poster = "Dọc 4:5"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .portrait: return "9:16"
        case .landscape: return "16:9"
        case .square: return "1:1"
        case .poster: return "4:5"
        }
    }

    var ratio: CGFloat {
        switch self {
        case .portrait: return 9.0 / 16.0
        case .landscape: return 16.0 / 9.0
        case .square: return 1.0
        case .poster: return 4.0 / 5.0
        }
    }

    func size(for quality: RenderQuality) -> CGSize {
        let unit = quality.shortSide
        switch self {
        case .portrait:
            return CGSize(width: unit, height: quality.longSide)
        case .landscape:
            return CGSize(width: quality.longSide, height: unit)
        case .square:
            return CGSize(width: unit, height: unit)
        case .poster:
            return CGSize(width: unit, height: unit * 5 / 4)
        }
    }
}

enum SmartVideoError: LocalizedError {
    case invalidMedia(String)
    case cannotCreateWriter
    case missingVideoTrack(String)
    case cannotExport(String)
    case photoPermission

    var errorDescription: String? {
        switch self {
        case .invalidMedia(let text): return text
        case .cannotCreateWriter: return "Không thể khởi tạo bộ mã hóa video."
        case .missingVideoTrack(let name): return "Không tìm thấy track video: \(name)"
        case .cannotExport(let text): return "Xuất video thất bại: \(text)"
        case .photoPermission: return "Chưa được cấp quyền thêm video vào ứng dụng Ảnh."
        }
    }
}
