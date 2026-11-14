import Foundation
import CoreImage
import Vision
import ImageIO

/// Segments a person with Apple Vision and blurs only the background.
/// It does not synthesize depth or reconstruct an optical depth map.
enum PhotoPortraitFocusProcessor {
    /// Quick on-device preflight: don't enable a background-blur effect
    /// where Vision cannot detect a person or a face.
    static func detectPerson(in fileURL: URL) async throws -> Bool {
        try await Task.detached(priority: .utility) {
            guard let image = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                    image, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512
                    ] as CFDictionary) else {
                throw SmartVideoError.invalidMedia(
                    "Không đọc được ảnh để tìm người.")
            }
            let human = VNDetectHumanRectanglesRequest()
            let face = VNDetectFaceRectanglesRequest()
            try VNImageRequestHandler(
                cgImage: thumbnail, options: [:]
            ).perform([human, face])
            return !(human.results ?? []).isEmpty ||
                   !(face.results ?? []).isEmpty
        }.value
    }

    static func apply(
        _ gradedSource: CIImage,
        settings: PhotoPortraitFocusSettings
    ) throws -> CIImage {
        guard settings.enabled else { return gradedSource }
        let extent = gradedSource.extent
        let longestSide = max(extent.width, extent.height)
        guard longestSide > 0, longestSide.isFinite,
              extent.width > 0, extent.height > 0 else {
            throw SmartVideoError.invalidMedia(
                "Kích thước ảnh không hợp lệ để xóa phông.")
        }

        let personMask = try PersonCutoutProcessor.personMask(
            gradedSource, quality: .accurate
        )
        // Reject a virtually empty segmentation instead of blurring an
        // entire landscape by mistake. Area-average is a 1x1 image.
        let average = personMask.applyingFilter(
            "CIAreaAverage", parameters: [
                kCIInputExtentKey: CIVector(cgRect: extent)
            ]
        )
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.cacheIntermediates: false])
        pixel.withUnsafeMutableBytes { buffer in
            context.render(
                average, toBitmap: buffer.baseAddress!,
                rowBytes: 4, bounds: CGRect(x: 0, y: 0,
                                             width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        // An empty matte should never change the image.
        guard pixel[0] > 2 else { return gradedSource }

        let blurRadius = max(0, min(160,
            longestSide * 0.024 * settings.blurStrength))
        let background = gradedSource.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: blurRadius
            ])
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: settings.backgroundSaturation
            ])
            .applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: -settings.backgroundDim
            ])
        let edgeRadius = max(0.01, min(18,
            longestSide * 0.0020 * settings.edgeSoftness))
        let softenedMask = personMask.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: edgeRadius
            ])
            .cropped(to: extent)
        let foreground = settings.subjectLiftEV > 0.001 ?
            gradedSource.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: settings.subjectLiftEV
            ]) : gradedSource
        return foreground.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: softenedMask
        ]).cropped(to: extent)
    }
}
