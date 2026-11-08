import Foundation
import AVFoundation
import QuartzCore
import UIKit

enum SubtitleOverlay {
    static func attach(to composition: AVMutableVideoComposition,
                       size: CGSize, cues: [SubtitleCue],
                       appearance: SubtitleAppearance,
                       imageOverlays: [ImageOverlayClip],
                       textOverlays: [TextOverlayClip],
                       positionX: Double, positionY: Double,
                       vfxPresets: [VFXPreset], vfxIntensity: Double,
                       duration: Double, effectBounds: CGRect,
                       vfxStartTime: Double, vfxEndTime: Double) {
        guard !cues.isEmpty || !vfxPresets.isEmpty ||
              !imageOverlays.isEmpty || !textOverlays.isEmpty else { return }

        let parent = CALayer()
        parent.frame = CGRect(origin: .zero, size: size)
        let video = CALayer()
        video.frame = parent.bounds
        parent.addSublayer(video)
        // VFX and subtitles share one AVVideoCompositionCoreAnimationTool.
        // Effects render over the footage; captions remain legible above them.
        VFXOverlayLibrary.attach(presets: vfxPresets, to: parent,
                                 canvas: size, duration: duration,
                                 intensity: vfxIntensity,
                                 effectBounds: effectBounds,
                                 startTime: vfxStartTime,
                                 endTime: vfxEndTime)

        // PIP overlays are positioned above VFX but below subtitles.
        ImageOverlayRenderer.attach(imageOverlays, to: parent,
                                    canvas: size, timelineDuration: duration)

        TextOverlayRenderer.attach(textOverlays, to: parent,
                                   canvas: size, duration: duration)

        for cue in cues where cue.end > cue.start && !cue.text.isEmpty {
            let width = size.width * 0.72
            let fontSize = max(16, size.width * 0.047 *
                               CGFloat(min(1.6, max(0.65, appearance.fontScale))))
            let textHeight = fontSize * (cue.text.count > 45 ? 4.3 : 2.8)
            let background = CALayer()
            background.backgroundColor = UIColor.black.withAlphaComponent(
                CGFloat(min(0.95, max(0, appearance.backgroundOpacity)))
            ).cgColor
            background.cornerRadius = fontSize * 0.28
            // Normalized preview placement (0,0 top-left; 1,1 bottom-right).
            let px = min(1, max(0, positionX))
            let py = min(1, max(0, positionY))
            background.frame = CGRect(
                x: (size.width - width) * px,
                y: (size.height - textHeight) * (1 - py),
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
            textLayer.foregroundColor = TextOverlayRenderer.uiColor(
                hex: appearance.foregroundHex
            ).cgColor
            if appearance.shadowEnabled {
                textLayer.shadowColor = UIColor.black.cgColor
                textLayer.shadowOpacity = 0.9
                textLayer.shadowRadius = 2.5
                textLayer.shadowOffset = CGSize(width: 1, height: -1)
            }
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
