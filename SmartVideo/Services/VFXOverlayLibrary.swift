import Foundation
import AVFoundation
import QuartzCore
import CoreGraphics
import UIKit

/// Built-in procedural VFX. No downloaded assets or third-party packs.
/// The selected layers are inserted into the SAME composition as subtitles,
/// so both effects and text are burned into the exported MP4.
enum VFXPreset: String, CaseIterable, Identifiable, Codable, Hashable {
    case grain = "Hạt phim"
    case vignette = "Viền tối"
    case lightLeak = "Lóa ánh sáng"
    case snow = "Tuyết rơi"
    case rain = "Mưa"
    case sparks = "Tia lửa"
    case dust = "Bụi ánh sáng"
    case flash = "Nháy sáng"
    case cinemaBars = "Viền điện ảnh"
    case bokeh = "Bokeh"
    case lightStreak = "Vệt sáng"
    case scanlines = "Scanline"
    case filmScratch = "Trầy phim"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .grain: return "camera.filters"
        case .vignette: return "circle.dotted.circle"
        case .lightLeak: return "sun.max.fill"
        case .snow: return "snowflake"
        case .rain: return "cloud.rain.fill"
        case .sparks: return "sparkles"
        case .dust: return "circle.hexagongrid"
        case .flash: return "bolt.fill"
        case .cinemaBars: return "rectangle.inset.filled"
        case .bokeh: return "circle.dotted"
        case .lightStreak: return "sun.horizon.fill"
        case .scanlines: return "line.3.horizontal"
        case .filmScratch: return "scribble.variable"
        }
    }

    var description: String {
        switch self {
        case .grain: return "Hạt nhiễu phim cổ điển"
        case .vignette: return "Tối nhẹ bốn góc"
        case .lightLeak: return "Dải ánh sáng ấm lướt qua"
        case .snow: return "Hạt tuyết chuyển động"
        case .rain: return "Vệt mưa trên khung hình"
        case .sparks: return "Tia sáng lấp lánh"
        case .dust: return "Bụi bay trong ánh sáng"
        case .flash: return "Chớp sáng theo nhịp"
        case .cinemaBars: return "Thanh đen trên và dưới"
        case .bokeh: return "Bokeh mềm nhiều độ sâu"
        case .lightStreak: return "Vệt sáng ngang"
        case .scanlines: return "Đường quét màn hình"
        case .filmScratch: return "Vết xước phim cổ điển"
        }
    }

    var tint: UIColor {
        switch self {
        case .grain, .vignette, .cinemaBars, .filmScratch, .scanlines: return .gray
        case .lightLeak: return .systemOrange
        case .snow: return .cyan
        case .rain: return .systemTeal
        case .sparks: return .systemYellow
        case .dust: return .systemMint
        case .flash: return .white
        case .bokeh: return .systemPink
        case .lightStreak: return .systemYellow
        }
    }
}

