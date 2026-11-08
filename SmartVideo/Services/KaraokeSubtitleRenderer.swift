import Foundation
import AVFoundation
import QuartzCore
import UIKit

/// Core Animation word-highlights burned into the same MP4 as subtitles.
/// A fixed text layout is measured once per cue; only the active word color
/// and optional motion animate. The underlying caption remains readable.
enum KaraokeSubtitleRenderer {
    private struct WordCell {
        var word: SubtitleWord
        var width: CGFloat
    }

    static func attach(cue: SubtitleCue, appearance: SubtitleAppearance,
                       to background: CALayer, fontSize: CGFloat) -> Bool {
        guard cue.hasAlignedWords else { return false }
        let font = UIFont.boldSystemFont(ofSize: fontSize)
        let padding = fontSize * 0.24
        let usable = max(100, background.bounds.width - 2 * padding)
        let space = max(4, (" " as NSString).size(
            withAttributes: [.font: font]).width)
        var lines = [[WordCell]]()
        var current = [WordCell]()
        var width: CGFloat = 0

        for word in cue.words {
            let measure = (word.text as NSString)
                .size(withAttributes: [.font: font]).width + 2
            let cell = WordCell(word: word, width: min(usable, measure))
            let nextWidth = width + (current.isEmpty ? 0 : space) + cell.width
            if !current.isEmpty && nextWidth > usable {
                lines.append(current)
                current = [cell]
                width = cell.width
            } else {
                width = nextWidth
                current.append(cell)
            }
        }
        if !current.isEmpty { lines.append(current) }

        // Avoid unbounded layer counts for pathological SRT files.
        guard !lines.isEmpty, lines.count <= 5, cue.words.count <= 14 else {
            return false
        }
        let lineHeight = font.lineHeight * 1.17
        let totalHeight = lineHeight * CGFloat(lines.count)
        let baseY = (background.bounds.height - totalHeight) / 2
        let normalColor = TextOverlayRenderer.uiColor(
            hex: appearance.foregroundHex
        ).cgColor
        let activeColor = TextOverlayRenderer.uiColor(
            hex: appearance.karaokeHex
        ).cgColor

        for (lineIndex, cells) in lines.enumerated() {
            let totalWidth = cells.reduce(CGFloat(0)) { $0 + $1.width } +
                space * CGFloat(max(0, cells.count - 1))
            var x = (background.bounds.width - totalWidth) / 2
            let y = background.bounds.height - baseY -
                    CGFloat(lineIndex + 1) * lineHeight

            for cell in cells {
                let frame = CGRect(
                    x: x, y: y, width: cell.width + 1, height: lineHeight
                )
                let base = makeLayer(
                    text: cell.word.text, frame: frame, font: font,
                    color: normalColor, shadow: appearance.shadowEnabled
                )
                background.addSublayer(base)

                let active = makeLayer(
                    text: cell.word.text, frame: frame, font: font,
                    color: activeColor, shadow: appearance.shadowEnabled
                )
                active.opacity = 0
                if appearance.karaokeMotion == .glow {
                    active.shadowColor = UIColor(
                        cgColor: activeColor
                    ).cgColor
                    active.shadowOpacity = 0.9
                    active.shadowRadius = 10
                }
                background.addSublayer(active)

                let start = max(cue.start, cell.word.start)
                let finish = min(cue.end, max(start + 0.09, cell.word.end))
                guard start < cue.end, finish > start else {
                    x += cell.width + space
                    continue
                }
                let alpha = CAKeyframeAnimation(keyPath: "opacity")
                alpha.values = [0, 1, 1, 0]
                alpha.keyTimes = [0, 0.07, 0.87, 1]
                alpha.beginTime = AVCoreAnimationBeginTimeAtZero + start
                alpha.duration = max(0.09, finish - start)
                alpha.fillMode = .forwards
                alpha.isRemovedOnCompletion = false
                active.add(alpha, forKey: "karaoke-alpha")

                if appearance.karaokeMotion == .pop {
                    let pop = CAKeyframeAnimation(
                        keyPath: "transform.scale"
                    )
                    pop.values = [1, 1.20, 1]
                    pop.keyTimes = [0, 0.3, 1]
                    pop.beginTime = AVCoreAnimationBeginTimeAtZero + start
                    pop.duration = min(0.25, max(0.12, finish - start))
                    pop.fillMode = .forwards
                    pop.isRemovedOnCompletion = false
                    active.add(pop, forKey: "karaoke-pop")
                }
                x += cell.width + space
            }
        }
        return true
    }

    private static func makeLayer(
        text: String, frame: CGRect, font: UIFont,
        color: CGColor, shadow: Bool
    ) -> CATextLayer {
        let layer = CATextLayer()
        layer.frame = frame
        layer.string = text
        layer.font = font
        layer.fontSize = font.pointSize
        layer.foregroundColor = color
        layer.alignmentMode = .left
        layer.isWrapped = false
        layer.contentsScale = 2
        if shadow {
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.9
            layer.shadowRadius = 2.5
            layer.shadowOffset = CGSize(width: 1, height: -1)
        }
        return layer
    }
}
