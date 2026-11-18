import Foundation
import UIKit
import CoreImage
import AVFoundation
import ImageIO
import Photos

/// Core Image rendering for Mockup Studio. Everything here is thread-safe and
/// is meant to run OFF the main thread (preview: ~1400 px, export: full size).
enum MockupStudioRenderer {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let previewLongSide: CGFloat = 1400
    static let exportLongSide: CGFloat = 8192

    // MARK: Source frames

    /// A clip's frame as the editor would show it: orientation applied and the
    /// clip's own colour grade baked in. `maxSide` bounds memory for previews.
    static func loadSource(clip: TimelineClip, local: Double, maxSide: CGFloat?) async throws -> CIImage {
        let base: CIImage
        if clip.kind == .image {
            base = try loadStill(url: clip.fileURL, maxSide: maxSide)
        } else {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip.fileURL))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            if let maxSide { generator.maximumSize = CGSize(width: maxSide, height: maxSide) }
            let at = clip.startTime + max(0, local) * max(0.1, clip.playbackSpeed)
            let cg = try await generator.image(at: CMTime(seconds: max(0, at), preferredTimescale: 600)).image
            base = CIImage(cgImage: cg)
        }
        return StudioColorGrader.apply(
            base, look: clip.imageLook, intensity: clip.lookIntensity,
            adjustments: clip.colorAdjustments, autoEnhance: clip.autoEnhance,
            photoPreset: clip.photoPreset, photoPresetIntensity: clip.photoPresetIntensity
        ).cropped(to: base.extent)
    }

    private static func loadStill(url: URL, maxSide: CGFloat?) throws -> CIImage {
        if let maxSide, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true
           ] as CFDictionary) {
            return CIImage(cgImage: thumb)
        }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw SmartVideoError.invalidMedia("Không mở được ảnh: \(url.lastPathComponent)")
        }
        return image
    }

    // MARK: Composition

    /// Same two passes as the video exporter (behind-person, then front).
    static func compose(source: CIImage, layers: [MockupOverlayClip], second: Double) -> CIImage {
        let needsPerson = layers.contains {
            $0.depthMode == .behindPerson && MockupAnimationSampler.active($0, at: second)
        }
        let mask: CIImage? = needsPerson ? (try? PersonCutoutProcessor.personMask(source, quality: .fast)) : nil
        var image = source
        if needsPerson, let rear = try? MockupOverlayRenderer.apply(
            image, overlays: layers, second: second, depth: .behindPerson, personMask: mask
        ) { image = rear }
        if let front = try? MockupOverlayRenderer.apply(
            image, overlays: layers, second: second, depth: .front
        ) { image = front }
        return image
    }

    static func renderPreview(source: CIImage, layers: [MockupOverlayClip], second: Double) -> UIImage? {
        let composed = compose(source: source, layers: layers, second: second)
        let rect = source.extent
        guard let cg = context.createCGImage(composed, from: rect) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Export

    enum ExportFormat: String, CaseIterable, Identifiable {
        case png = "PNG", jpeg = "JPG"
        var id: String { rawValue }
        var fileExtension: String { self == .png ? "png" : "jpg" }
    }

    /// Full-resolution still of the current frame with every layer applied.
    static func export(clip: TimelineClip, local: Double, layers: [MockupOverlayClip],
                       second: Double, format: ExportFormat) async throws -> URL {
        var source = try await loadSource(clip: clip, local: local, maxSide: nil)
        let longest = max(source.extent.width, source.extent.height)
        if longest > exportLongSide {
            let scale = exportLongSide / longest
            source = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let rect = source.extent
        let composed = compose(source: source, layers: layers, second: second).cropped(to: rect)
        let shifted = composed.transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let output = MediaStorage.exportsDirectory
            .appendingPathComponent("ViePN-Mockup-\(UUID().uuidString.prefix(8)).\(format.fileExtension)")
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        do {
            switch format {
            case .png:
                try context.writePNGRepresentation(of: shifted, to: output, format: .RGBA8, colorSpace: space)
            case .jpeg:
                try context.writeJPEGRepresentation(
                    of: shifted, to: output, colorSpace: space,
                    options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }

    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SmartVideoError.photoPermission }
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
        }
    }
}

/// Decoded library thumbnails (256 px WebP), cached and bounded.
enum MockupThumbnailCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        c.totalCostLimit = 24 * 1024 * 1024
        return c
    }()

    static func cached(_ asset: MockupStudioAsset) -> UIImage? {
        cache.object(forKey: asset.id as NSString)
    }

    static func load(_ asset: MockupStudioAsset) async -> UIImage? {
        if let hit = cached(asset) { return hit }
        let image: UIImage? = await Task.detached(priority: .utility) {
            guard let url = asset.thumbnailURL,
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(source, 0, [
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image {
            cache.setObject(image, forKey: asset.id as NSString, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }
}
