import UIKit
import ImageIO

extension MusicVideoStudio {
    /// Decoded, DOWNSAMPLED photos for the preview and timeline thumbnails.
    /// A 48-megapixel photo never sits in memory at full size: ImageIO decodes
    /// straight to the pixel size the screen needs, off the main thread.
    final class PhotoImageCache {
        static let shared = PhotoImageCache()

        private let cache: NSCache<NSString, UIImage> = {
            let c = NSCache<NSString, UIImage>()
            c.countLimit = 80
            c.totalCostLimit = 192 * 1024 * 1024
            return c
        }()

        /// Round up to 256 px steps so zooming does not create many variants.
        static func bucket(_ pixels: CGFloat) -> Int {
            guard pixels.isFinite else { return 1024 }
            return max(256, Int((pixels / 256).rounded(.up)) * 256)
        }

        private func key(_ url: URL, _ maxPixel: Int) -> NSString { "\(url.path)|\(maxPixel)" as NSString }

        func cached(_ url: URL, maxPixel: Int) -> UIImage? { cache.object(forKey: key(url, maxPixel)) }

        func load(_ url: URL, maxPixel: Int) async -> UIImage? {
            if let hit = cached(url, maxPixel: maxPixel) { return hit }
            let image = await Task.detached(priority: .userInitiated) {
                Self.decode(url, maxPixel: maxPixel)
            }.value
            if let image { store(image, url: url, maxPixel: maxPixel) }
            return image
        }

        /// Warm the cache for photos about to appear.
        func prefetch(_ urls: [URL], maxPixel: Int) {
            for url in urls where cached(url, maxPixel: maxPixel) == nil {
                Task.detached(priority: .utility) { [weak self] in
                    guard let image = Self.decode(url, maxPixel: maxPixel) else { return }
                    self?.store(image, url: url, maxPixel: maxPixel)
                }
            }
        }

        private func store(_ image: UIImage, url: URL, maxPixel: Int) {
            cache.setObject(image, forKey: key(url, maxPixel),
                            cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        }

        static func decode(_ url: URL, maxPixel: Int) -> UIImage? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }

        func removeAll() { cache.removeAllObjects() }
    }
}
