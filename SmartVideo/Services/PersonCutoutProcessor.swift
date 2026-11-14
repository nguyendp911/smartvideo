import Foundation
import Vision
import CoreImage
import CoreVideo

/// One-device person segmentation. This is a real per-frame Vision mask,
/// not chroma-key or a fake visual toggle. Only the PERSON is segmented;
/// other objects remain part of the replaceable background.
enum PersonBackground: String, CaseIterable, Codable, Identifiable {
    case original = "Giữ nguyên"
    case blur = "Xóa phông"
    case black = "Nền đen"
    case white = "Nền trắng"
    case green = "Nền xanh"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .original: return "person.crop.rectangle"
        case .blur: return "camera.aperture"
        case .black: return "moon.fill"
        case .white: return "sun.max.fill"
        case .green: return "leaf.fill"
        }
    }
}

enum PersonCutoutProcessor {
    /// Reusable normalized subject matte, mapped exactly to CI coordinates.
    static func personMask(
        _ source: CIImage,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced
    ) throws -> CIImage {
        let extent = source.extent
        guard extent.width > 0 && extent.height > 0 else {
            throw SmartVideoError.invalidMedia("Khung hình không hợp lệ.")
        }
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = quality
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(ciImage: source, options: [:])
            .perform([request])
        guard let maskBuffer = request.results?.first?.pixelBuffer else {
            throw SmartVideoError.invalidMedia(
                "Vision chưa tách được mặt nạ người."
            )
        }
        let raw = CIImage(cvPixelBuffer: maskBuffer)
        let m = raw.extent.size
        guard m.width > 0 && m.height > 0 else {
            throw SmartVideoError.invalidMedia("Mặt nạ người bị rỗng.")
        }
        return raw
            .transformed(by: CGAffineTransform(
                translationX: -raw.extent.minX,
                y: -raw.extent.minY
            ))
            .transformed(by: CGAffineTransform(
                scaleX: extent.width / m.width,
                y: extent.height / m.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: extent.minX, y: extent.minY
            ))
            .cropped(to: extent)
    }

    /// Returns image with an opaque background (MP4/H.264 has no alpha).
    /// The same function is used by the live Core Image preview and export.
    static func apply(
        _ source: CIImage, mode: PersonBackground,
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .balanced,
        foreground: CIImage? = nil,
        portraitFocus: PhotoPortraitFocusSettings = .off
    ) throws -> CIImage {
        if mode == .original {
            let graded = foreground ?? source
            return portraitFocus.enabled ?
                try PhotoPortraitFocusProcessor.apply(
                    graded, settings: portraitFocus) : graded
        }
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else {
            throw SmartVideoError.invalidMedia("Khung hình không hợp lệ để tách nền.")
        }

        let mask = try personMask(source, quality: quality)

        let background: CIImage
        switch mode {
        case .original:
            background = source
        case .blur:
            background = source.applyingFilter(
                "CIGaussianBlur", parameters: [kCIInputRadiusKey: 22]
            ).cropped(to: extent)
        case .black:
            background = CIImage(color: CIColor(red: 0, green: 0,
                                                blue: 0, alpha: 1)).cropped(to: extent)
        case .white:
            background = CIImage(color: CIColor(red: 1, green: 1,
                                                blue: 1, alpha: 1)).cropped(to: extent)
        case .green:
            background = CIImage(color: CIColor(red: 0, green: 0.62,
                                                blue: 0.12, alpha: 1)).cropped(to: extent)
        }
        return (foreground ?? source).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ]).cropped(to: extent)
    }
}
