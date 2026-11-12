import Foundation
import UIKit
import CoreGraphics

/// Generates transparent, non-watermarked light and shadow artwork offline.
/// Geometry is deterministic for every effect ID; the animation engine moves
/// and blends these images without allocating new textures per video frame.
enum MockupProceduralTexture {
    private static let thumbnails = NSCache<NSString, UIImage>()
    private static let working = NSCache<NSString, UIImage>()

    static func artwork(
        id: String, preview: Bool = false
    ) -> UIImage? {
        guard let definition = MockupAssetLibrary.find(id) else {
            return nil
        }
        let cache = preview ? thumbnails : working
        let key = NSString(string: id)
        if let image = cache.object(forKey: key) { return image }
        cache.countLimit = preview ? 42 : 12
        let size = preview ? CGSize(width: 180, height: 270) :
            CGSize(width: 480, height: 720)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let bitmap = UIGraphicsImageRenderer(
            size: size, format: format
        ).image { renderer in
            let ctx = renderer.cgContext
            ctx.saveGState()
            ctx.scaleBy(x: size.width, y: size.height)
            switch definition.category {
            case .windows:
                window(ctx, variant: definition.variant)
            case .leaves:
                leaves(ctx, variant: definition.variant)
            case .flares:
                flare(ctx, variant: definition.variant)
            case .reflections:
                reflection(ctx, variant: definition.variant)
            case .atmosphere:
                atmosphere(ctx, variant: definition.variant)
            case .motion:
                switch definition.variant {
                case 0: leaves(ctx, variant: 2)
                case 1: flare(ctx, variant: 6)
                case 2: reflection(ctx, variant: 2)
                default: atmosphere(ctx, variant: 0)
                }
            }
            ctx.restoreGState()
        }
        cache.setObject(bitmap, forKey: key)
        return bitmap
    }

    /// Seeded synthetic randomness; reproducible when reopening projects.
    private struct Seeded {
        private var value: UInt64
        init(_ seed: UInt64) { value = seed &+ 42 }
        mutating func unit() -> CGFloat {
            value = value &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((value >> 35) % 1_000_000) / 1_000_000
        }
    }

    private static func fill(
        _ ctx: CGContext, _ rect: CGRect,
        color: UIColor, alpha: CGFloat
    ) {
        ctx.saveGState()
        ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
        ctx.fill(rect)
        ctx.restoreGState()
    }

