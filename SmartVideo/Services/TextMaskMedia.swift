import Foundation
import UIKit
import AVFoundation
import QuartzCore

/// Render real RGBA glyph pixels *before* Core Animation export.
/// AVVideoCompositionCoreAnimationTool does not consistently serialize
/// CALayer.mask chains; opaque layer shapes containing a non-zero alpha
/// bitmap are reliable both in Simulator and the iPhone AV exporter.
enum TextMaskMedia {
    struct Filmstrip {
        let frames: [CGImage]
        let loopSeconds: Double
        var first: CGImage? { frames.first }
        func frame(at second: Double) -> CGImage? {
            guard !frames.isEmpty else { return nil }
            let time = max(0, second.isFinite ? second : 0)
            let length = max(0.1, loopSeconds)
            let progress = time.truncatingRemainder(
                dividingBy: length
            ) / length
            return frames[min(frames.count - 1,
                              Int(progress * Double(frames.count)))]
        }
    }

    static func load(
        url: URL, maxSeconds: Double = 4,
        framesPerSecond: Double = 8
    ) -> Filmstrip? {
        guard FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        let asset = AVURLAsset(url: url)
        let length = CMTimeGetSeconds(asset.duration)
        guard length.isFinite, length >= 0.08 else { return nil }
        let loop = min(maxSeconds, length)
        let frameCount = min(32, max(1, Int(ceil(loop *
                                               framesPerSecond))))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        var frames: [CGImage] = []
        for index in 0..<frameCount {
            let timestamp = Double(index) / Double(frameCount) * loop
            if let bitmap = try? generator.copyCGImage(
                at: CMTime(seconds: timestamp,
                           preferredTimescale: 600),
                actualTime: nil
            ) {
                frames.append(bitmap)
            }
        }
        return frames.isEmpty ? nil :
            Filmstrip(frames: frames, loopSeconds: loop)
    }

    static func image(url: URL?) -> CGImage? {
        guard let url, let bitmap = UIImage(
            contentsOfFile: url.path
        ) else { return nil }
        return bitmap.cgImage
    }

