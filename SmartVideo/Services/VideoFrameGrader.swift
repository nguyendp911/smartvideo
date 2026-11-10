import Foundation
import AVFoundation
import CoreImage

/// Non-destructive video color-grading bridge. Because the existing editor
/// relies on a custom AVMutableVideoComposition for transitions and PIP,
/// graded video is exported as a temporary A/V source before composition.
///
/// The source's selected time range is transcoded, not the whole camera roll
/// file. The temporary MOV contains any source audio track, so TimelineComposer
/// can still keep/crossfade original audio when the user enables it.
enum VideoFrameGrader {
    static func makeComposition(
        asset: AVAsset, look: ImageLook, intensity: Double,
        adjustments: ColorAdjustments = .neutral,
        personBackground: PersonBackground = .original
    ) -> AVVideoComposition {
        let context = CIContext(options: [.cacheIntermediates: false])
        return AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            do {
                let cutout = try PersonCutoutProcessor.apply(
                    source, mode: personBackground
                )
                let graded = StudioColorGrader.apply(
                    cutout, look: look, intensity: intensity,
                    adjustments: adjustments
                ).cropped(to: source.extent)
                request.finish(with: graded, context: context)
            } catch {
                // Export fails explicitly instead of silently returning
                // the original footage without a requested AI cutout.
                request.finish(with: error)
            }
        }
    }

    static func makePreviewItem(for clip: TimelineClip) -> AVPlayerItem {
        let asset = AVURLAsset(url: clip.fileURL)
        let item = AVPlayerItem(asset: asset)
        if clip.kind == .video &&
           ((clip.imageLook != .original && clip.lookIntensity > 0.001) ||
            !clip.colorAdjustments.isNeutral ||
            clip.personBackground != .original) {
            item.videoComposition = makeComposition(
                asset: asset, look: clip.imageLook,
                intensity: clip.lookIntensity,
                adjustments: clip.colorAdjustments,
                personBackground: clip.personBackground
            )
        }
        return item
    }

    /// Returns a transient MOV containing only clip's trimmed source section.
    /// Caller must remove it and replace the working clip's startTime with 0.
    static func renderTrimmed(
        clip: TimelineClip, outputURL: URL
    ) async throws {
        guard clip.kind == .video,
              ((clip.imageLook != .original && clip.lookIntensity > 0.001) ||
                !clip.colorAdjustments.isNeutral ||
                clip.personBackground != .original) else {
            throw SmartVideoError.invalidMedia(
                "Không có bộ màu video cần xử lý."
            )
        }
        let asset = AVURLAsset(url: clip.fileURL)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw SmartVideoError.missingVideoTrack(clip.filename)
        }
        let available = try await asset.load(.duration).seconds
        let start = max(0, clip.startTime)
        let seconds = min(clip.duration, max(0, available - start))
        guard seconds.isFinite && seconds > 0.06 else {
            throw SmartVideoError.invalidMedia(
                "Đoạn video quá ngắn hoặc mốc cắt không hợp lệ."
            )
        }

        guard let exporter = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SmartVideoError.cannotExport(
                "Thiết bị không thể khởi tạo Core Image Video Grading."
            )
        }
        guard exporter.supportedFileTypes.contains(.mov) else {
            throw SmartVideoError.cannotExport(
                "Thiết bị không hỗ trợ MOV trung gian cho bộ màu video."
            )
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mov
        exporter.videoComposition = makeComposition(
            asset: asset, look: clip.imageLook,
            intensity: clip.lookIntensity,
            adjustments: clip.colorAdjustments,
            personBackground: clip.personBackground
        )
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: seconds, preferredTimescale: 600)
        )
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
                    "Không áp màu được cho \(clip.filename): " +
                    (exporter.error?.localizedDescription ??
                     "AVAssetExportSession trạng thái \(exporter.status.rawValue)")
                )
            }
        } catch {
            exporter.cancelExport()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