enum VFXOverlayLibrary {
    /// Add all VFX underneath subtitle layers, so subtitles remain readable.
    static func attach(
        presets: [VFXPreset],
        to parent: CALayer,
        canvas: CGSize,
        duration: Double,
        intensity: Double,
        effectBounds: CGRect,
        startTime: Double,
        endTime: Double
    ) {
        // VFX are clipped to visible footage, not the letterboxed bars.
        let strength = CGFloat(min(1, max(0.05, intensity)))
        guard duration.isFinite, duration > 0, !presets.isEmpty else { return }
        let bounds = effectBounds.intersection(CGRect(origin: .zero, size: canvas))
        guard bounds.width > 1, bounds.height > 1 else { return }
        let clipped = CALayer()
        clipped.frame = bounds
        clipped.masksToBounds = true
        parent.addSublayer(clipped)
        let activeStart = min(max(0, startTime), duration)
        let activeEnd = min(max(activeStart + 0.05, endTime), duration)
        if activeStart > 0.001 || activeEnd < duration - 0.001 {
            clipped.opacity = 0
            let visible = CAKeyframeAnimation(keyPath: "opacity")
            visible.values = [0, 0, 1, 1, 0]
            let begin = max(0, activeStart - 0.01)
            let finish = min(duration, activeEnd + 0.01)
            visible.keyTimes = [
                0,
                NSNumber(value: begin / duration),
                NSNumber(value: activeStart / duration),
                NSNumber(value: activeEnd / duration),
                NSNumber(value: finish / duration)
            ]
            visible.duration = duration
            visible.beginTime = AVCoreAnimationBeginTimeAtZero
            visible.isRemovedOnCompletion = false
            visible.fillMode = .both
            clipped.add(visible, forKey: "viepn-vfx-range")
        }
        let effectSize = bounds.size
        for effect in presets {
            switch effect {
            case .grain:
                addGrain(to: clipped, size: effectSize, strength: strength)
            case .vignette:
                addVignette(to: clipped, size: effectSize, strength: strength)
            case .lightLeak:
                addLightLeak(to: clipped, size: effectSize, strength: strength,
                             duration: duration)
            case .snow:
                addParticles(to: clipped, size: effectSize, strength: strength,
                             kind: .snow)
            case .rain:
                addParticles(to: clipped, size: canvas, strength: strength,
                             kind: .rain)
            case .sparks:
                addParticles(to: clipped, size: canvas, strength: strength,
                             kind: .sparks)
            case .dust:
                addParticles(to: clipped, size: canvas, strength: strength,
                             kind: .dust)
            case .flash:
                addFlash(to: clipped, size: effectSize, strength: strength,
                         duration: duration)
            case .cinemaBars:
                addCinemaBars(to: clipped, size: effectSize, strength: strength)
            case .bokeh:
                addBokeh(to: clipped, size: effectSize, strength: strength)
            case .lightStreak:
                addLightStreak(to: clipped, size: effectSize, strength: strength)
            case .scanlines:
                addScanlines(to: clipped, size: effectSize, strength: strength)
            case .filmScratch:
                addFilmScratches(to: clipped, size: effectSize, strength: strength)
            }
        }
    }

