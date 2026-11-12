import Foundation
import UIKit
import AVFoundation
import QuartzCore

/// Bounded offline filmstrip for a looping *video inside text*.
    /// AVPlayerLayer is not deterministic in AVVideoCompositionCoreAnimationTool;
/// discrete CGImage contents frames ARE evaluated on the export timeline.
enum TextMaskMedia {
    struct Filmstrip {
        let frames: [CGImage]
        let loopSeconds: Double
        var first: CGImage? { frames.first }
        func frame(at second: Double) -> CGImage? {
            guard !frames.isEmpty else { return nil }
            let t = max(0, second.isFinite ? second : 0)
            let p = t.truncatingRemainder(dividingBy: max(0.1, loopSeconds))
            let i = min(frames.count - 1,
                        max(0, Int(p / loopSeconds * Double(frames.count))))
            return frames[i]
        }
    }

    static func load(
        url: URL, maxSeconds: Double = 4,
        framesPerSecond: Double = 8
    ) -> Filmstrip? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let asset = AVURLAsset(url: url)
        let length = CMTimeGetSeconds(asset.duration)
        guard length.isFinite, length > 0.08 else { return nil }
        let loop = min(maxSeconds, length)
        let amount = min(32, max(1, Int(ceil(loop * framesPerSecond))))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var frames: [CGImage] = []
        for n in 0..<amount {
            let moment = Double(n) / Double(amount) * loop
            if let frame = try? generator.copyCGImage(
                at: CMTime(seconds: moment, preferredTimescale: 600),
                actualTime: nil
            ) {
                frames.append(frame)
            }
        }
        guard !frames.isEmpty else { return nil }
        return Filmstrip(frames: frames, loopSeconds: loop)
    }

    static func image(url: URL?) -> CGImage? {
        guard let url, let photo = UIImage(contentsOfFile: url.path)
        else { return nil }
        return photo.cgImage
    }

    /// A precise glyph-alpha mask. The caller paints a gradient/image/video
    /// through this alpha mask, not into its bounding rectangle.
    static func glyphMask(
        text: String, size: CGSize, fontSize: CGFloat,
        strokeWidth: CGFloat = 0
    ) -> CGImage? {
        let width = max(1, Int(size.width)), height = max(1, Int(size.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { _ in
            let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.white,
                .strokeWidth: -strokeWidth,
                .paragraphStyle: paragraph
            ]
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: size.width - 12, height: size.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes, context: nil
            )
            let rect = CGRect(x: 6,
                              y: max(0, (size.height - bounds.height) / 2),
                              width: max(1, size.width - 12),
                              height: max(1, size.height))
            (text as NSString).draw(
                with: rect, options: [.usesLineFragmentOrigin,
                                      .usesFontLeading],
                attributes: attributes, context: nil
            )
        }
        return image.cgImage
    }

    static func contentLayer(
        for item: TextOverlayClip, bounds: CGRect,
        begin: Double, duration: Double,
        filmstrip: Filmstrip? = nil
    ) -> CALayer {
        let container = CALayer()
        container.bounds = bounds
        container.position = CGPoint(x: bounds.midX, y: bounds.midY)
        container.masksToBounds = true

        let fill = CALayer()
        fill.bounds = bounds
        fill.position = CGPoint(x: bounds.midX, y: bounds.midY)

        switch item.fillMode {
        case .solid:
            fill.backgroundColor = TextOverlayRenderer.uiColor(
                hex: item.colorHex
            ).cgColor
        case .gradient:
            let gradient = CAGradientLayer()
            gradient.frame = fill.bounds
            gradient.colors = [
                TextOverlayRenderer.uiColor(hex: item.colorHex).cgColor,
                TextOverlayRenderer.uiColor(hex: item.gradientEndHex).cgColor
            ]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            fill.addSublayer(gradient)
        case .image:
            fill.contents = image(url: item.fillAssetURL)
            fill.contentsGravity = item.maskFit == .fit ?
                .resizeAspect : .resizeAspectFill
        case .video:
            let film = filmstrip ?? item.fillAssetURL.flatMap {
                load(url: $0)
            }
            fill.contents = film?.first
            fill.contentsGravity = item.maskFit == .fit ?
                .resizeAspect : .resizeAspectFill
            if let film, film.frames.count >= 2 {
                let frames = CAKeyframeAnimation(keyPath: "contents")
                frames.values = film.frames
                frames.calculationMode = .discrete
                frames.duration = film.loopSeconds
                frames.repeatCount = Float.greatestFiniteMagnitude
                frames.beginTime = AVCoreAnimationBeginTimeAtZero + begin
                frames.isRemovedOnCompletion = false
                frames.fillMode = .both
                fill.add(frames, forKey: "text-video-fill")
            }
        }
        let safe = CGFloat(min(4, max(0.5, item.maskScale)))
        fill.transform = CATransform3DMakeScale(safe, safe, 1)
        fill.position = CGPoint(
            x: bounds.midX + CGFloat(item.maskOffsetX) * bounds.width * 0.5,
            y: bounds.midY - CGFloat(item.maskOffsetY) * bounds.height * 0.5
        )
        container.addSublayer(fill)

        let glyph = CALayer()
        glyph.frame = bounds
        glyph.contents = glyphMask(
            text: item.text, size: bounds.size,
            fontSize: CGFloat(min(180, max(15, item.fontSize))),
            strokeWidth: CGFloat(item.strokeWidth)
        )
        // The entire group is masked, so no rectangular image/gradient is
        // visible outside glyphs, including transparent holes inside letters.
        container.mask = glyph
        return container
    }
}
