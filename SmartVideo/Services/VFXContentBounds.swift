import Foundation
import AVFoundation
import CoreGraphics
import UIKit

enum VFXCoverage: String, CaseIterable, Identifiable {
    case videoOnly = "Chỉ trong hình"
    case entireCanvas = "Toàn khung"

    var id: String { rawValue }
}

/// Estimates the actual visible media rectangle, including letterboxing
/// which was already burned into the source MP4. Deliberately samples one
/// small thumbnail to keep memory and CPU usage low on iPhone 12 Pro Max.
enum VFXContentBounds {
    static func detect(clips: [TimelineClip], canvas: CGSize,
                       mode: CanvasContentMode) async -> CGRect {
        let bounds = CGRect(origin: .zero, size: canvas)
        guard let source = clips.first else { return bounds }
        if source.kind == .image {
            guard let image = UIImage(contentsOfFile: source.fileURL.path) else {
                return bounds
            }
            return placedMediaRect(
                oriented: image.size, canvas: canvas, mode: mode
            ).intersection(bounds)
        }

        let asset = AVURLAsset(url: source.fileURL)
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = videoTracks.first else { return bounds }
            let sourceSize = try await track.load(.naturalSize)
            let preferred = try await track.load(.preferredTransform)
            let oriented = CGRect(origin: .zero, size: sourceSize)
                .applying(preferred).standardized.size

            let mappedRect = placedMediaRect(
                oriented: oriented, canvas: canvas, mode: mode
            )
            if mode == .fill {
                return bounds
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 224, height: 224)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
            let sampleAt = min(max(0, source.startTime + 0.25),
                               max(0, source.originalDuration - 0.1))
            let (frame, _) = try await generator.image(
                at: CMTime(seconds: sampleAt, preferredTimescale: 600)
            )
            guard let normalized = visiblePixelBounds(frame) else {
                return mappedRect.intersection(bounds)
            }

            let inside = CGRect(
                x: mappedRect.minX + normalized.minX * mappedRect.width,
                y: mappedRect.minY + normalized.minY * mappedRect.height,
                width: normalized.width * mappedRect.width,
                height: normalized.height * mappedRect.height
            )
            let clipped = inside.intersection(bounds)
            return clipped.width >= canvas.width * 0.18 &&
                   clipped.height >= canvas.height * 0.10 ?
                    clipped : mappedRect.intersection(bounds)
        } catch {
            return bounds
        }
    }

    private static func placedMediaRect(oriented: CGSize, canvas: CGSize,
                                        mode: CanvasContentMode) -> CGRect {
        guard oriented.width > 0, oriented.height > 0 else {
            return CGRect(origin: .zero, size: canvas)
        }
        let sx = canvas.width / oriented.width
        let sy = canvas.height / oriented.height
        let scale = mode == .fill ? max(sx, sy) : min(sx, sy)
        let w = oriented.width * scale
        let h = oriented.height * scale
        return CGRect(x: (canvas.width - w) / 2,
                      y: (canvas.height - h) / 2, width: w, height: h)
    }

    private static func visiblePixelBounds(_ frame: CGImage) -> CGRect? {
        let w = 64, h = 112, rowBytes = w * 4
        var rgba = [UInt8](repeating: 0, count: h * rowBytes)
        let completed = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress,
                                      width: w, height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: rowBytes,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            ctx.interpolationQuality = .medium
            ctx.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard completed else { return nil }
        var minRow = h, maxRow = -1
        var minCol = w, maxCol = -1
        for y in 0..<h {
            var brightRow = 0
            for x in 0..<w {
                let base = (y * w + x) * 4
                let value = (Int(rgba[base]) + Int(rgba[base + 1]) +
                             Int(rgba[base + 2])) / 3
                if value >= 30 { brightRow += 1 }
            }
            if brightRow >= 9 {
                minRow = min(minRow, y)
                maxRow = max(maxRow, y)
            }
        }
        guard maxRow >= minRow, maxRow - minRow >= 9 else { return nil }
        // Use full frame width: most 16:9 footage extends horizontally
        // even if the leading/trailing pixels are dark.
        minCol = 0
        maxCol = w - 1
        let heightRatio = CGFloat(maxRow - minRow + 1) / CGFloat(h)
        if heightRatio > 0.96 { return nil } // no inner letterbox
        return CGRect(x: CGFloat(minCol) / CGFloat(w),
                      y: CGFloat(minRow) / CGFloat(h),
                      width: CGFloat(maxCol - minCol + 1) / CGFloat(w),
                      height: heightRatio)
    }
}
