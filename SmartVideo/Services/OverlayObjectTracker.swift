import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// Vision object tracking for a SINGLE image overlay on a SINGLE video clip.
/// The starting target is the area underneath the overlay's initial position.
/// Tracking failures are surfaced instead of inventing target motion.
enum OverlayObjectTracker {
    static func generate(
        clip: TimelineClip, overlay: ImageOverlayClip,
        localStart: Double, renderSize: CGSize,
        contentMode: CanvasContentMode
    ) async throws -> [OverlayKeyframe] {
        guard clip.kind == .video, localStart >= 0,
              overlay.duration >= 0.3,
              localStart + overlay.duration <= clip.renderedDuration + 0.02 else {
            throw SmartVideoError.invalidMedia(
                "Đặt overlay nằm trọn trong một clip video để theo dõi vật thể."
            )
        }
        let asset = AVURLAsset(url: clip.fileURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw SmartVideoError.missingVideoTrack(clip.filename)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(
            seconds: 0.06, preferredTimescale: 600
        )
        generator.requestedTimeToleranceAfter = CMTime(
            seconds: 0.06, preferredTimescale: 600
        )

        let count = min(14, max(4, Int(ceil(overlay.duration * 3)) + 1))
        let handler = VNSequenceRequestHandler()
        var tracker: VNTrackObjectRequest?
        var positions: [OverlayKeyframe] = []

        for step in 0..<count {
            try Task.checkCancellation()
            let progress = Double(step) / Double(count - 1)
            let local = localStart + progress * overlay.duration
            let sourceOffset = clip.speedCurve.isEmpty
                ? local * max(0.25, clip.playbackSpeed)
                : SpeedCurveMath.sourceOffset(
                    atOutputSecond: local, sourceDuration: clip.duration,
                    points: clip.speedCurve
                )
            let sourceTime = max(0, min(
                clip.startTime + clip.duration - 0.015,
                clip.startTime + sourceOffset
            ))
            let (frame, _) = try await generator.image(
                at: CMTime(seconds: sourceTime, preferredTimescale: 600)
            )

            let width = CGFloat(frame.width)
            let height = CGFloat(frame.height)
            let factor = contentMode == .fill
                ? max(renderSize.width / width, renderSize.height / height)
                : min(renderSize.width / width, renderSize.height / height)
            let scaledWidth = width * factor
            let scaledHeight = height * factor
            let left = (renderSize.width - scaledWidth) / 2
            let top = (renderSize.height - scaledHeight) / 2

            if tracker == nil {
                // Reverse the actual fit/fill transform so the user-selected
                // canvas position becomes a real source-image target.
                let x = (CGFloat(overlay.startX) * renderSize.width - left) /
                    scaledWidth
                let topY = (CGFloat(overlay.startY) * renderSize.height - top) /
                    scaledHeight
                let centerX = min(0.95, max(0.05, x))
                let centerY = min(0.95, max(0.05, 1 - topY))
                let halfSize: CGFloat = min(0.20,
                    max(0.045, CGFloat(overlay.scale) * 0.28))
                let rect = CGRect(
                    x: max(0, centerX - halfSize),
                    y: max(0, centerY - halfSize),
                    width: min(2 * halfSize, 1 - max(0, centerX - halfSize)),
                    height: min(2 * halfSize, 1 - max(0, centerY - halfSize))
                )
                let initial = VNDetectedObjectObservation(boundingBox: rect)
                let newTracker = VNTrackObjectRequest(
                    detectedObjectObservation: initial
                )
                newTracker.trackingLevel = .accurate
                tracker = newTracker
                positions.append(OverlayKeyframe(
                    progress: progress, x: overlay.startX,
                    y: overlay.startY, scale: overlay.scale,
                    opacity: overlay.opacity,
                    rotationDegrees: overlay.rotationDegrees
                ))
                continue
            }
            guard let tracker else { continue }
            try handler.perform([tracker], on: frame, options: [:])
            guard let found = tracker.results?.first,
                  found.confidence >= 0.20 else {
                throw SmartVideoError.invalidMedia(
                    "Vision mất dấu vật thể. Hãy chọn đoạn ngắn, rõ và đặt ảnh phủ đúng vị trí ban đầu."
                )
            }
            tracker.inputObservation = found
            let centerX = (left + found.boundingBox.midX * scaledWidth) /
                renderSize.width
            let centerY = (top + (1 - found.boundingBox.midY) * scaledHeight) /
                renderSize.height
            positions.append(OverlayKeyframe(
                progress: progress,
                x: min(0.97, max(0.03, Double(centerX))),
                y: min(0.97, max(0.03, Double(centerY))),
                scale: overlay.scale,
                opacity: overlay.opacity,
                rotationDegrees: overlay.rotationDegrees
            ))
        }
        guard positions.count >= 2 else {
            throw SmartVideoError.invalidMedia(
                "Không tạo được dữ liệu theo dõi vật thể."
            )
        }
        return positions
    }
}
