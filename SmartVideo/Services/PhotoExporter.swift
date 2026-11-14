import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Exports a still-photo clip to a real image, NEVER via the video encoder.
enum PhotoExporter {
    static func export(
        clip: TimelineClip,
        settings: PhotoExportSettings
    ) throws -> URL {
        guard clip.kind == .image else {
            throw SmartVideoError.invalidMedia(
                "Chỉ có ảnh mới được xuất bằng Photo Export.")
        }
        guard let source = CIImage(
            contentsOf: clip.fileURL,
            options: [.applyOrientationProperty: true]
        ) else {
            throw SmartVideoError.invalidMedia(
                "Không đọc được ảnh gốc.")
        }
        let rect = source.extent.integral
        guard rect.width > 0, rect.height > 0 else {
            throw SmartVideoError.invalidMedia(
                "Ảnh gốc có kích thước không hợp lệ.")
        }
        let outputSize = try settings.outputSize(
            for: rect.size)
        let transparency = settings.transparentPersonBackground
        guard !transparency || settings.format == .png else {
            throw SmartVideoError.invalidMedia(
                "Nền trong suốt chỉ hỗ trợ PNG.")
        }
        let graded = StudioColorGrader.apply(
            source,
            look: clip.imageLook,
            intensity: clip.lookIntensity,
            adjustments: clip.colorAdjustments,
            autoEnhance: clip.autoEnhance,
            photoPreset: clip.photoPreset,
            photoPresetIntensity: clip.photoPresetIntensity
        )
        let processed: CIImage
        if transparency {
            let mask = try PersonCutoutProcessor.personMask(
                source, quality: .accurate)
            let feathered = mask.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [
                    kCIInputRadiusKey: max(0.4,
                        max(rect.width, rect.height) * 0.0006)
                ])
                .cropped(to: rect)
            processed = graded.applyingFilter(
                "CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage(
                        color: CIColor(red: 0, green: 0,
                                       blue: 0, alpha: 0)
                    ).cropped(to: rect),
                    kCIInputMaskImageKey: feathered
                ]
            ).cropped(to: rect)
        } else {
            processed = try PersonCutoutProcessor.apply(
                source,
                mode: clip.personBackground,
                foreground: graded,
                portraitFocus: clip.portraitFocus
            ).cropped(to: rect)
        }
        let shifted = processed.transformed(by:
            CGAffineTransform(translationX: -rect.minX,
                              y: -rect.minY))
        let scaleX = outputSize.width / rect.width
        let scaleY = outputSize.height / rect.height
        let scale = min(scaleX, scaleY)
        let resampled = abs(scale - 1) < 0.0001 ? shifted :
            shifted.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1
            ])
        let canvas = CGRect(origin: .zero, size: outputSize)
        let final: CIImage
        if transparency || settings.format == .png {
            final = resampled.cropped(to: canvas)
        } else {
            let background = CIImage(color: CIColor(
                red: 1, green: 1, blue: 1, alpha: 1))
                .cropped(to: canvas)
            final = resampled.composited(over: background)
                .cropped(to: canvas)
        }

        let output = MediaStorage.exportsDirectory
            .appendingPathComponent("ViePN-Photo-" +
                UUID().uuidString.prefix(10) + "." +
                settings.format.fileExtension)
        let context = CIContext(options: [
            .cacheIntermediates: false
        ])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let quality = min(1, max(0.55,
            settings.quality.isFinite ? settings.quality : 0.95))
        do {
            switch settings.format {
            case .jpeg:
                try context.writeJPEGRepresentation(
                    of: final, to: output,
                    colorSpace: colorSpace,
                    options: [.lossyCompressionQuality: quality]
                )
            case .png:
                try context.writePNGRepresentation(
                    of: final, to: output,
                    format: .RGBA8,
                    colorSpace: colorSpace
                )
            case .heic:
                try context.writeHEIFRepresentation(
                    of: final, to: output,
                    format: .RGBA8,
                    colorSpace: colorSpace,
                    options: [.lossyCompressionQuality: quality]
                )
            }
            if !settings.removeSourceMetadata {
                try copyMetadata(
                    from: clip.fileURL, to: output,
                    format: settings.format)
            }
            guard let readback = CGImageSourceCreateWithURL(
                output as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(
                    readback, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width == Int(outputSize.width),
                  height == Int(outputSize.height) else {
                throw SmartVideoError.invalidMedia(
                    "File ảnh sau xuất không đúng độ phân giải.")
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }

    /// When requested, preserve selected EXIF/TIFF/IPTC metadata.
    /// GPS is intentionally not copied by default for privacy. The output
    /// orientation is normalized to 1 so edited images are never rotated twice.
    private static func copyMetadata(
        from sourceURL: URL,
        to outputURL: URL,
        format: PhotoExportFormat
    ) throws {
        guard let original = CGImageSourceCreateWithURL(
            sourceURL as CFURL, nil),
              let oldProperties = CGImageSourceCopyPropertiesAtIndex(
                original, 0, nil) as? [CFString: Any],
              let rendered = CGImageSourceCreateWithURL(
                outputURL as CFURL, nil) else { return }
        var metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: 1
        ]
        for key in [
            kCGImagePropertyExifDictionary,
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyIPTCDictionary
        ] {
            if let value = oldProperties[key] {
                metadata[key] = value
            }
        }
        let outputType: CFString
        switch format {
        case .jpeg: outputType = UTType.jpeg.identifier as CFString
        case .png: outputType = UTType.png.identifier as CFString
        case .heic: outputType = UTType.heic.identifier as CFString
        }
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("Meta-" + UUID().uuidString +
                                    "." + format.fileExtension)
        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL, outputType, 1, nil) else { return }
        CGImageDestinationAddImageFromSource(
            destination, rendered, 0, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        do {
            try FileManager.default.removeItem(at: outputURL)
            try FileManager.default.moveItem(
                at: tempURL, to: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }
}
