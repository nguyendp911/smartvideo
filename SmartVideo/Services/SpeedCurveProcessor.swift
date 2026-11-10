import Foundation
import AVFoundation

/// Performs an actual nonlinear retime, including source audio when present.
/// Uses native AVFoundation time scaling; optical flow is NOT performed.
enum SpeedCurveProcessor {
    private static let timeScale: CMTimeScale = 60_000

    static func composition(for clip: TimelineClip) async throws
        -> AVMutableComposition {
        guard clip.kind == .video, !clip.speedCurve.isEmpty else {
            throw SmartVideoError.invalidMedia("Hãy chọn Speed Curve cho video.")
        }
        let asset = AVURLAsset(url: clip.fileURL)
        guard let sourceVideo = try await asset.loadTracks(
            withMediaType: .video
        ).first else {
            throw SmartVideoError.missingVideoTrack(clip.filename)
        }
        let available = try await asset.load(.duration).seconds
        let sourceStart = max(0, clip.startTime)
        let usable = min(clip.duration, max(0, available - sourceStart))
        guard usable.isFinite, usable >= 0.2 else {
            throw SmartVideoError.invalidMedia("Video quá ngắn để tạo Speed Curve.")
        }
        let slices = SpeedCurveMath.slices(
            sourceDuration: usable, points: clip.speedCurve
        )
        guard !slices.isEmpty else {
            throw SmartVideoError.invalidMedia("Đường tốc độ không hợp lệ.")
        }

        let output = AVMutableComposition()
        guard let videoTrack = output.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SmartVideoError.cannotCreateWriter
        }
        videoTrack.preferredTransform = try await sourceVideo.load(
            .preferredTransform
        )

        let sourceAudio = try await asset.loadTracks(
            withMediaType: .audio
        ).first
        let audioTrack = sourceAudio == nil ? nil : output.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTimeRange = try await sourceAudio?.load(.timeRange)
        var cursor = CMTime.zero
        for slice in slices {
            try Task.checkCancellation()
            let from = CMTime(seconds: sourceStart + slice.sourceOffset,
                              preferredTimescale: timeScale)
            let duration = CMTime(seconds: slice.sourceDuration,
                                  preferredTimescale: timeScale)
            let outputLength = CMTime(seconds: slice.outputDuration,
                                      preferredTimescale: timeScale)
            guard CMTimeCompare(duration, .zero) > 0,
                  CMTimeCompare(outputLength, .zero) > 0 else { continue }
            let range = CMTimeRange(start: from, duration: duration)

            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
            videoTrack.scaleTimeRange(
                CMTimeRange(start: cursor, duration: duration),
                toDuration: outputLength
            )
            // Keep the original audio aligned with video when the source
            // audio fully covers this slice. Sources with silent gaps remain
            // silent; we do not stretch beyond available audio samples.
            if let sourceAudio, let audioTrack, let audioTimeRange,
               CMTimeCompare(range.start, audioTimeRange.start) >= 0,
               CMTimeCompare(range.end, audioTimeRange.end) <= 0 {
                try audioTrack.insertTimeRange(
                    range, of: sourceAudio, at: cursor
                )
                audioTrack.scaleTimeRange(
                    CMTimeRange(start: cursor, duration: duration),
                    toDuration: outputLength
                )
            }
            cursor = CMTimeAdd(cursor, outputLength)
        }
        guard CMTimeCompare(cursor, .zero) > 0 else {
            throw SmartVideoError.invalidMedia("Không tạo được đoạn Speed Curve.")
        }
        return output
    }

    static func previewItem(for clip: TimelineClip) async throws
        -> AVPlayerItem {
        let asset = try await composition(for: clip)
        let item = AVPlayerItem(asset: asset)
        if (clip.imageLook != .original && clip.lookIntensity > 0.001) ||
            !clip.colorAdjustments.isNeutral {
            item.videoComposition = VideoFrameGrader.makeComposition(
                asset: asset, look: clip.imageLook,
                intensity: clip.lookIntensity,
                adjustments: clip.colorAdjustments
            )
        }
        return item
    }

    static func render(clip: TimelineClip, outputURL: URL) async throws {
        let composition = try await composition(for: clip)
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SmartVideoError.cannotExport(
                "Không thể tạo bộ xuất Speed Curve."
            )
        }
        guard exporter.supportedFileTypes.contains(.mov) else {
            throw SmartVideoError.cannotExport(
                "Thiết bị không hỗ trợ MOV trung gian."
            )
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.shouldOptimizeForNetworkUse = false
        do {
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in
                exporter.exportAsynchronously {
                    continuation.resume()
                }
            }
            try Task.checkCancellation()
            guard exporter.status == .completed else {
                throw SmartVideoError.cannotExport(
                    "Speed Curve thất bại: " +
                    (exporter.error?.localizedDescription ??
                     "trạng thái \(exporter.status.rawValue)")
                )
            }
        } catch {
            exporter.cancelExport()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
