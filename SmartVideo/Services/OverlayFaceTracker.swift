import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// Generates real sticker keyframes from faces detected in one source video.
/// This is a face FOLLOW assist, not generic Vision object tracking.
/// Frame sampling is capped to avoid overloading older iPhones.
enum OverlayFaceTracker {
    static func generate(
        clip: TimelineClip, overlay: ImageOverlayClip,
        localStart: Double, renderSize: CGSize,
        contentMode: CanvasContentMode
    ) async throws -> [OverlayKeyframe] {
        guard clip.kind == .video, localStart >= 0,
              overlay.duration > 0.2,
              localStart + overlay.duration <= clip.renderedDuration + 0.02 else {
            throw SmartVideoError.invalidMedia(
                "Overlay phải nằm trọn trong một đoạn video để bám khuôn mặt."
            )
        }
        let asset = AVURLAsset(url: clip.fileURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw SmartVideoError.missingVideoTrack(clip.filename)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)

        // The overlay renderer supports 16 authorable keyframes. Cap here so
        // all sampled positions survive Codable and live/export interpolation.
        let sampleCount = min(14, max(4, Int(ceil(overlay.duration * 2)) + 1))
        var observations: [(progress: Double, x: Double, y: Double)] = []
        var lastTarget: CGPoint? = CGPoint(x: overlay.startX, y: overlay.startY)
        var actualDetections = 0

        for step in 0..<sampleCount {
            try Task.checkCancellation()
            let progress = Double(step) / Double(sampleCount - 1)
            let outputSecond = localStart + progress * overlay.duration
            let sourceOffset = clip.speedCurve.isEmpty
                ? outputSecond * max(0.25, clip.playbackSpeed)
                : SpeedCurveMath.sourceOffset(
                    atOutputSecond: outputSecond,
                    sourceDuration: clip.duration,
                    points: clip.speedCurve
                )
            let sourceTime = min(
                clip.startTime + clip.duration - 0.015,
                clip.startTime + sourceOffset
            )
            let (frame, _) = try await generator.image(
                at: CMTime(seconds: max(0, sourceTime),
                           preferredTimescale: 600)
            )
            let request = VNDetectFaceRectanglesRequest()
            try VNImageRequestHandler(cgImage: frame, options: [:])
                .perform([request])
            let faces = request.results ?? []
            guard !faces.isEmpty else { continue }

            let width = CGFloat(frame.width)
            let height = CGFloat(frame.height)
            let factor = contentMode == .fill
                ? max(renderSize.width / width, renderSize.height / height)
                : min(renderSize.width / width, renderSize.height / height)
            let scaledWidth = width * factor
            let scaledHeight = height * factor
            let left = (renderSize.width - scaledWidth) / 2
            let top = (renderSize.height - scaledHeight) / 2

            let candidates: [CGPoint] = faces.map { face in
                let bounds = face.boundingBox
                let pointX = (left + bounds.midX * scaledWidth) / renderSize.width
                let pointY = (top + (1 - bounds.midY) * scaledHeight) / renderSize.height
                return CGPoint(x: min(0.97, max(0.03, pointX)),
                               y: min(0.97, max(0.03, pointY)))
            }
            let chosen = candidates.min {
                let anchor = lastTarget ?? CGPoint(x: 0.5, y: 0.5)
                let leftDistance = pow($0.x - anchor.x, 2) +
                    pow($0.y - anchor.y, 2)
                let rightDistance = pow($1.x - anchor.x, 2) +
                    pow($1.y - anchor.y, 2)
                return leftDistance < rightDistance
            } ?? candidates[0]
            lastTarget = chosen
            actualDetections += 1
            observations.append((progress, Double(chosen.x), Double(chosen.y)))
        }

        guard actualDetections >= 2 else {
            throw SmartVideoError.invalidMedia(
                "Không phát hiện đủ khuôn mặt. Thử clip sáng rõ hoặc chỉnh keyframe thủ công."
            )
        }
        var keyframes: [OverlayKeyframe] = observations.map {
            OverlayKeyframe(progress: $0.progress, x: $0.x, y: $0.y,
                            scale: overlay.scale, opacity: overlay.opacity,
                            rotationDegrees: overlay.rotationDegrees)
        }
        if let first = keyframes.first, first.progress > 0 {
            keyframes.insert(OverlayKeyframe(
                progress: 0, x: first.x, y: first.y,
                scale: first.scale, opacity: first.opacity,
                rotationDegrees: first.rotationDegrees
            ), at: 0)
        }
        if let last = keyframes.last, last.progress < 1 {
            keyframes.append(OverlayKeyframe(
                progress: 1, x: last.x, y: last.y,
                scale: last.scale, opacity: last.opacity,
                rotationDegrees: last.rotationDegrees
            ))
        }
        return keyframes
    }
}
