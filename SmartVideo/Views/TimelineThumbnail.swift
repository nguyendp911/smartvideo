import SwiftUI
import AVFoundation
import UIKit

/// Lazy source-media thumbnail for the editor timeline. The user sees an
/// actual frame of each video rather than an opaque generic movie icon.
struct TimelineThumbnail: View {
    let clip: TimelineClip
    @State private var image: UIImage?

    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    private var thumbKey: String {
        "\(clip.fileURL.path)|\(Int(clip.startTime * 10))"
    }

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: clip.kind == .image ? "photo.fill" : "film.fill")
                    .font(.caption)
                    .foregroundStyle(.cyan)
            }
        }
        .clipped()
        .task(id: thumbKey) {
            let key = thumbKey as NSString
            if let cached = Self.cache.object(forKey: key) {
                image = cached
                return
            }
            let url = clip.fileURL
            let kind = clip.kind
            let moment = clip.startTime
            let loaded: UIImage? = await Task.detached(priority: .utility) {
                if kind == .image {
                    return UIImage(contentsOfFile: url.path)
                }
                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 240, height: 160)
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.3, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.3, preferredTimescale: 600)
                let time = CMTime(seconds: max(0, moment + 0.05), preferredTimescale: 600)
                if let cg = try? generator.copyCGImage(at: time, actualTime: nil) {
                    return UIImage(cgImage: cg)
                }
                return nil
            }.value
            if let loaded {
                image = loaded
                Self.cache.setObject(loaded, forKey: key,
                                     cost: Int(loaded.size.width * loaded.size.height * 4))
            }
        }
    }
}
