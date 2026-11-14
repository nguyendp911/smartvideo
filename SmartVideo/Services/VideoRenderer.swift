import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import UIKit

/// Offline export pipeline:
/// 1. Encode still images as short H.264 video segments using hardware writer.
/// 2. Concatenate video segments on AVMutableComposition.
/// 3. Apply aspect-fit transforms and audio mix.
/// 4. Export one MP4 with AVAssetExportSession.
final class VideoRenderer {
    private let framesPerSecond: Int32 = 30
    private let imageContext = CIContext(options: [.cacheIntermediates: false])

    func render(
        clips: [TimelineClip],
        imageOverlays: [ImageOverlayClip],
        videoOverlays: [VideoOverlayClip],
        textOverlays: [TextOverlayClip],
        mockupOverlays: [MockupOverlayClip],
        soundEffects: [SoundEffectClip],
        musicRegions: [SoundEffectClip],
        transition: VideoTransition,
        transitionSeconds: Double,
        vfxPresets: [VFXPreset],
        vfxIntensity: Double,
        vfxCoverage: VFXCoverage,
        vfxStartTime: Double,
        vfxEndTime: Double,
        musicURL: URL?,
        musicVolume: Float,
        musicStartSeconds: Double,
        musicTimelineOffset: Double,
        musicVolumeKeyframes: [AudioGainKeyframe],
        voiceVolumeKeyframes: [AudioGainKeyframe],
        repeatShortMusic: Bool,
        musicHighlightDuration: Double,
        voiceoverURL: URL?,
        voiceoverOffset: Double,
        voiceoverVolume: Float,
        subtitles: [SubtitleCue],
        subtitleAppearance: SubtitleAppearance,
        subtitleX: Double,
        subtitleY: Double,
        keepOriginalAudio: Bool,
        quality: RenderQuality,
        canvas: CanvasFormat,
        contentMode: CanvasContentMode,
        stripMetadata: Bool,
        exportMetadata: ExportMetadata,
        musicFadeIn: Double,
        musicFadeOut: Double
    ) async throws -> URL {
        guard !clips.isEmpty else {
            throw SmartVideoError.invalidMedia("Hãy thêm ảnh hoặc video trước khi xuất.")
        }

        let size = canvas.size(for: quality)
        var generatedImageVideos: [URL] = []
        defer {
            for file in generatedImageVideos {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Prepare a small, bounded filmstrip once per video-filled title.
        // Never decode MOV/MP4 inside each exported source frame.
        var textFilms: [UUID: TextMaskMedia.Filmstrip] = [:]
        for item in textOverlays where item.fillMode == .video {
            if let url = item.fillAssetURL,
               let film = TextMaskMedia.load(url: url) {
                textFilms[item.id] = film
            }
        }

        // Match TimelineComposer's overlapping transition positions.
        var clipStarts: [Double] = []
        var position = 0.0
        for i in clips.indices {
            if i > 0 && transition != .cut {
                let previous = clips[i - 1].renderedDuration
                let incoming = clips[i].renderedDuration
                position -= min(transitionSeconds,
                                previous * 0.24, incoming * 0.24)
            }
            clipStarts.append(max(0, position))
            position += clips[i].renderedDuration
        }

        var workingClips = clips
        var sourceURLs: [URL] = []
        for (index, clip) in clips.enumerated() {
            try Task.checkCancellation()
            let clipStart = clipStarts[index]
            let behindTitles = textOverlays.filter {
                $0.depthMode == .behindPerson &&
                TextTitleRenderTime.intersects(
                    titleStart: $0.start,
                    titleDuration: $0.duration,
                    clipStart: clipStart,
                    clipDuration: clip.renderedDuration
                )
            }
            let clipMockups = mockupOverlays.filter {
                TextTitleRenderTime.intersects(
                    titleStart: $0.start,
                    titleDuration: $0.duration,
                    clipStart: clipStart,
                    clipDuration: clip.renderedDuration
                ) && !$0.isHidden
            }
            if clip.kind == .image {
                let temporary = MediaStorage.newTemporaryVideoURL()
                generatedImageVideos.append(temporary)
                try await writeStillImage(
                    at: clip.fileURL,
                    to: temporary,
                    duration: clip.duration,
                    size: size,
                    bitRate: quality.bitRate,
                    contentMode: contentMode,
                    imageMotion: clip.imageMotion,
                    imageLook: clip.imageLook,
                    lookIntensity: clip.lookIntensity,
                    colorAdjustments: clip.colorAdjustments,
                    autoEnhance: clip.autoEnhance,
                    photoPreset: clip.photoPreset,
                    photoPresetIntensity: clip.photoPresetIntensity,
                    portraitFocus: clip.portraitFocus,
                    personBackground: clip.personBackground,
                    flipHorizontal: clip.flipHorizontal,
                    flipVertical: clip.flipVertical,
                    behindTitles: behindTitles,
                    timelineStart: clipStart,
                    filmstrips: textFilms,
                    mockups: clipMockups
                )
                sourceURLs.append(temporary)
            } else if !clip.speedCurve.isEmpty {
                // Retime the trimmed source first (including its audio).
                // The compositing stage can then treat it as a normal 1x
                // clip, preserving all its existing transitions and PIP.
                let rampURL = MediaStorage.newTemporaryVideoURL()
                generatedImageVideos.append(rampURL)
                try await SpeedCurveProcessor.render(
                    clip: clip, outputURL: rampURL
                )
                let rampAsset = AVURLAsset(url: rampURL)
                let rampDuration = try await rampAsset.load(.duration).seconds
                guard rampDuration.isFinite, rampDuration > 0 else {
                    throw SmartVideoError.invalidMedia(
                        "Không đọc được thời lượng của Speed Curve."
                    )
                }
                var prepared = clip
                prepared.fileURL = rampURL
                prepared.startTime = 0
                prepared.duration = rampDuration
                prepared.originalDuration = rampDuration
                prepared.playbackSpeed = 1
                prepared.speedCurve = []

                if (clip.imageLook != .original && clip.lookIntensity > 0.001) ||
                    !clip.colorAdjustments.isNeutral ||
                    clip.autoEnhance.isActive ||
                    clip.personBackground != .original ||
                    !behindTitles.isEmpty ||
                    !clipMockups.isEmpty {
                    // Existing Core Image grading is run AFTER the retime.
                    // Do not discard the grade or apply it twice.
                    let gradeURL = MediaStorage.newTemporaryVideoURL()
                    generatedImageVideos.append(gradeURL)
                    try await VideoFrameGrader.renderTrimmed(
                        clip: prepared, outputURL: gradeURL,
                        behindTitles: behindTitles,
                        timelineStart: clipStart,
                        filmstrips: textFilms,
                        mockups: clipMockups
                    )
                    sourceURLs.append(gradeURL)
                } else {
                    sourceURLs.append(rampURL)
                }
                workingClips[index] = prepared
            } else if (clip.imageLook != .original && clip.lookIntensity > 0.001) ||
                      !clip.colorAdjustments.isNeutral ||
                      clip.autoEnhance.isActive ||
                      clip.personBackground != .original ||
                      !behindTitles.isEmpty ||
                      !clipMockups.isEmpty {
                let temporary = MediaStorage.newTemporaryVideoURL()
                generatedImageVideos.append(temporary)
                try await VideoFrameGrader.renderTrimmed(
                    clip: clip, outputURL: temporary,
                    behindTitles: behindTitles,
                    timelineStart: clipStart,
                    filmstrips: textFilms,
                    mockups: clipMockups
                )
                sourceURLs.append(temporary)
                // The intermediate MOV starts at 0 because only the selected
                // section was transcoded. Keep clip speed and timeline length.
                workingClips[index].startTime = 0
            } else {
                sourceURLs.append(clip.fileURL)
            }
        }

        // Compose into two alternating tracks. Adjacent segments overlap
        // only when the user chooses the dissolve transition.
        let timeline = try await TimelineComposer().compose(
            clips: workingClips,
            sourceURLs: sourceURLs,
            videoOverlays: videoOverlays,
            renderSize: size,
            contentMode: contentMode,
            transition: transition,
            transitionSeconds: transitionSeconds,
            keepOriginalAudio: keepOriginalAudio
        )
        let composition = timeline.composition
        let videoComposition = timeline.videoComposition
        let cursor = timeline.duration

        var mixParameters: [AVAudioMixInputParameters] = timeline.originalMixParameters
        // First place narration so that music ducking can be calculated
        // in the SAME envelope as fades and volume keyframes. Individual
        // AVAudioMix ramps must never overlap or overwrite each other.
        var narrationStart: Double?
        var narrationEnd: Double?

        func rampMix(
            track: AVMutableCompositionTrack, at start: Double,
            points: [(second: Double, gain: Float)]
        ) -> AVMutableAudioMixInputParameters {
            let param = AVMutableAudioMixInputParameters(track: track)
            let global = CMTime(seconds: start, preferredTimescale: 60_000)
            if let first = points.first {
                param.setVolume(first.gain, at: global)
            }
            for (a, b) in zip(points, points.dropFirst()) {
                guard b.second > a.second else { continue }
                param.setVolumeRamp(
                    fromStartVolume: a.gain,
                    toEndVolume: b.gain,
                    timeRange: CMTimeRange(
                        start: CMTimeAdd(global, CMTime(
                            seconds: a.second, preferredTimescale: 60_000
                        )),
                        duration: CMTime(
                            seconds: b.second - a.second,
                            preferredTimescale: 60_000
                        )
                    )
                )
            }
            return param
        }

        if let voiceoverURL {
            let voiceAsset = AVURLAsset(url: voiceoverURL)
            guard let source = try await voiceAsset.loadTracks(
                withMediaType: .audio
            ).first else {
                throw SmartVideoError.invalidMedia(
                    "Tệp thuyết minh không có âm thanh."
                )
            }
            let assetDuration = try await voiceAsset.load(.duration).seconds
            let at = ProjectAudioTrackMath.safeStart(
                voiceoverOffset, projectDuration: cursor.seconds
            )
            let seconds = min(max(0, assetDuration), cursor.seconds - at)
            if seconds > 0.05 {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw SmartVideoError.cannotCreateWriter }
                try track.insertTimeRange(
                    CMTimeRange(start: .zero,
                                duration: CMTime(seconds: seconds,
                                                 preferredTimescale: 600)),
                    of: source,
                    at: CMTime(seconds: at, preferredTimescale: 600)
                )
                narrationStart = at
                narrationEnd = at + seconds
                mixParameters.append(rampMix(
                    track: track, at: at,
                    points: ProjectAudioTrackMath.points(
                        duration: seconds, volume: voiceoverVolume,
                        fadeIn: 0, fadeOut: 0,
                        keyframes: voiceVolumeKeyframes
                    )
                ))
            }
        }

        if let musicURL {
            let asset = AVURLAsset(url: musicURL)
            guard let source = try await asset.loadTracks(
                withMediaType: .audio
            ).first else {
                throw SmartVideoError.invalidMedia(
                    "Tệp nhạc không có track âm thanh."
                )
            }
            let fileSeconds = try await asset.load(.duration).seconds
            let from = min(max(0, musicStartSeconds),
                           max(0, fileSeconds - 0.05))
            let section = musicHighlightDuration > 0 ?
                min(fileSeconds - from, musicHighlightDuration) :
                fileSeconds - from
            guard section > 0.05 else {
                throw SmartVideoError.invalidMedia(
                    "Không còn nhạc sau điểm cắt."
                )
            }
            let at = ProjectAudioTrackMath.safeStart(
                musicTimelineOffset, projectDuration: cursor.seconds
            )
            let musicLength = ProjectAudioTrackMath.musicDuration(
                projectDuration: cursor.seconds, timelineStart: at,
                fileDuration: fileSeconds, sourceStart: from,
                highlightDuration: musicHighlightDuration,
                repeats: repeatShortMusic
            )
            if musicLength > 0.05 {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw SmartVideoError.cannotCreateWriter }
                var local = 0.0
                while local < musicLength - 0.01 {
                    try Task.checkCancellation()
                    let length = min(section, musicLength - local)
                    guard length > 0.02 else { break }
                    try track.insertTimeRange(
                        CMTimeRange(
                            start: CMTime(seconds: from,
                                          preferredTimescale: 600),
                            duration: CMTime(seconds: length,
                                             preferredTimescale: 600)
                        ), of: source,
                        at: CMTime(seconds: at + local,
                                   preferredTimescale: 600)
                    )
                    local += length
                    if !repeatShortMusic { break }
                }
                mixParameters.append(rampMix(
                    track: track, at: at,
                    points: ProjectAudioTrackMath.points(
                        duration: local, volume: musicVolume,
                        fadeIn: musicFadeIn, fadeOut: musicFadeOut,
                        keyframes: musicVolumeKeyframes,
                        narrationStart: narrationStart.map { $0 - at },
                        narrationEnd: narrationEnd.map { $0 - at }
                    )
                ))
            }
        }

        // Independent music regions replace the legacy single background
        // track in multi-music mode; voice ducking is per region.
        let regionParameters = try await SoundEffectsMixer.add(
            musicRegions, to: composition, timelineDuration: cursor,
            narrationStart: narrationStart,
            narrationEnd: narrationEnd
        )
        mixParameters.append(contentsOf: regionParameters)

        // Independently mix SFX at chosen global timeline positions.
        let effectParameters = try await SoundEffectsMixer.add(
            soundEffects, to: composition, timelineDuration: cursor
        )
        mixParameters.append(contentsOf: effectParameters)

        let mix: AVMutableAudioMix?
        if mixParameters.isEmpty {
            mix = nil
        } else {
            let value = AVMutableAudioMix()
            value.inputParameters = mixParameters
            mix = value
        }

        let effectBounds = vfxCoverage == .entireCanvas ?
            CGRect(origin: .zero, size: size) :
            await VFXContentBounds.detect(clips: clips, canvas: size,
                                          mode: contentMode)
        SubtitleOverlay.attach(
            to: videoComposition, size: size, cues: subtitles,
            appearance: subtitleAppearance,
            imageOverlays: imageOverlays,
            textOverlays: textOverlays,
            positionX: subtitleX, positionY: subtitleY,
            vfxPresets: vfxPresets, vfxIntensity: vfxIntensity,
            duration: cursor.seconds, effectBounds: effectBounds,
            vfxStartTime: vfxStartTime,
            vfxEndTime: vfxEndTime <= 0 ? cursor.seconds : vfxEndTime
        )
        let exportURL = MediaStorage.newExportURL()
        do {
            guard let exporter = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                throw SmartVideoError.cannotExport("Không khởi tạo được AVAssetExportSession.")
            }
            exporter.videoComposition = videoComposition
            exporter.audioMix = mix
            exporter.outputURL = exportURL
            exporter.outputFileType = .mp4
            exporter.shouldOptimizeForNetworkUse = true
            // Source metadata filtering is independent of user-authored tags.
            // When enabled, exclude private inherited source tags first.
            if stripMetadata {
                exporter.metadataItemFilter = AVMetadataItemFilter.forSharing()
            }
            exporter.metadata = exportMetadata.items()

            guard exporter.supportedFileTypes.contains(.mp4) else {
                throw SmartVideoError.cannotExport("Thiết bị không hỗ trợ xuất MP4 cho dự án này.")
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exporter.exportAsynchronously {
                    continuation.resume()
                }
            }

            guard exporter.status == .completed else {
                throw SmartVideoError.cannotExport(
                    exporter.error?.localizedDescription ?? "Trạng thái: \(exporter.status.rawValue)"
                )
            }
            return exportURL
        } catch {
            try? FileManager.default.removeItem(at: exportURL)
            throw error
        }
    }

    private func writeStillImage(
        at imageURL: URL,
        to destinationURL: URL,
        duration: Double,
        size: CGSize,
        bitRate: Int,
        contentMode: CanvasContentMode,
        imageMotion: ImageMotion,
        imageLook: ImageLook,
        lookIntensity: Double,
        colorAdjustments: ColorAdjustments,
        autoEnhance: AutoEnhanceSettings,
        photoPreset: PhotoPreset?,
        photoPresetIntensity: Double,
        portraitFocus: PhotoPortraitFocusSettings,
        personBackground: PersonBackground,
        flipHorizontal: Bool,
        flipVertical: Bool,
        behindTitles: [TextOverlayClip] = [],
        timelineStart: Double = 0,
        filmstrips: [UUID: TextMaskMedia.Filmstrip] = [:],
        mockups: [MockupOverlayClip] = []
    ) async throws {
        guard let image = CIImage(contentsOf: imageURL, options: [.applyOrientationProperty: true]) else {
            throw SmartVideoError.invalidMedia("Không mở được ảnh: \(imageURL.lastPathComponent)")
        }

        let canvasRect = CGRect(origin: .zero, size: size)
        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 else {
            throw SmartVideoError.invalidMedia("Ảnh không có kích thước hợp lệ.")
        }
        let x = size.width / extent.width
        let y = size.height / extent.height
        let scale = contentMode == .fill ? max(x, y) : min(x, y)
        // Grade the original pixels before applying an opaque matte, so
        // pure green/white remains unchanged for subsequent chroma workflows.
        // Vision is evaluated once per still, not once per output frame.
        let gradedSource = StudioColorGrader.apply(
            image, look: imageLook, intensity: lookIntensity,
            adjustments: colorAdjustments,
            autoEnhance: autoEnhance,
            photoPreset: photoPreset,
            photoPresetIntensity: photoPresetIntensity
        )
        let cutout = try PersonCutoutProcessor.apply(
            image, mode: personBackground, foreground: gradedSource,
            portraitFocus: portraitFocus
        )
        let fitted = cutout
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (size.width - extent.width * scale) / 2,
                y: (size.height - extent.height * scale) / 2
            ))
        let black = CIImage(color: .black).cropped(to: canvasRect)
        let staticFrame = fitted.composited(over: black)
        // Still-image subject segmentation only once for the source
        // photo, even when generating many pan/zoom frames.
        let needsDepthMask = !behindTitles.isEmpty ||
            mockups.contains { $0.depthMode == .behindPerson }
        let staticPersonMask = !needsDepthMask ? nil :
            try PersonCutoutProcessor.personMask(
                staticFrame, quality: .balanced
            )
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: Int(framesPerSecond),
                AVVideoMaxKeyFrameIntervalKey: Int(framesPerSecond)
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else {
            throw SmartVideoError.cannotCreateWriter
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw SmartVideoError.cannotExport(
                writer.error?.localizedDescription ?? "Không thể bắt đầu mã hóa ảnh."
            )
        }
        writer.startSession(atSourceTime: .zero)
        defer {
            if writer.status != .completed {
                writer.cancelWriting()
            }
        }

        guard let pool = adaptor.pixelBufferPool else {
            throw SmartVideoError.cannotCreateWriter
        }

        let numberOfFrames = max(1, Int(ceil(duration * Double(framesPerSecond))))
        for frameIndex in 0..<numberOfFrames {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed {
                    throw SmartVideoError.cannotExport(
                        writer.error?.localizedDescription ?? "Mã hóa ảnh thất bại."
                    )
                }
                try await Task.sleep(nanoseconds: 10_000_000)
            }

            var newPixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &newPixelBuffer)
            guard status == kCVReturnSuccess, let pixelBuffer = newPixelBuffer else {
                throw SmartVideoError.cannotCreateWriter
            }
            let progress = numberOfFrames <= 1 ? 0 :
                Double(frameIndex) / Double(numberOfFrames - 1)
            let zoom: CGFloat
            let shift: CGFloat
            switch imageMotion {
            case .none:
                zoom = 1; shift = 0
            case .zoomIn:
                zoom = CGFloat(1 + 0.12 * progress); shift = 0
            case .zoomOut:
                zoom = CGFloat(1.12 - 0.12 * progress); shift = 0
            case .panLeft:
                zoom = 1.10; shift = CGFloat((0.5 - progress) * 0.065) * size.width
            case .panRight:
                zoom = 1.10; shift = CGFloat((progress - 0.5) * 0.065) * size.width
            }
            let frameImage: CIImage
            if imageMotion == .none {
                frameImage = staticFrame
            } else {
                let scale = CGAffineTransform(
                    translationX: size.width / 2, y: size.height / 2
                )
                .scaledBy(x: zoom, y: zoom)
                .translatedBy(x: -size.width / 2, y: -size.height / 2)
                .translatedBy(x: shift / zoom, y: 0)
                frameImage = fitted.transformed(by: scale)
                    .composited(over: black).cropped(to: canvasRect)
            }
            var finalFrame = frameImage
            if flipHorizontal {
                finalFrame = finalFrame.transformed(
                    by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: size.width, ty: 0)
                )
            }
            if flipVertical {
                finalFrame = finalFrame.transformed(
                    by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
                )
            }
            var movingMask = staticPersonMask
            if let staticPersonMask, imageMotion != .none {
                let tx = CGAffineTransform(
                    translationX: size.width / 2, y: size.height / 2
                )
                .scaledBy(x: zoom, y: zoom)
                .translatedBy(x: -size.width / 2, y: -size.height / 2)
                .translatedBy(x: shift / zoom, y: 0)
                movingMask = staticPersonMask.transformed(by: tx)
                    .cropped(to: canvasRect)
            }
            if flipHorizontal {
                movingMask = movingMask?.transformed(by:
                    CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                      tx: size.width, ty: 0))
            }
            if flipVertical {
                movingMask = movingMask?.transformed(by:
                    CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                      tx: 0, ty: size.height))
            }
            let second = timelineStart +
                Double(frameIndex) / Double(framesPerSecond)
            let rear = try MockupOverlayRenderer.apply(
                finalFrame, overlays: mockups, second: second,
                depth: .behindPerson, personMask: movingMask
            )
            let titled = try TextBehindPersonRenderer.apply(
                to: rear, items: behindTitles,
                projectTime: second, maskOverride: movingMask,
                films: filmstrips, quality: .fast
            )
            let depthFrame = try MockupOverlayRenderer.apply(
                titled, overlays: mockups, second: second,
                depth: .front
            )
            imageContext.render(depthFrame, to: pixelBuffer,
                                bounds: canvasRect, colorSpace: colorSpace)
            let frameTime = CMTime(value: Int64(frameIndex), timescale: framesPerSecond)
            guard adaptor.append(pixelBuffer, withPresentationTime: frameTime) else {
                throw SmartVideoError.cannotExport(
                    writer.error?.localizedDescription ?? "Không ghi được frame ảnh."
                )
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            throw SmartVideoError.cannotExport(
                writer.error?.localizedDescription ?? "Không hoàn tất mã hóa ảnh."
            )
        }
    }
    /// Lightweight Core Image photo color looks.
    private func colorGrade(_ image: CIImage, preset: ImageLook) -> CIImage {
        StudioColorGrader.apply(image, look: preset)
    }

}
