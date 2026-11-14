import Foundation
import CoreGraphics

enum PhotoExportFormat: String, CaseIterable, Identifiable, Codable {
    case jpeg = "JPG"
    case png = "PNG"
    case heic = "HEIC"
    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        }
    }
    var supportsTransparency: Bool { self == .png }
}

enum PhotoResolution: String, CaseIterable, Identifiable, Codable {
    case original = "Gốc • không đổi kích thước"
    case twoK = "2K • cạnh dài 2048"
    case fourK = "4K • cạnh dài 4096"
    case sixK = "6K • cạnh dài 6144"
    case eightK = "8K • cạnh dài 8192"
    case custom = "Tùy chỉnh (giữ tỉ lệ)"
    var id: String { rawValue }
    var maxSide: CGFloat? {
        switch self {
        case .original, .custom: return nil
        case .twoK: return 2048
        case .fourK: return 4096
        case .sixK: return 6144
        case .eightK: return 8192
        }
    }
}

struct PhotoExportSettings: Hashable, Codable {
    var format: PhotoExportFormat = .jpeg
    var resolution: PhotoResolution = .original
    var customWidth: Int = 3000
    var customHeight: Int = 4000
    var quality: Double = 0.95
    var removeSourceMetadata: Bool = true
    var transparentPersonBackground: Bool = false
    /// 1x is normal export; 2x/4x is interpolated enlargement, NOT AI detail reconstruction.
    var upscaleFactor: Int = 1

    func outputSize(for original: CGSize) throws -> CGSize {
        guard original.width.isFinite && original.height.isFinite,
              original.width >= 1 && original.height >= 1 else {
            throw SmartVideoError.invalidMedia("Ảnh gốc có kích thước không hợp lệ.")
        }
        let longSide = max(original.width, original.height)
        let factor: CGFloat
        switch resolution {
        case .original: factor = 1
        case .twoK, .fourK, .sixK, .eightK:
            factor = (resolution.maxSide ?? longSide) / longSide
        case .custom:
            guard (16...8192).contains(customWidth),
                  (16...8192).contains(customHeight) else {
                throw SmartVideoError.invalidMedia(
                    "Kích thước tùy chỉnh phải từ 16 đến 8192 pixel mỗi cạnh.")
            }
            factor = min(CGFloat(customWidth) / original.width,
                         CGFloat(customHeight) / original.height)
        }
        guard [1, 2, 4].contains(upscaleFactor) else {
            throw SmartVideoError.invalidMedia(
                "Phóng ảnh chỉ hỗ trợ 1×, 2× hoặc 4×.")
        }
        let targetScale = factor * CGFloat(upscaleFactor)
        let width = max(1, Int((original.width * targetScale).rounded()))
        let height = max(1, Int((original.height * targetScale).rounded()))
        guard width <= 8192, height <= 8192,
              Double(width) * Double(height) <= 64_000_000 else {
            throw SmartVideoError.invalidMedia(
                "Ảnh xuất vượt giới hạn 8192 pixel mỗi cạnh hoặc 64 megapixel. Hãy giảm độ phân giải / phóng ảnh.")
        }
        return CGSize(width: width, height: height)
    }
}
