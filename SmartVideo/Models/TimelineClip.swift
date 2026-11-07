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

    var id: String { rawValue }
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
    var imageLook: ImageLook = .original

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
