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
        // Critical: the output Core Image coordinates are in physical
        // pixels. UIGraphicsImageRenderer defaults to 2x/3x on iPhone,
        // causing the subsequently cropped overlay to miss all glyphs.
        // A 320x480 video frame MUST produce a 320x480 CGImage.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: canvas, format: format
        )
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
        var renderedTitle = item
        let baseFont = CGFloat(min(160, max(15, item.fontSize))) *
            min(1, canvas.width / 720)
        var fontSize = baseFont
        if item.behindVisibilityAssist {
            // If the title is narrow and centered on a person, Vision
            // correctly occludes ALL glyphs. Widen behind-person lettering
            // toward the canvas edges so letters can remain visible on
            // either side, without painting over the foreground person.
            // User can disable this option to preserve exact typography.
            let estimate = (item.text as NSString).size(
                withAttributes: [
                    .font: UIFont.systemFont(
                        ofSize: max(1, baseFont),
                        weight: .black
                    )
                ]
            ).width
            let desiredWidth = canvas.width * 0.72
            let enlargement = min(6, max(1, desiredWidth /
                                           max(1, estimate)))
            fontSize = min(180, canvas.height * 0.21,
                           baseFont * enlargement)
            renderedTitle.fontSize = Double(fontSize)
        }
        let tall = min(canvas.height * 0.5, fontSize * 3.5)
        let bounds = CGRect(x: -wide / 2, y: -tall / 2,
                            width: wide, height: tall)
        let imageSize = bounds.insetBy(dx: 9, dy: 5).size
        guard imageSize.width > 0,
              imageSize.height > 0 else { return }

        let image = TextMaskMedia.rasterizedGlyph(
            for: renderedTitle, size: imageSize,
            videoFrame: item.fillMode == .video ?
                film?.frame(at: localSecond) : nil
        )
        guard let image else { return }

        ctx.saveGState()
        ctx.setAlpha(CGFloat(
            min(1, max(0, frame.opacity))
        ))
        ctx.translateBy(
            x: CGFloat(frame.x) * canvas.width,
            y: CGFloat(frame.y) * canvas.height
        )
        ctx.rotate(by:
            CGFloat(frame.rotationDegrees) * .pi / 180
        )
        ctx.scaleBy(
            x: ratio * pulse, y: ratio * pulse
        )

        if item.useBackground {
            ctx.setFillColor(
                UIColor.black.withAlphaComponent(0.38).cgColor
            )
            let path = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: fontSize * 0.17
            )
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }

        let region = CGRect(
            x: -imageSize.width / 2,
            y: -imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        // Pre-rasterized glyph bitmap contains real nonzero RGBA pixels.
        // The previous nested source-in transparency blend could silently
        // produce a completely transparent title during video rendering.
        if item.fauxDepth > 0 {
            var shadowItem = renderedTitle
            shadowItem.fillMode = .solid
            shadowItem.colorHex = "242424"
            if let depth = TextMaskMedia.rasterizedGlyph(
                for: shadowItem, size: imageSize
            ) {
                let shifted = region.offsetBy(
                    dx: CGFloat(item.fauxDepth),
                    dy: CGFloat(item.fauxDepth)
                )
                UIImage(cgImage: depth).draw(in: shifted)
            }
        }
        if item.shadowOpacity > 0 {
            ctx.setShadow(
                offset: CGSize(width: 1.5, height: 2),
                blur: CGFloat(min(20, max(0, item.glowRadius))),
                color: UIColor.black.withAlphaComponent(
                    CGFloat(min(1, max(0, item.shadowOpacity)))
                ).cgColor
            )
        }
        UIImage(cgImage: image).draw(in: region)
        ctx.setShadow(
            offset: .zero, blur: 0, color: nil
        )

        if let outline = TextMaskMedia.outlineImage(
            for: renderedTitle, size: imageSize
        ) {
            UIImage(cgImage: outline).draw(in: region)
        }
        ctx.restoreGState()
    }
}
