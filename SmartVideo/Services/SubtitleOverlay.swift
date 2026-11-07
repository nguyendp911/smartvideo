import Foundation
import AVFoundation
import QuartzCore
import UIKit

enum SubtitleOverlay {
    static func attach(to composition: AVMutableVideoComposition,
                       size: CGSize, cues: [SubtitleCue]) {
        guard !cues.isEmpty else { return }

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        let video = CALayer()
        video.frame = parent.bounds
        parent.addSublayer(video)

        for cue in cues where cue.end > cue.start && !cue.text.isEmpty {
            let width = size.width * 0.88
            let fontSize = max(22, size.width * 0.047)
            let textHeight = fontSize * (cue.text.count > 45 ? 4.3 : 2.8)
            let background = CALayer()
            background.backgroundColor = UIColor.black.withAlphaComponent(0.68).cgColor
            background.cornerRadius = fontSize * 0.28
            background.frame = CGRect(
                x: (size.width - width) / 2,
                y: max(20, size.height * 0.085),
                width: width,
                height: textHeight
            )
            background.opacity = 0

            let textLayer = CATextLayer()
            textLayer.frame = background.bounds.insetBy(dx: fontSize * 0.25, dy: 4)
            textLayer.string = cue.text
            textLayer.font = UIFont.boldSystemFont(ofSize: fontSize)
            textLayer.fontSize = fontSize
            textLayer.alignmentMode = .center
            textLayer.foregroundColor = UIColor.white.cgColor
            textLayer.isWrapped = true
            textLayer.contentsScale = 2
            background.addSublayer(textLayer)

            let visible = CAKeyframeAnimation(keyPath: "opacity")
            visible.values = [0, 1, 1, 0]
            visible.keyTimes = [0, 0.001, 0.999, 1]
            visible.beginTime = AVCoreAnimationBeginTimeAtZero + cue.start
            visible.duration = max(0.05, cue.end - cue.start)
            visible.isRemovedOnCompletion = false
            visible.fillMode = .forwards
            background.add(visible, forKey: "subtitle-\(cue.id)")
            parent.addSublayer(background)
        }

        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: video, in: parent
        )
    }
}
