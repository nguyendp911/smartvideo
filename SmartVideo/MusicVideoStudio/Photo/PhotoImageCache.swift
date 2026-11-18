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

        private let lock = NSLock()
        private var failedKeys = Set<String>()

        /// Decodes right now on the calling thread (a downsampled thumbnail is quick) so a photo is on screen
        /// in the very first frame instead of waiting for an asynchronous load to be noticed. A file that cannot
        /// be read is remembered, so it is not retried on every redraw.
        func loadNow(_ url: URL, maxPixel: Int) -> UIImage? {
            if let hit = cached(url, maxPixel: maxPixel) { return hit }
            let id = key(url, maxPixel) as String
            lock.lock(); let known = failedKeys.contains(id); lock.unlock()
            if known { return nil }
            guard let image = Self.decode(url, maxPixel: maxPixel) else {
                lock.lock(); failedKeys.insert(id); lock.unlock()
                return nil
            }
            store(image, url: url, maxPixel: maxPixel)
            return image
        }

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

        /// Thumbnail through ImageIO; if that cannot read the file, a full decode that is shrunk by hand.
        static func decode(_ url: URL, maxPixel: Int) -> UIImage? {
            if let image = thumbnail(url, maxPixel: maxPixel) { return image }
            guard let full = UIImage(contentsOfFile: url.path), full.size.width > 0, full.size.height > 0 else { return nil }
            let longest = max(full.size.width, full.size.height)
            guard longest > CGFloat(maxPixel) else { return full }
            let ratio = CGFloat(maxPixel) / longest
            let size = CGSize(width: full.size.width * ratio, height: full.size.height * ratio)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in full.draw(in: CGRect(origin: .zero, size: size)) }
        }

        private static func thumbnail(_ url: URL, maxPixel: Int) -> UIImage? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: image)
        }

        func removeAll() {
            cache.removeAllObjects()
            lock.lock(); failedKeys.removeAll(); lock.unlock()
        }
    }
}