    /// Generates a glyph alpha image, not a CALayer text mask.
    static func glyphMask(
        text: String, size: CGSize, fontSize: CGFloat,
        strokeWidth: CGFloat = 0, outlineOnly: Bool = false,
        fontName: String = "", tracking: CGFloat = 0, curve: CGFloat = 0
    ) -> CGImage? {
        let sz = safeSize(size)
        let renderer = UIGraphicsImageRenderer(
            size: sz, format: rgbaFormat()
        )
        let result = renderer.image { _ in
            let font = UIFont(name: fontName, size: fontSize)
                ?? UIFont.systemFont(ofSize: fontSize, weight: .black)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .kern: tracking
            ]
            // Explicit zero stroke width is accepted in UIFont drawing,
            // but omitting it for normal glyphs avoids inconsistent
            // system text rendering on different iOS versions.
            if strokeWidth > 0 {
                attributes[.strokeColor] = UIColor.white
                attributes[.strokeWidth] = outlineOnly ?
                    max(0.1, strokeWidth) : -strokeWidth
            }
            let textWidth = max(1, sz.width - 12)
            let measure = (text as NSString).boundingRect(
                with: CGSize(width: textWidth, height: sz.height),
                options: [.usesLineFragmentOrigin,
                          .usesFontLeading],
                attributes: attributes, context: nil
            )
            let rect = CGRect(
                x: 6, y: max(0, (sz.height - measure.height) / 2),
                width: textWidth,
                height: sz.height
            )
            if abs(curve) < 0.5 {
                (text as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes, context: nil
                )
            } else {
                let letters = text.map(String.init)
                let widths = letters.map {
                    ($0 as NSString).size(withAttributes: attributes).width
                }
                let total = widths.reduce(CGFloat.zero, +) +
                    tracking * CGFloat(max(0, letters.count - 1))
                var cursor = (sz.width - total) / 2
                let baseY = (sz.height - font.lineHeight) / 2
                for (index, letter) in letters.enumerated() {
                    let width = widths[index]
                    let x = cursor + width / 2
                    let u = (x - sz.width / 2) / max(1, sz.width / 2)
                    let y = -curve * (1 - u * u)
                    let angle = atan(2 * curve * u / max(1, sz.width / 2))
                    let ctx = UIGraphicsGetCurrentContext()
                    ctx?.saveGState()
                    ctx?.translateBy(x: x, y: baseY + y)
                    ctx?.rotate(by: angle)
                    (letter as NSString).draw(
                        at: CGPoint(x: -width / 2, y: 0),
                        withAttributes: attributes
                    )
                    ctx?.restoreGState()
                    cursor += width + tracking
                }
            }
        }
        return result.cgImage
    }

    static func rasterizedGlyph(
        for item: TextOverlayClip,
        size: CGSize, videoFrame: CGImage? = nil
    ) -> CGImage? {
        let size = safeSize(size)
        guard let mask = glyphMask(
            text: item.text, size: size,
            fontSize: CGFloat(min(180, max(15, item.fontSize))),
            fontName: item.fontName,
            tracking: CGFloat(item.letterSpacing),
            curve: CGFloat(item.curveAmount)
        ) else { return nil }
        let bitmap = UIGraphicsImageRenderer(
            size: size, format: rgbaFormat()
        ).image { drawing in
            let rect = CGRect(origin: .zero, size: size)
            switch item.fillMode {
            case .solid:
                TextOverlayRenderer.uiColor(hex: item.colorHex)
                    .setFill()
                UIRectFill(rect)
            case .gradient:
                let cg = drawing.cgContext
                let colors: [CGColor] = [
                    TextOverlayRenderer.uiColor(
                        hex: item.colorHex
                    ).cgColor,
                    TextOverlayRenderer.uiColor(
                        hex: item.gradientEndHex
                    ).cgColor
                ]
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors as CFArray, locations: [0, 1]
                ) {
                    cg.drawLinearGradient(
                        gradient, start: .zero,
                        end: CGPoint(x: size.width,
                                     y: size.height),
                        options: []
                    )
                }
            case .image, .video:
                let media = item.fillMode == .image ?
                    image(url: item.fillAssetURL) : videoFrame
                if let media {
                    let aspect = CGSize(
                        width: CGFloat(media.width),
                        height: CGFloat(media.height)
                    )
                    let fit = item.maskFit == .fit ?
                        min(size.width / aspect.width,
                            size.height / aspect.height) :
                        max(size.width / aspect.width,
                            size.height / aspect.height)
                    let zoom = CGFloat(min(4, max(0.5,
                                                item.maskScale)))
                    let drawn = CGSize(
                        width: aspect.width * fit * zoom,
                        height: aspect.height * fit * zoom
                    )
                    let dest = CGRect(
                        x: (size.width - drawn.width) / 2 +
                           CGFloat(item.maskOffsetX) *
                           size.width / 2,
                        y: (size.height - drawn.height) / 2 -
                           CGFloat(item.maskOffsetY) *
                           size.height / 2,
                        width: drawn.width, height: drawn.height
                    )
                    UIImage(cgImage: media).draw(in: dest)
                } else {
                    // A missing attachment is still a visible title,
                    // not a fully transparent video export.
                    TextOverlayRenderer.uiColor(
                        hex: item.colorHex
                    ).setFill()
                    UIRectFill(rect)
                }
            }

            // Destination-In retains the fill ONLY where the glyph alpha
            // is non-zero. In the old implementation, the Core Animation
            // layer-mask chain could export completely transparent.
            UIImage(cgImage: mask).draw(
                in: rect, blendMode: .destinationIn, alpha: 1
            )
        }
        return bitmap.cgImage
    }

    static func outlineImage(
        for item: TextOverlayClip, size: CGSize
    ) -> CGImage? {
        guard item.strokeWidth > 0,
              let mask = glyphMask(
                text: item.text, size: size,
                fontSize: CGFloat(min(180, max(15, item.fontSize))),
                strokeWidth: CGFloat(item.strokeWidth),
                outlineOnly: true,
                fontName: item.fontName,
                tracking: CGFloat(item.letterSpacing),
                curve: CGFloat(item.curveAmount)
              ) else { return nil }
        let size = safeSize(size)
        return UIGraphicsImageRenderer(
            size: size, format: rgbaFormat()
        ).image { _ in
            TextOverlayRenderer.uiColor(
                hex: item.strokeHex
            ).setFill()
            let rect = CGRect(origin: .zero, size: size)
            UIRectFill(rect)
            UIImage(cgImage: mask).draw(
                in: rect, blendMode: .destinationIn, alpha: 1
            )
        }.cgImage
    }

    static func contentLayer(
        for item: TextOverlayClip, bounds: CGRect,
        begin: Double, duration: Double,
        filmstrip: Filmstrip? = nil
    ) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero,
                              size: safeSize(bounds.size))
        layer.contentsGravity = .resize
        layer.contentsScale = 1
        let video = item.fillMode == .video ?
            (filmstrip ?? item.fillAssetURL.flatMap {
                load(url: $0)
            }) : nil
        layer.contents = rasterizedGlyph(
            for: item, size: layer.bounds.size,
            videoFrame: video?.first
        )

        if let video, video.frames.count > 1 {
            let animated = video.frames.compactMap {
                rasterizedGlyph(
                    for: item, size: layer.bounds.size,
                    videoFrame: $0
                )
            }
            if animated.count > 1 {
                let change = CAKeyframeAnimation(
                    keyPath: "contents"
                )
                change.values = animated
                change.calculationMode = .discrete
                change.beginTime =
                    AVCoreAnimationBeginTimeAtZero + begin
                change.duration = max(0.1, video.loopSeconds)
                change.repeatCount =
                    Float.greatestFiniteMagnitude
                change.isRemovedOnCompletion = false
                change.fillMode = .both
                layer.add(change, forKey: "text-video-fill")
            }
        }
        return layer
    }

    private static func safeSize(_ size: CGSize) -> CGSize {
        CGSize(width: CGFloat(max(1, Int(size.width))),
               height: CGFloat(max(1, Int(size.height))))
    }

    private static func rgbaFormat() -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return format
    }
}
