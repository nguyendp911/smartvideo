import Foundation
import QuartzCore
import AVFoundation
import UIKit

enum TextOverlayRenderer {
    static func attach(_ overlays: [TextOverlayClip], to parent: CALayer,
                       canvas: CGSize, duration: Double) {
        guard duration.isFinite && duration > 0 else { return }
        for item in overlays where !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let begin = min(max(0, item.start), duration)
            let end = min(duration, max(begin, item.end))
            guard end > begin + 0.04 else { continue }
            let fontSize = CGFloat(min(160, max(15, item.fontSize)))
            let width = canvas.width * 0.85
            let height = min(canvas.height * 0.5, fontSize * 3.5)
            let outer = CALayer()
            outer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            outer.cornerRadius = fontSize * 0.20
            if item.useBackground {
                outer.backgroundColor = UIColor.black.withAlphaComponent(0.52).cgColor
            }
            outer.opacity = 0

            let title = CATextLayer()
            title.frame = outer.bounds.insetBy(dx: 9, dy: 5)
            title.string = item.text
            title.font = UIFont.boldSystemFont(ofSize: fontSize)
            title.fontSize = fontSize
            title.alignmentMode = .center
            title.foregroundColor = uiColor(hex: item.colorHex).cgColor
            title.isWrapped = true
            title.contentsScale = 2
            outer.addSublayer(title)

            let p1 = CGPoint(x: item.startX * canvas.width,
                             y: (1 - item.startY) * canvas.height)
            let p2 = CGPoint(x: item.endX * canvas.width,
                             y: (1 - item.endY) * canvas.height)
            outer.position = p1
            parent.addSublayer(outer)

            let alpha = CAKeyframeAnimation(keyPath: "opacity")
            alpha.values = [0, Float(min(1, max(0, item.opacity))),
                            Float(min(1, max(0, item.opacity))), 0]
            alpha.keyTimes = [0, 0.04, 0.96, 1]
            alpha.beginTime = AVCoreAnimationBeginTimeAtZero + begin
            alpha.duration = end - begin
            alpha.isRemovedOnCompletion = false
            alpha.fillMode = .forwards
            outer.add(alpha, forKey: "text-alpha-\(item.id)")

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: p1)
            move.toValue = NSValue(cgPoint: p2)
            move.beginTime = AVCoreAnimationBeginTimeAtZero + begin
            move.duration = end - begin
            move.timingFunction = CAMediaTimingFunction(name: easing(item.easing))
            move.isRemovedOnCompletion = false
            move.fillMode = .forwards
            outer.add(move, forKey: "text-position-\(item.id)")
        }
    }

    static func easing(_ mode: OverlayEasing) -> CAMediaTimingFunctionName {
        switch mode {
        case .linear: return .linear
        case .easeIn: return .easeIn
        case .easeOut: return .easeOut
        case .easeInOut: return .easeInEaseOut
        }
    }

    static func uiColor(hex: String) -> UIColor {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let number = UInt32(cleaned, radix: 16), cleaned.count == 6 else {
            return .white
        }
        return UIColor(red: CGFloat((number >> 16) & 255) / 255,
                       green: CGFloat((number >> 8) & 255) / 255,
                       blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}
