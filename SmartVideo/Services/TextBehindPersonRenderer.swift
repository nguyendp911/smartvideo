import Foundation
import UIKit
import CoreImage
import Vision

/// Text is painted BETWEEN the original background and the segmented
/// foreground person, in the actual source pixels before MP4 composition.
/// Vision is run on the original source; other non-person objects are not
/// separated (the UI labels the feature "Sau người", not "all objects").
enum TextBehindPersonRenderer {
    static func apply(
        to source: CIImage, items: [TextOverlayClip],
        projectTime: Double, maskSource: CIImage? = nil,
        maskOverride: CIImage? = nil,
        films: [UUID: TextMaskMedia.Filmstrip] = [:],
        quality: VNGeneratePersonSegmentationRequest.QualityLevel = .fast
    ) throws -> CIImage {
        guard projectTime.isFinite else { return source }
        let active = items.filter {
            $0.depthMode == .behindPerson &&
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            projectTime >= $0.start &&
            projectTime < $0.end &&
            $0.duration > 0.05
        }
        guard !active.isEmpty else { return source }
        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return source }

        let renderScale = min(1, 1080 / max(extent.width, extent.height))
        let canvas = CGSize(
            width: max(1, floor(extent.width * renderScale)),
            height: max(1, floor(extent.height * renderScale))
        )
        let renderer = UIGraphicsImageRenderer(size: canvas)
        let overlay = renderer.image { renderContext in
            let ctx = renderContext.cgContext
            for item in active {
                draw(
                    item, in: ctx, canvas: canvas,
                    localSecond: projectTime - item.start,
                    film: films[item.id]
                )
            }
        }
        guard let cg = overlay.cgImage else { return source }
        let overlayCI = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(
                scaleX: 1 / renderScale, y: 1 / renderScale
            ))
            .transformed(by: CGAffineTransform(
                translationX: extent.minX,
                y: extent.minY
            ))
            .cropped(to: extent)

        let under = overlayCI.composited(over: source)
        let mask = try maskOverride ?? PersonCutoutProcessor.personMask(
            maskSource ?? source, quality: quality
        )
        // The foreground person wins over the title in every generated frame.
        // Smooth mask edges are handled by Vision's alpha image.
        return source.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: under,
                kCIInputMaskImageKey: mask
            ]
        ).cropped(to: extent)
    }

    private static func draw(
        _ item: TextOverlayClip,
        in ctx: CGContext, canvas: CGSize,
        localSecond: Double,
        film: TextMaskMedia.Filmstrip?
    ) {
        let progress = min(1, max(0,
            localSecond / max(0.05, item.duration)))
        let frame = OverlayKeyframeSampler.sample(
            item, atProgress: progress
        )
        let ratio = min(4, max(0.5, Double(frame.scale) / 0.45))
        let pulse = item.pulseEnabled ?
            1 + 0.035 * sin(localSecond * .pi * 2 / 1.7) : 1
        let wide = canvas.width * 0.85
        let fontSize = CGFloat(min(160, max(15, item.fontSize))) *
            min(1, canvas.width / 720)
        let tall = min(canvas.height * 0.5, fontSize * 3.5)
        let bounds = CGRect(x: -wide / 2, y: -tall / 2,
                            width: wide, height: tall)
        let imageSize = bounds.insetBy(dx: 9, dy: 5).size
        guard imageSize.width > 0, imageSize.height > 0,
              let mask = TextMaskMedia.glyphMask(
                text: item.text, size: imageSize,
                fontSize: fontSize,
                strokeWidth: CGFloat(item.strokeWidth)
              ) else { return }

        ctx.saveGState()
        ctx.setAlpha(CGFloat(min(1, max(0, frame.opacity))))
        ctx.translateBy(x: CGFloat(frame.x) * canvas.width,
                        y: CGFloat(frame.y) * canvas.height)
        ctx.rotate(by: CGFloat(frame.rotationDegrees) * .pi / 180)
        ctx.scaleBy(x: ratio * pulse, y: ratio * pulse)

        if item.useBackground {
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.38).cgColor)
            let path = UIBezierPath(
                roundedRect: bounds, cornerRadius: fontSize * 0.17
            )
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }

        let region = CGRect(
            x: -imageSize.width / 2,
            y: -imageSize.height / 2,
            width: imageSize.width, height: imageSize.height
        )
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // UIKit-oriented glyph alpha; sourceIn paints inside the letters.
        UIImage(cgImage: mask).draw(in: region)
        ctx.setBlendMode(.sourceIn)
        switch item.fillMode {
        case .solid:
            ctx.setFillColor(TextOverlayRenderer.uiColor(
                hex: item.colorHex
            ).cgColor)
            ctx.fill(region)
        case .gradient:
            let colors = [
                TextOverlayRenderer.uiColor(hex: item.colorHex).cgColor,
                TextOverlayRenderer.uiColor(
                    hex: item.gradientEndHex
                ).cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(
                colorsSpace: space, colors: colors,
                locations: [0, 1]
            ) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: region.minX, y: region.minY),
                    end: CGPoint(x: region.maxX, y: region.maxY),
                    options: []
                )
            }
        case .image, .video:
            let picture: CGImage? = item.fillMode == .image ?
                TextMaskMedia.image(url: item.fillAssetURL) :
                film?.frame(at: localSecond)
            if let picture {
                let sourceAspect = CGFloat(picture.width) /
                    CGFloat(max(1, picture.height))
                let targetAspect = region.width /
                    max(1, region.height)
                let factor = item.maskFit == .fit ?
                    (sourceAspect > targetAspect ?
                        region.width / CGFloat(picture.width) :
                        region.height / CGFloat(picture.height)) :
                    (sourceAspect > targetAspect ?
                        region.height / CGFloat(picture.height) :
                        region.width / CGFloat(picture.width))
                let scale = factor * CGFloat(min(4, max(0.5,
                    item.maskScale)))
                let size = CGSize(
                    width: CGFloat(picture.width) * scale,
                    height: CGFloat(picture.height) * scale
                )
                let photoRect = CGRect(
                    x: region.midX - size.width / 2 +
                       CGFloat(item.maskOffsetX) * region.width * 0.5,
                    y: region.midY - size.height / 2 +
                       CGFloat(item.maskOffsetY) * region.height * 0.5,
                    width: size.width, height: size.height
                )
                UIImage(cgImage: picture).draw(in: photoRect)
            } else {
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(region)
            }
        }
        ctx.endTransparencyLayer()

        // Draw a separate colorable outer stroke, rather than merely
        // widening the image glyph alpha. The stroke is also behind Vision's
        // foreground person because it participates in this scene layer.
        if item.strokeWidth > 0,
           let edge = TextMaskMedia.glyphMask(
                text: item.text, size: imageSize,
                fontSize: fontSize,
                strokeWidth: CGFloat(item.strokeWidth),
                outlineOnly: true
           ) {
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            UIImage(cgImage: edge).draw(in: region)
            ctx.setBlendMode(.sourceIn)
            ctx.setFillColor(TextOverlayRenderer.uiColor(
                hex: item.strokeHex
            ).cgColor)
            ctx.fill(region)
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()
    }
}