    private static func addVignette(to parent: CALayer, size: CGSize,
                                    strength: CGFloat) {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.frame = CGRect(origin: .zero, size: size)
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.05, y: 1.05)
        gradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.18 * strength).cgColor,
            UIColor.black.withAlphaComponent(0.42 * strength).cgColor
        ]
        gradient.locations = [0, 0.48, 1]
        parent.addSublayer(gradient)
    }

    private static func addCinemaBars(to parent: CALayer, size: CGSize,
                                      strength: CGFloat) {
        let height = size.height * (0.06 + 0.04 * strength)
        for y in [CGFloat(0), size.height - height] {
            let bar = CALayer()
            bar.frame = CGRect(x: 0, y: y, width: size.width, height: height)
            bar.backgroundColor = UIColor.black.cgColor
            parent.addSublayer(bar)
        }
    }

    private static func addLightLeak(to parent: CALayer, size: CGSize,
                                     strength: CGFloat, duration: Double) {
        // A soft radial alpha field is crucial. The previous linear gradient
        // had an opaque rectangular boundary that became very obvious over
        // footage with black bars.
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = CGRect(x: 0, y: -size.height * 0.3,
                            width: size.width * 1.2, height: size.height * 1.6)
        glow.startPoint = CGPoint(x: 0.36, y: 0.47)
        glow.endPoint = CGPoint(x: 0.92, y: 0.96)
        glow.colors = [
            UIColor(red: 1, green: 0.82, blue: 0.52,
                    alpha: 0.24 * strength).cgColor,
            UIColor(red: 1, green: 0.42, blue: 0.25,
                    alpha: 0.11 * strength).cgColor,
            UIColor.clear.cgColor
        ]
        glow.locations = [0, 0.40, 1]
        parent.addSublayer(glow)

        let sway = CABasicAnimation(keyPath: "position.x")
        sway.fromValue = size.width * 0.28
        sway.toValue = size.width * 0.72
        sway.duration = 5.5
        sway.autoreverses = true
        sway.repeatCount = Float.greatestFiniteMagnitude
        configureAnimation(sway)
        glow.add(sway, forKey: "viepn-light-leak-soft")
    }

    private static func addFlash(to parent: CALayer, size: CGSize,
                                 strength: CGFloat, duration: Double) {
        let flash = CALayer()
        flash.frame = CGRect(origin: .zero, size: size)
        flash.backgroundColor = UIColor.white.cgColor
        flash.opacity = 0
        parent.addSublayer(flash)

        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, 0, Float(0.44 * strength), 0, 0]
        pulse.keyTimes = [0, 0.45, 0.49, 0.53, 1]
        pulse.duration = min(6, max(1.5, duration))
        pulse.repeatCount = Float.greatestFiniteMagnitude
        configureAnimation(pulse)
        flash.add(pulse, forKey: "viepn-flash")
    }

    private static func addGrain(to parent: CALayer, size: CGSize,
                                 strength: CGFloat) {
        let noise = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
            .image { context in
                let cg = context.cgContext
                var state: UInt32 = 0x91DAF03
                for _ in 0..<1800 {
                    state = state &* 1664525 &+ 1013904223
                    let x = CGFloat(state % 256)
                    state = state &* 1664525 &+ 1013904223
                    let y = CGFloat(state % 256)
                    state = state &* 1664525 &+ 1013904223
                    let white = (state & 1) == 0
                    cg.setFillColor(
                        (white ? UIColor.white : UIColor.black)
                            .withAlphaComponent(0.20).cgColor
                    )
                    cg.fill(CGRect(x: x, y: y, width: 1.4, height: 1.4))
                }
            }
        guard let image = noise.cgImage else { return }
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contents = image
        layer.contentsGravity = .resize
        layer.opacity = Float(0.75 * strength)
        parent.addSublayer(layer)
        let flicker = CAKeyframeAnimation(keyPath: "opacity")
        flicker.values = [Float(0.3 * strength), Float(0.8 * strength),
                          Float(0.5 * strength), Float(0.7 * strength)]
        flicker.duration = 0.15
        flicker.repeatCount = Float.greatestFiniteMagnitude
        configureAnimation(flicker)
        layer.add(flicker, forKey: "viepn-grain")
    }

    private enum ParticleStyle { case snow, rain, sparks, dust }

    private static func addParticles(to parent: CALayer, size: CGSize,
                                     strength: CGFloat, kind: ParticleStyle) {
        let count: Int
        switch kind {
        case .snow: count = 45
        case .rain: count = 65
        case .sparks: count = 24
        case .dust: count = 32
        }
        var state: UInt32 = 0xD59B13
        func random() -> CGFloat {
            state = state &* 1664525 &+ 1013904223
            return CGFloat(state % 10000) / 10000
        }

        for index in 0..<count {
            let x = random() * size.width
            let sizeFactor = 0.5 + random()
            let dot = CALayer()
            let width: CGFloat
            let height: CGFloat
            let color: UIColor
            let motionDuration: CFTimeInterval
            let travel: CGFloat
            switch kind {
            case .snow:
                width = 3.8 * sizeFactor
                height = width
                color = .white
                motionDuration = 5 + Double(random()) * 8
                travel = size.height + 30
            case .rain:
                width = 1.8 * sizeFactor
                height = 18 * sizeFactor
                color = UIColor(red: 0.62, green: 0.81, blue: 1, alpha: 1)
                motionDuration = 0.8 + Double(random()) * 0.9
                travel = size.height + 80
            case .sparks:
                width = 3 * sizeFactor
                height = width
                color = .systemYellow
                motionDuration = 2 + Double(random()) * 3
                travel = -(size.height + 40)
            case .dust:
                width = 4 * sizeFactor
                height = width
                color = .white
                motionDuration = 6 + Double(random()) * 7
                travel = -(size.height * 0.6)
            }
            let startY = kind == .sparks || kind == .dust
                ? size.height + 20 : -40
            dot.frame = CGRect(x: x, y: startY, width: width, height: height)
            dot.cornerRadius = kind == .rain ? 0 : width / 2
            dot.backgroundColor = color.withAlphaComponent(
                (kind == .rain ? 0.24 : 0.43) * strength
            ).cgColor
            parent.addSublayer(dot)

            let velocity = CABasicAnimation(keyPath: "position")
            velocity.fromValue = NSValue(cgPoint: dot.position)
            let dx: CGFloat = kind == .rain ? -size.width * 0.07 :
                (random() - 0.5) * size.width * 0.18
            velocity.toValue = NSValue(cgPoint: CGPoint(
                x: dot.position.x + dx,
                y: dot.position.y + travel
            ))
            velocity.duration = motionDuration
            velocity.beginTime = AVCoreAnimationBeginTimeAtZero
                + Double(index) / Double(max(count, 1)) * motionDuration
            velocity.repeatCount = Float.greatestFiniteMagnitude
            velocity.isRemovedOnCompletion = false
            velocity.fillMode = .both
            dot.add(velocity, forKey: "viepn-particle-\(index)")
        }
    }

    private static func addBokeh(to parent: CALayer, size: CGSize,
                                 strength: CGFloat) {
        for index in 0..<18 {
            let factor = CGFloat((index * 37 + 19) % 97) / 97
            let diameter = CGFloat(13 + (index * 17) % 37)
            let dot = CALayer()
            dot.frame = CGRect(
                x: size.width * factor,
                y: size.height * CGFloat((index * 29 + 13) % 99) / 99,
                width: diameter, height: diameter
            )
            dot.cornerRadius = diameter / 2
            dot.borderWidth = max(1.2, diameter * 0.07)
            dot.borderColor = UIColor(
                hue: CGFloat(index % 6) / 24 + 0.09,
                saturation: 0.34, brightness: 1, alpha: 0.35 * strength
            ).cgColor
            dot.backgroundColor = UIColor.white.withAlphaComponent(0.05 * strength).cgColor
            dot.shadowColor = UIColor.systemOrange.cgColor
            dot.shadowOpacity = Float(0.12 * strength)
            dot.shadowRadius = 5
            parent.addSublayer(dot)
            let float = CABasicAnimation(keyPath: "position.y")
            float.fromValue = dot.position.y
            float.toValue = dot.position.y + size.height * 0.10
            float.duration = 3.5 + Double(index % 7)
            float.autoreverses = true
            float.repeatCount = Float.greatestFiniteMagnitude
            configureAnimation(float)
            dot.add(float, forKey: "viepn-bokeh")
        }
    }

    private static func addLightStreak(to parent: CALayer, size: CGSize,
                                       strength: CGFloat) {
        let streak = CAGradientLayer()
        streak.frame = CGRect(x: 0, y: size.height * 0.32,
                              width: size.width, height: max(2, size.height * 0.055))
        streak.startPoint = CGPoint(x: 0, y: 0.5)
        streak.endPoint = CGPoint(x: 1, y: 0.5)
        streak.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.05 * strength).cgColor,
            UIColor.cyan.withAlphaComponent(0.27 * strength).cgColor,
            UIColor.white.withAlphaComponent(0.12 * strength).cgColor,
            UIColor.clear.cgColor
        ]
        streak.locations = [0, 0.25, 0.5, 0.75, 1]
        parent.addSublayer(streak)
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = size.height * 0.15
        move.toValue = size.height * 0.82
        move.duration = 4.5
        move.autoreverses = true
        move.repeatCount = Float.greatestFiniteMagnitude
        configureAnimation(move)
        streak.add(move, forKey: "viepn-streak")
    }

    private static func addScanlines(to parent: CALayer, size: CGSize,
                                     strength: CGFloat) {
        let spacing = max(5, size.height / 135)
        var y: CGFloat = 0
        while y < size.height {
            let stripe = CALayer()
            stripe.frame = CGRect(x: 0, y: y, width: size.width, height: 1)
            stripe.backgroundColor = UIColor.black.withAlphaComponent(
                0.16 * strength
            ).cgColor
            parent.addSublayer(stripe)
            y += spacing
        }
    }

    private static func addFilmScratches(to parent: CALayer, size: CGSize,
                                         strength: CGFloat) {
        for index in 0..<4 {
            let line = CALayer()
            let x = size.width * CGFloat((index * 29 + 13) % 97) / 97
            line.frame = CGRect(x: x, y: 0, width: 1, height: size.height)
            line.backgroundColor = UIColor.white.withAlphaComponent(
                0.12 * strength
            ).cgColor
            line.opacity = 0
            parent.addSublayer(line)

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, Float(0.22 * strength), 0, 0]
            opacity.keyTimes = [0, 0.08, 0.15, 1]
            opacity.duration = 2.5 + Double(index) * 0.8
            opacity.repeatCount = Float.greatestFiniteMagnitude
            configureAnimation(opacity)
            line.add(opacity, forKey: "viepn-scratch")
        }
    }

    private static func configureAnimation(_ animation: CAAnimation) {
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
    }
}
