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
        personBackground: PersonBackground = .original,
        behindTitles: [TextOverlayClip] = [],
        timelineStart: Double = 0,
        sourceStart: Double = 0,
        speed: Double = 1,
        filmstrips: [UUID: TextMaskMedia.Filmstrip] = [:]
    ) -> AVVideoComposition {
        let context = CIContext(options: [.cacheIntermediates: false])
        return AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            do {
                let graded = StudioColorGrader.apply(
                    source, look: look, intensity: intensity,
                    adjustments: adjustments
                ).cropped(to: source.extent)
                let output = try PersonCutoutProcessor.apply(
                    source, mode: personBackground, quality: .fast,
                    foreground: graded
                )
                let projectSecond = TextTitleRenderTime.projectSecond(
                    clipStart: timelineStart,
                    trimmedCompositionSecond:
                        request.compositionTime.seconds - sourceStart,
                    playbackSpeed: speed
                )
                let composited = try TextBehindPersonRenderer.apply(
                    to: output, items: behindTitles,
                    projectTime: projectSecond, maskSource: source,
                    films: filmstrips, quality: .fast
                )
                request.finish(with: composited, context: context)
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
        clip: TimelineClip, outputURL: URL,
        behindTitles: [TextOverlayClip] = [],
        timelineStart: Double = 0,
        filmstrips: [UUID: TextMaskMedia.Filmstrip] = [:]
    ) async throws {
        guard clip.kind == .video,
              ((clip.imageLook != .original && clip.lookIntensity > 0.001) ||
                !clip.colorAdjustments.isNeutral ||
                clip.personBackground != .original ||
                !behindTitles.isEmpty) else {
            throw SmartVideoError.invalidMedia(
                "Không có bộ màu video cần xử lý."
            )
        }
        let originalAsset = AVURLAsset(url: clip.fileURL)
        guard let videoTrack = try await originalAsset.loadTracks(
            withMediaType: .video
        ).first else {
            throw SmartVideoError.missingVideoTrack(clip.filename)
        }
        let available = try await originalAsset.load(.duration).seconds
        let start = max(0, clip.startTime)
        let seconds = min(clip.duration, max(0, available - start))
        guard seconds.isFinite && seconds > 0.06 else {
            throw SmartVideoError.invalidMedia(
                "Đoạn video quá ngắn hoặc mốc cắt không hợp lệ."
            )
        }

        // Critical for title depth: AVVideoComposition on a source file
        // with timeRange=sourceStart may report compositionTime relative to
        // zero OR the original asset's source timestamp depending on export
        // path. In 5.5.1 titles after 0s could be permanently gated out.
        // Trim all tracks into a composition whose first frame is 0 seconds;
        // now the compositor clock is deterministic for every iPhone source.
        let zeroBased = AVMutableComposition()
        guard let trimmedVideo = zeroBased.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SmartVideoError.cannotCreateWriter
        }
        let sourceRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: seconds, preferredTimescale: 600)
        )
        try trimmedVideo.insertTimeRange(
            sourceRange, of: videoTrack, at: .zero
        )
        trimmedVideo.preferredTransform = try await videoTrack.load(
            .preferredTransform
        )

        // Preserve original sound while re-basing its timestamps.
        if let audio = try await originalAsset.loadTracks(
            withMediaType: .audio
        ).first {
            let audibleRange = CMTimeRangeGetIntersection(
                sourceRange, try await audio.load(.timeRange)
            )
            if audibleRange.duration.isNumeric &&
                CMTimeCompare(audibleRange.duration, .zero) > 0,
                let trimmedAudio = zeroBased.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) {
                try trimmedAudio.insertTimeRange(
                    audibleRange, of: audio,
                    at: CMTimeSubtract(audibleRange.start,
                                       sourceRange.start)
                )
            }
        }

        guard let exporter = AVAssetExportSession(
            asset: zeroBased,
            presetName: AVAssetExportPresetHighestQuality
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
            asset: zeroBased, look: clip.imageLook,
            intensity: clip.lookIntensity,
            adjustments: clip.colorAdjustments,
            personBackground: clip.personBackground,
            behindTitles: behindTitles,
            timelineStart: timelineStart,
            sourceStart: 0,
            speed: clip.playbackSpeed,
            filmstrips: filmstrips
        )
        // The source was trimmed BEFORE videoComposition; no timeRange
        // is applied to this export. All filters begin at t=0.
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
