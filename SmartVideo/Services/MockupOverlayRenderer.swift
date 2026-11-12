import Foundation
import UIKit
import CoreImage
import Vision

/// Procedural, asset-free film-light renderer. One cached transparent texture
/// per design; motion/blur/blend/occlusion are applied on each export frame.
/// No network, Core Animation timings, or paid PNG/MOV dependencies.
enum MockupOverlayRenderer {
    private static let textureCache = NSCache<NSString, UIImage>()
    private static let outputSize = CGSize(width: 640, height: 640)
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func apply(_ source: CIImage, overlays: [MockupOverlayClip],
                      second: Double, depth: MockupDepthMode,
                      personMask: CIImage? = nil) throws -> CIImage {
        let active = overlays.prefix(12).filter {
            $0.depthMode == depth &&
                MockupAnimationSampler.active($0, at: second) &&
                MockupAssetLibrary.asset($0.assetID) != nil
        }
        guard !active.isEmpty else { return source }
        let ext = source.extent
        guard ext.width > 0, ext.height > 0 else { return source }
        let mask: CIImage?
        if depth == .behindPerson {
            mask = try personMask ?? PersonCutoutProcessor.personMask(
                source, quality: .fast
            )
        } else { mask = nil }

        var composite = source
        for clip in active {
            guard let asset = MockupAssetLibrary.asset(clip.assetID),
                  let texture = texture(for: asset).cgImage
            else { continue }
            let state = MockupAnimationSampler.sample(clip, at: second)
            let base = CIImage(cgImage: texture)
            let effectiveScale = max(ext.width, ext.height) /
                CGFloat(texture.width) * CGFloat(state.scale)
            var transform = CGAffineTransform(
                translationX: -CGFloat(texture.width) / 2,
                y: -CGFloat(texture.height) / 2
            )
            transform = transform.scaledBy(
                x: clip.flipHorizontal ? -effectiveScale : effectiveScale,
                y: clip.flipVertical ? -effectiveScale : effectiveScale
            )
            transform = transform.rotated(
                by: CGFloat(state.rotation) * .pi / 180
            )
            transform = transform.translatedBy(
                x: (ext.minX + ext.width * CGFloat(state.x)) /
                    max(0.001, effectiveScale),
                y: (ext.minY + ext.height * (1 - CGFloat(state.y))) /
                    max(0.001, effectiveScale)
            )
            // Compose with center-position transform in world coordinates.
            let center = CGAffineTransform(
                translationX: ext.minX + ext.width * CGFloat(state.x),
                y: ext.minY + ext.height * (1 - CGFloat(state.y))
            )
            let rotate = CGAffineTransform(
                rotationAngle: CGFloat(state.rotation) * .pi / 180
            )
            let scaled = CGAffineTransform(
                scaleX: (clip.flipHorizontal ? -1 : 1) * effectiveScale,
                y: (clip.flipVertical ? -1 : 1) * effectiveScale
            )
            let origin = CGAffineTransform(
                translationX: -CGFloat(texture.width) / 2,
                y: -CGFloat(texture.height) / 2
            )
            var transformed = base.transformed(
                by: origin.concatenating(scaled)
                    .concatenating(rotate)
                    .concatenating(center)
            )
            let blur = min(45, max(0, clip.blurRadius))
            if blur > 0.01 {
                transformed = transformed.applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: blur]
                )
            }
            let alpha = CGFloat(min(1, max(0, state.opacity)))
            let brightness = min(0.8, max(-0.8, clip.brightness))
            let contrast = min(2, max(0.5, clip.contrast))
            transformed = transformed.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: brightness,
                    kCIInputContrastKey: contrast
                ]
            )
            if clip.warmth != 0 {
                let warm = min(0.6, max(-0.6, clip.warmth))
                transformed = transformed.applyingFilter(
                    "CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 1 + warm * 0.25,
                                                 y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: 1,
                                                 z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0,
                                                 z: 1 - warm * 0.28, w: 0)
                    ]
                )
            }
            transformed = transformed.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0,
                                              w: alpha)
                ]
            ).cropped(to: ext)

            // Clip against the person foreground, not against the entire
            // video. A white subject mask means light/shadow is occluded.
            if let mask {
                let empty = CIImage(
                    color: CIColor.clear
                ).cropped(to: ext)
                transformed = transformed.applyingFilter(
                    "CIBlendWithMask",
                    parameters: [
                        kCIInputBackgroundImageKey: transformed,
                        kCIInputImageKey: empty,
                        kCIInputMaskImageKey: mask
                    ]
                ).cropped(to: ext)
            }

            // Applying a blend directly to a transparent overlay is
            // compatible with Core Image premultiplied alpha.
            let filter: String
            switch clip.blendMode {
            case .normal: filter = "CISourceOverCompositing"
            case .multiply: filter = "CIMultiplyBlendMode"
            case .screen: filter = "CIScreenBlendMode"
            case .overlay: filter = "CIOverlayBlendMode"
            case .softLight: filter = "CISoftLightBlendMode"
            case .hardLight: filter = "CIHardLightBlendMode"
            case .add: filter = "CIAdditionCompositing"
            case .darken: filter = "CIDarkenBlendMode"
            case .lighten: filter = "CILightenBlendMode"
            }
            composite = transformed.applyingFilter(
                filter, parameters: [
                    kCIInputBackgroundImageKey: composite
                ]
            ).cropped(to: ext)
        }
        return composite
    }

    static func texture(for asset: MockupAsset) -> UIImage {
        let key = asset.id as NSString
        if let hit = textureCache.object(forKey: key) {
            return hit
        }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let result = UIGraphicsImageRenderer(
            size: outputSize, format: fmt
        ).image { info in
            let ctx = info.cgContext
            let w = outputSize.width, h = outputSize.height
            let tint: UIColor
            switch asset.category {
            case .window, .leaf:
                tint = UIColor(red: 0.07, green: 0.08,
                               blue: 0.09, alpha: 0.85)
            case .flare, .motion:
                tint = UIColor(red: 1, green: 0.83,
                               blue: 0.57, alpha: 0.78)
            case .reflection:
                tint = UIColor(red: 0.83, green: 0.92,
                               blue: 1, alpha: 0.62)
            case .atmosphere:
                tint = UIColor(red: 1, green: 0.94,
                               blue: 0.79, alpha: 0.48)
            }
            let style = asset.style
            // Unique angle/count/position per named asset; no downloaded
            // imagery, placeholder thumbnails or repetitive one-pixel masks.
            let angle = CGFloat((style % 7) * 7 - 22) * .pi / 180
            ctx.saveGState()
            ctx.translateBy(x: w / 2, y: h / 2)
            ctx.rotate(by: angle)
            ctx.translateBy(x: -w / 2, y: -h / 2)
            switch asset.category {
            case .window:
                drawWindow(ctx, style: style, tint: tint,
                           width: w, height: h)
            case .leaf:
                drawLeaves(ctx, style: style, tint: tint,
                           width: w, height: h)
            case .flare:
                drawLight(ctx, style: style, tint: tint,
                          width: w, height: h)
            case .reflection:
                drawReflection(ctx, style: style,
                               width: w, height: h)
            case .atmosphere:
                drawAtmosphere(ctx, style: style,
                               width: w, height: h)
            case .motion:
                if style == 0 {
                    drawLeaves(ctx, style: 2, tint: tint,
                               width: w, height: h)
                } else if style == 3 {
                    drawAtmosphere(ctx, style: 0,
                                   width: w, height: h)
                } else {
                    drawLight(ctx, style: style + 1,
                              tint: tint, width: w, height: h)
                }
            }
            ctx.restoreGState()
        }
        textureCache.setObject(result, forKey: key)
        return result
    }

    private static func drawWindow(
        _ ctx: CGContext, style: Int, tint: UIColor,
        width w: CGFloat, height h: CGFloat
    ) {
        ctx.setFillColor(tint.cgColor)
        let bars = style == 3 ? 11 : style == 2 ? 6 : 4
        let thickness: CGFloat = style == 1 ? 27 : 15
        for index in 0..<bars {
            let x = CGFloat(index) * w / CGFloat(bars) + w * 0.08
            if style == 3 {
                ctx.fill(CGRect(x: 0,
                                y: CGFloat(index) * h / CGFloat(bars),
                                width: w,
                                height: thickness))
            } else {
                ctx.fill(CGRect(x: x, y: -h * 0.2,
                                width: thickness, height: h * 1.5))
            }
        }
        if style != 3 {
            ctx.fill(CGRect(x: 0, y: h * 0.27,
                            width: w, height: thickness * 1.1))
            ctx.fill(CGRect(x: 0, y: h * 0.69,
                            width: w, height: thickness * 1.15))
        }
        if style == 4 || style == 5 || style == 6 {
            drawLight(ctx, style: style, tint: .white,
                      width: w, height: h)
        }
    }

    private static func drawLeaves(
        _ ctx: CGContext, style: Int, tint: UIColor,
        width w: CGFloat, height h: CGFloat
    ) {
        var seed = UInt64(1000 + style * 2317)
        func random() -> CGFloat {
            seed = seed &* 2862933555777941757 &+ 3037000493
            return CGFloat((seed >> 32) % 10000) / 10000
        }
        ctx.setStrokeColor(tint.cgColor)
        ctx.setLineWidth(style == 3 ? 10 : 5)
        let branches = style == 1 ? 10 : 6
        for _ in 0..<branches {
            let x = random() * w
            let y = random() * h
            let end = CGPoint(x: x + (random() - 0.5) * 200,
                              y: y + 140)
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: end)
            ctx.strokePath()
            for leaf in 0..<7 {
                let p = CGFloat(leaf) / 7
                let lx = x + (end.x - x) * p
                let ly = y + (end.y - y) * p
                let length = 23 + random() * (style == 4 ? 65 : 38)
                ctx.saveGState()
                ctx.translateBy(x: lx, y: ly)
                ctx.rotate(by: (random() - 0.5) * 3)
                let path = UIBezierPath(ovalIn:
                    CGRect(x: -length * 0.25, y: 0,
                           width: length * 0.5, height: length))
                ctx.setFillColor(tint.cgColor)
                ctx.addPath(path.cgPath)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }

    private static func drawLight(
        _ ctx: CGContext, style: Int, tint: UIColor,
        width w: CGFloat, height h: CGFloat
    ) {
        let center = CGPoint(
            x: style == 1 ? w * 0.85 : w * (style == 3 ? 0.5 : 0.18),
            y: style == 4 ? h * 0.7 : h * 0.78
        )
        let colors = [
            UIColor(red: 1, green: style == 3 ? 0.52 : 0.86,
                    blue: 0.52, alpha: 0.92).cgColor,
            UIColor(red: 1, green: 0.77,
                    blue: 0.38, alpha: 0.18).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors, locations: [0, 0.32, 1]
        ) {
            ctx.drawRadialGradient(
                gradient, startCenter: center,
                startRadius: 0, endCenter: center,
                endRadius: (style == 6 ? 230 : 380),
                options: [.drawsAfterEndLocation]
            )
        }
        for index in 0..<(style == 7 ? 9 : 4) {
            let p = CGFloat(index)
            ctx.setStrokeColor(
                UIColor(red: 1, green: 0.9,
                        blue: 0.72, alpha: 0.08).cgColor
            )
            ctx.setLineWidth(10 + 5 * p)
            ctx.move(to: center)
            ctx.addLine(to: CGPoint(
                x: center.x + cos(p * 1.43) * w,
                y: center.y + sin(p * 1.43) * h
            ))
            ctx.strokePath()
        }
    }

    private static func drawReflection(
        _ ctx: CGContext, style: Int,
        width w: CGFloat, height h: CGFloat
    ) {
        let colors = [
            UIColor.white.withAlphaComponent(
                style == 4 ? 0.9 : 0.55
            ).cgColor,
            UIColor(red: style == 4 ? 0.45 : 0.81,
                    green: 0.8, blue: 1, alpha: 0.18).cgColor,
            UIColor.clear.cgColor
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors, locations: [0, 0.45, 1]
        ) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: w * 0.14, y: 0),
                end: CGPoint(x: w * 0.8, y: h),
                options: [.drawsBeforeStartLocation]
            )
        }
        if style % 2 == 0 {
            ctx.setFillColor(
                UIColor.white.withAlphaComponent(0.12).cgColor
            )
            ctx.fill(CGRect(x: w * 0.29, y: 0,
                            width: w * 0.045, height: h))
        }
    }

    private static func drawAtmosphere(
        _ ctx: CGContext, style: Int,
        width w: CGFloat, height h: CGFloat
    ) {
        var seed = UInt64(42 + style * 8167)
        func random() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1
            return CGFloat((seed >> 33) % 10000) / 10000
        }
        let count = style == 0 ? 120 :
            style == 1 ? 38 : 60
        for _ in 0..<count {
            let x = random() * w, y = random() * h
            let radius = style == 0 ? 1 + random() * 5 :
                style == 1 ? 7 + random() * 24 :
                14 + random() * 40
            let alpha = style == 0 ? 0.38 : 0.08
            ctx.setFillColor(
                UIColor(red: 1, green: 0.91,
                        blue: 0.73, alpha: alpha).cgColor
            )
            ctx.fillEllipse(in:
                CGRect(x: x, y: y, width: radius,
                       height: radius))
        }
    }
}
