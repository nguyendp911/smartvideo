import Foundation
import UIKit
import CoreImage
import Vision

/// Procedural, asset-free film-light renderer. One cached transparent texture
/// per design; motion/blur/blend/occlusion are applied on each export frame.
/// No network, Core Animation timings, or paid PNG/MOV dependencies.
enum MockupOverlayRenderer {
    private static let textureCache = NSCache<NSString, UIImage>()
    private static let outputSize = CGSize(width: 1280, height: 1280)
    // Bound memory even with 42 available designs (6.5 MB each at 1280²).
    private static let cacheLimit: Void = {
        textureCache.countLimit = 6
        textureCache.totalCostLimit = 48 * 1024 * 1024
    }()

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
            // Feather is expressed in normalized 0–1 softness and shared
            // by the still/video export path.
            let blur = min(45, max(0, clip.blurRadius +
                clip.feather * 24))
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
        let _ = cacheLimit
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
        textureCache.setObject(result, forKey: key,
                               cost: Int(outputSize.width * outputSize.height * 4))
        return result
    }

    /// Window casting with perspective, irregular penumbra, and curtain folds.
    /// Texture alpha remains separate from the user's opacity/blend controls.
    private static func drawWindow(
        _ ctx: CGContext, style: Int, tint: UIColor,
        width w: CGFloat, height h: CGFloat
    ) {
        let blinds = style == 3
        let count = blinds ? 12 : (style == 2 ? 6 : 4)
        let thickness = (style == 1 ? 0.047 : 0.023) * w
        let mainTint = tint.withAlphaComponent(style == 0 ? 0.55 : 0.79)
        ctx.setFillColor(mainTint.cgColor)
        for index in 0..<count {
            let p = CGFloat(index) / CGFloat(count)
            let shadow = UIBezierPath()
            if blinds {
                let y = (p + 0.05) * h
                let skew = w * (0.035 + CGFloat(style % 3) * 0.012)
                shadow.move(to: CGPoint(x: -w * 0.1, y: y))
                shadow.addLine(to: CGPoint(x: w * 1.1, y: y + skew))
                shadow.addLine(to: CGPoint(x: w * 1.1, y: y + skew + thickness * 0.75))
                shadow.addLine(to: CGPoint(x: -w * 0.1, y: y + thickness))
            } else {
                let x = (p + 0.08) * w
                let perspective = (CGFloat(index) - CGFloat(count) / 2) * w * 0.037
                shadow.move(to: CGPoint(x: x - perspective, y: -h * 0.13))
                shadow.addLine(to: CGPoint(x: x + thickness - perspective, y: -h * 0.13))
                shadow.addLine(to: CGPoint(x: x + thickness + perspective, y: h * 1.14))
                shadow.addLine(to: CGPoint(x: x + perspective, y: h * 1.14))
            }
            shadow.close()
            ctx.addPath(shadow.cgPath)
            ctx.fillPath()
        }
        if !blinds {
            for row in [0.28, 0.68] {
                let bar = UIBezierPath()
                let y = h * row
                bar.move(to: CGPoint(x: -w * 0.2, y: y - thickness))
                bar.addLine(to: CGPoint(x: w * 1.2, y: y + h * 0.07))
                bar.addLine(to: CGPoint(x: w * 1.2, y: y + h * 0.07 + thickness))
                bar.addLine(to: CGPoint(x: -w * 0.2, y: y))
                bar.close()
                ctx.addPath(bar.cgPath)
                ctx.fillPath()
            }
        }
        if style == 4 || style == 5 || style == 6 {
            // Broad, translucent light spill instead of opaque white streaks.
            drawLight(ctx, style: style, tint: .white,
                      width: w, height: h)
            if style == 4 {
                for fold in 0..<8 {
                    let x = CGFloat(fold) * w / 7
                    let foldPath = UIBezierPath()
                    foldPath.move(to: CGPoint(x: x, y: -h * 0.1))
                    foldPath.addCurve(
                        to: CGPoint(x: x + w * 0.09, y: h * 1.1),
                        controlPoint1: CGPoint(x: x + w * 0.085, y: h * 0.24),
                        controlPoint2: CGPoint(x: x - w * 0.035, y: h * 0.78)
                    )
                    ctx.setStrokeColor(tint.withAlphaComponent(0.2).cgColor)
                    ctx.setLineWidth(w * 0.016)
                    ctx.addPath(foldPath.cgPath)
                    ctx.strokePath()
                }
            }
        }
    }

    /// Organic, tapered foliage silhouettes. Deterministic curved stems and
    /// asymmetric pointed leaves avoid the repeated oval/stick appearance.
    private static func drawLeaves(
        _ ctx: CGContext, style: Int, tint: UIColor,
        width w: CGFloat, height h: CGFloat
    ) {
        var seed = UInt64(1000 + style * 2317)
        func random() -> CGFloat {
            seed = seed &* 2862933555777941757 &+ 3037000493
            return CGFloat((seed >> 32) % 10000) / 10000
        }
        let density = style == 1 ? 11 : (style == 3 ? 5 : 8)
        let organicTint = tint.withAlphaComponent(style == 5 ? 0.63 : 0.82)
        for branchIndex in 0..<density {
            let origin = CGPoint(x: (random() * 1.3 - 0.15) * w,
                                 y: (random() * 1.2 - 0.1) * h)
            let length = h * (0.25 + random() * 0.43)
            let bend = w * (random() - 0.5) * 0.55
            let end = CGPoint(x: origin.x + bend, y: origin.y + length)
            let control = CGPoint(x: origin.x + bend * 0.12,
                                  y: origin.y + length * 0.62)
            let path = UIBezierPath()
            path.move(to: origin)
            path.addQuadCurve(to: end, controlPoint: control)
            ctx.addPath(path.cgPath)
            ctx.setStrokeColor(organicTint.cgColor)
            ctx.setLineWidth((style == 3 ? 4.8 : 2.6) * w / 640)
            ctx.setLineCap(.round)
            ctx.strokePath()

            let leafCount = style == 4 ? 12 : (style == 7 ? 10 : 7)
            for leafIndex in 0..<leafCount {
                let t = (CGFloat(leafIndex) + 0.5) / CGFloat(leafCount)
                let inv = 1 - t
                let center = CGPoint(
                    x: inv * inv * origin.x + 2 * inv * t * control.x + t * t * end.x,
                    y: inv * inv * origin.y + 2 * inv * t * control.y + t * t * end.y
                )
                let side: CGFloat = leafIndex % 2 == 0 ? 1 : -1
                let jitter = 0.73 + random() * 0.65
                let blade = w * (style == 4 ? 0.09 : 0.047) * jitter
                let width = blade * (0.26 + random() * 0.17)
                let angle = side * (0.56 + random() * 0.7)
                ctx.saveGState()
                ctx.translateBy(x: center.x, y: center.y)
                ctx.rotate(by: angle)
                let leaf = UIBezierPath()
                leaf.move(to: .zero)
                leaf.addCurve(to: CGPoint(x: blade * 0.12, y: blade),
                              controlPoint1: CGPoint(x: -width * 1.1, y: blade * 0.24),
                              controlPoint2: CGPoint(x: -width * 0.65, y: blade * 0.76))
                leaf.addCurve(to: .zero,
                              controlPoint1: CGPoint(x: width * 1.4, y: blade * 0.79),
                              controlPoint2: CGPoint(x: width * 0.85, y: blade * 0.19))
                ctx.setFillColor(organicTint.withAlphaComponent(
                    0.64 + random() * 0.28).cgColor)
                ctx.addPath(leaf.cgPath)
                ctx.fillPath()
                ctx.restoreGState()
            }
            // Thin offshoots make nearby leaves read as a branch, not a stamp.
            if branchIndex % 2 == 0 {
                let tip = CGPoint(x: end.x + bend * 0.28, y: end.y + length * 0.1)
                ctx.move(to: end)
                ctx.addLine(to: tip)
                ctx.setLineWidth(1.4 * w / 640)
                ctx.strokePath()
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
