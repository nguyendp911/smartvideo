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
        }
    }

    var tint: UIColor {
        switch self {
        case .grain, .vignette, .cinemaBars: return .gray
        case .lightLeak: return .systemOrange
        case .snow: return .cyan
        case .rain: return .systemTeal
        case .sparks: return .systemYellow
        case .dust: return .systemMint
        case .flash: return .white
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
        intensity: Double
    ) {
        let strength = CGFloat(min(1, max(0.05, intensity)))
        guard duration.isFinite, duration > 0 else { return }
        let clipped = CALayer()
        clipped.frame = CGRect(origin: .zero, size: canvas)
        clipped.masksToBounds = true
        parent.addSublayer(clipped)
        for effect in presets {
            switch effect {
            case .grain:
                addGrain(to: clipped, size: canvas, strength: strength)
            case .vignette:
                addVignette(to: clipped, size: canvas, strength: strength)
            case .lightLeak:
                addLightLeak(to: clipped, size: canvas, strength: strength,
                             duration: duration)
            case .snow:
                addParticles(to: clipped, size: canvas, strength: strength,
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
                addFlash(to: clipped, size: canvas, strength: strength,
                         duration: duration)
            case .cinemaBars:
                addCinemaBars(to: clipped, size: canvas, strength: strength)
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
            UIColor.black.withAlphaComponent(0.85 * strength).cgColor
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
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: -size.width * 0.7, y: 0,
                                width: size.width * 1.5, height: size.height)
        gradient.startPoint = CGPoint(x: 0, y: 0.2)
        gradient.endPoint = CGPoint(x: 1, y: 0.85)
        gradient.colors = [
            UIColor.systemRed.withAlphaComponent(0.46 * strength).cgColor,
            UIColor.systemOrange.withAlphaComponent(0.22 * strength).cgColor,
            UIColor.clear.cgColor
        ]
        gradient.locations = [0, 0.55, 1]
        parent.addSublayer(gradient)

        let motion = CABasicAnimation(keyPath: "position.x")
        motion.fromValue = -size.width * 0.2
        motion.toValue = size.width * 1.4
        motion.duration = min(12, max(2.5, duration))
        motion.autoreverses = true
        motion.repeatCount = Float.greatestFiniteMagnitude
        configureAnimation(motion)
        gradient.add(motion, forKey: "viepn-light-leak")
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
                (kind == .rain ? 0.35 : 0.65) * strength
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

    private static func configureAnimation(_ animation: CAAnimation) {
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
    }
}