    private static func radial(
        _ ctx: CGContext,
        at center: CGPoint, radius: CGFloat,
        color: UIColor, opacity: CGFloat
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlphaComponent(opacity).cgColor,
                color.withAlphaComponent(opacity * 0.32).cgColor,
                color.withAlphaComponent(0).cgColor
            ] as CFArray,
            locations: [0, 0.28, 1]
        ) else { return }
        ctx.drawRadialGradient(
            gradient,
            startCenter: center, startRadius: 0,
            endCenter: center, endRadius: radius,
            options: []
        )
    }

    private static func line(
        _ ctx: CGContext, from a: CGPoint, to b: CGPoint,
        width: CGFloat, color: UIColor, opacity: CGFloat
    ) {
        ctx.saveGState()
        ctx.setStrokeColor(
            color.withAlphaComponent(opacity).cgColor
        )
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: a)
        ctx.addLine(to: b)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func window(
        _ ctx: CGContext, variant: Int
    ) {
        let bright = variant == 4 || variant == 5 ||
            variant == 6
        if bright {
            let sun = UIColor(
                red: 1, green: variant == 6 ? 0.87 : 0.73,
                blue: 0.42, alpha: 1
            )
            radial(ctx, at: CGPoint(x: 0.12, y: 0.16),
                   radius: 0.94, color: sun, opacity: 0.52)
            for i in 0..<4 {
                line(
                    ctx,
                    from: CGPoint(x: -0.1 + CGFloat(i) * 0.12,
                                  y: -0.1),
                    to: CGPoint(x: 0.48 + CGFloat(i) * 0.18,
                                y: 1.25),
                    width: 0.085 + CGFloat(i % 2) * 0.04,
                    color: sun, opacity: 0.12
                )
            }
            return
        }
        ctx.saveGState()
        ctx.translateBy(x: 0.53, y: 0.51)
        ctx.rotate(by: CGFloat(variant - 3) * 0.09)
        ctx.translateBy(x: -0.53, y: -0.51)
        let shadow = UIColor.black
        let opacity: CGFloat = variant == 1 ? 0.66 : 0.46
        let beams = variant == 3 ? 9 : (variant == 2 ? 4 : 2)
        if variant == 7 {
            // Long right-hand side bars cast onto a wall.
            for i in 0..<4 {
                fill(ctx, CGRect(x: 0.49 + CGFloat(i) * 0.19,
                                 y: -0.2,
                                 width: 0.075, height: 1.4),
                     color: shadow, alpha: opacity)
            }
        } else if variant == 3 {
            for i in 0..<beams {
                fill(ctx, CGRect(x: -0.1, y: CGFloat(i) * 0.135,
                                 width: 1.3, height: 0.055),
                     color: shadow, alpha: opacity)
            }
        } else {
            for i in 0..<beams {
                fill(ctx, CGRect(x: 0.19 + CGFloat(i) * 0.33,
                                 y: -0.16, width: 0.065,
                                 height: 1.4),
                     color: shadow, alpha: opacity)
            }
            for i in 0..<3 {
                fill(ctx, CGRect(x: -0.20, y: 0.13 + CGFloat(i) * 0.36,
                                 width: 1.4, height: 0.06),
                     color: shadow, alpha: opacity)
            }
        }
        ctx.restoreGState()
    }

    private static func leaves(
        _ ctx: CGContext, variant: Int
    ) {
        var random = Seeded(UInt64(variant) * 113_311 + 12_399)
        let count = 17 + variant * 6
        let dark: CGFloat = variant == 1 ? 0.85 :
            (variant == 5 ? 0.25 : 0.63)
        let base = variant == 5 ?
            UIColor(red: 1, green: 0.90, blue: 0.55, alpha: 1) :
            UIColor.black
        let origin = CGPoint(
            x: variant.isMultiple(of: 2) ? -0.05 : 1.05,
            y: -0.12
        )
        for i in 0..<count {
            let reach = 0.18 + random.unit() * 1.1
            let theta = CGFloat.pi * (0.1 + random.unit() * 0.8)
            let x = origin.x + cos(theta) * reach *
                (origin.x < 0.5 ? 1 : -1)
            let y = origin.y + abs(sin(theta)) * reach
            let rotation = random.unit() * CGFloat.pi * 2
            let length = 0.035 + random.unit() * 0.14
            let breadth = 0.012 + random.unit() * 0.055
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: rotation)
            ctx.setFillColor(
                base.withAlphaComponent(
                    dark * (0.36 + random.unit() * 0.50)
                ).cgColor
            )
            let leaf = UIBezierPath()
            leaf.move(to: CGPoint(x: -length, y: 0))
            leaf.addQuadCurve(
                to: CGPoint(x: length, y: 0),
                control: CGPoint(x: 0, y: -breadth * 2)
            )
            leaf.addQuadCurve(
                to: CGPoint(x: -length, y: 0),
                control: CGPoint(x: 0, y: breadth * 2)
            )
            ctx.addPath(leaf.cgPath)
            ctx.fillPath()
            ctx.restoreGState()
            if i.isMultiple(of: 3) {
                line(ctx, from: origin, to: CGPoint(x: x, y: y),
                     width: 0.002 + CGFloat(variant % 3) * 0.001,
                     color: base, opacity: dark * 0.25)
            }
        }
    }

    private static func flare(
        _ ctx: CGContext, variant: Int
    ) {
        let fromRight = variant == 1 || variant == 6
        let center = CGPoint(x: fromRight ? 0.85 : 0.16,
                             y: variant == 3 ? 0.82 : 0.18)
        let warm = variant == 4 || variant == 2 || variant == 3
        let tint = UIColor(
            red: 1, green: warm ? 0.63 : 0.90,
            blue: warm ? 0.32 : 0.79, alpha: 1
        )
        radial(ctx, at: center, radius: 0.76,
               color: tint, opacity: 0.58)
        if variant == 7 {
            radial(ctx, at: CGPoint(x: 0.55, y: 0.44),
                   radius: 0.54, color: tint, opacity: 0.36)
        }
        for i in 0..<4 {
            line(ctx, from: CGPoint(
                x: center.x - CGFloat(i) * 0.03, y: -0.12
            ), to: CGPoint(
                x: center.x + (fromRight ? -1 : 1) *
                   (0.37 + CGFloat(i) * 0.09),
                y: 1.25
            ), width: variant == 6 ? 0.017 : 0.052,
               color: tint, opacity: 0.10)
        }
        if variant == 5 || variant == 6 {
            for i in 0..<5 {
                radial(ctx, at: CGPoint(
                    x: center.x + (fromRight ? -1 : 1) *
                        CGFloat(i) * 0.16,
                    y: center.y + CGFloat(i) * 0.14
                ), radius: 0.018 + CGFloat(i) * 0.012,
                   color: UIColor.white, opacity: 0.23)
            }
        }
    }

    private static func reflection(
        _ ctx: CGContext, variant: Int
    ) {
        let cool = variant == 4 || variant == 6
        let color = cool ?
            UIColor(red: 0.41, green: 0.84, blue: 1, alpha: 1) :
            UIColor(red: 1, green: 0.94, blue: 0.77, alpha: 1)
        if variant == 2 || variant == 3 || variant == 5 {
            radial(
                ctx,
                at: CGPoint(x: variant == 5 ? 0.34 : 0.75,
                            y: variant == 3 ? 0.25 : 0.52),
                radius: 0.8, color: color, opacity: 0.57
            )
        }
        ctx.saveGState()
        ctx.translateBy(x: 0.5, y: 0.5)
        ctx.rotate(by: CGFloat(variant - 3) * 0.12)
        ctx.translateBy(x: -0.5, y: -0.5)
        for i in 0..<5 {
            let dx = CGFloat(i) * 0.24
            line(ctx,
                 from: CGPoint(x: -0.3 + dx, y: -0.2),
                 to: CGPoint(x: 0.39 + dx, y: 1.23),
                 width: i.isMultiple(of: 2) ? 0.10 : 0.035,
                 color: color, opacity: CGFloat(0.07 + 0.02 * Double(i)))
        }
        ctx.restoreGState()
    }

    private static func atmosphere(
        _ ctx: CGContext, variant: Int
    ) {
        var random = Seeded(
            UInt64(variant) * 7_723 + 41_009
        )
        let color = variant == 4 ?
            UIColor(red: 0.84, green: 0.90, blue: 1, alpha: 1) :
            UIColor(red: 1, green: 0.90, blue: 0.66, alpha: 1)
        if variant >= 2 {
            radial(ctx, at: CGPoint(x: 0.50, y: 0.64),
                   radius: 0.83, color: color, opacity: 0.15)
            radial(ctx, at: CGPoint(x: 0.22, y: 0.18),
                   radius: 0.65, color: color, opacity: 0.12)
        }
        for _ in 0..<(variant == 0 ? 120 : 44 + variant * 11) {
            let x = random.unit(), y = random.unit()
            let r = (variant == 1 ? 0.02 : 0.003) +
                random.unit() * (variant == 1 ? 0.061 : 0.012)
            radial(ctx, at: CGPoint(x: x, y: y),
                   radius: r, color: color,
                   opacity: (variant == 1 ? 0.18 : 0.35) *
                       (0.45 + random.unit() * 0.55))
        }
    }
}
