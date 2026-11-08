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
        soundEffects: [SoundEffectClip],
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

        var sourceURLs: [URL] = []
        for clip in clips {
            try Task.checkCancellation()
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
                    flipHorizontal: clip.flipHorizontal,
                    flipVertical: clip.flipVertical
                )
                sourceURLs.append(temporary)
            } else {
                sourceURLs.append(clip.fileURL)
            }
        }

        // Compose into two alternating tracks. Adjacent segments overlap
        // only when the user chooses the dissolve transition.
        let timeline = try await TimelineComposer().compose(
            clips: clips,
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
        var musicParameters: AVMutableAudioMixInputParameters?
        var musicEnd = CMTime.zero
        var narrationEnd = CMTime.zero
        var narrationStart: CMTime?

        // Music: trim at a selected start offset; loop only when requested,
        // keep its output duration aligned to the video, then fade at the end.
        if let musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            guard let musicSource = try await musicAsset.loadTracks(withMediaType: .audio).first else {
                throw SmartVideoError.invalidMedia("Tệp nhạc không có track âm thanh.")
            }
            let sourceDuration = try await musicAsset.load(.duration)
            let maxStart = max(0, sourceDuration.seconds - 0.1)
            let safeStart = min(max(0, musicStartSeconds), maxStart)
            let start = CMTime(seconds: safeStart, preferredTimescale: 600)
            let availableMusic = CMTimeSubtract(sourceDuration, start)
            let remainingMusic = musicHighlightDuration > 0
                ? CMTimeMinimum(availableMusic, CMTime(seconds: musicHighlightDuration, preferredTimescale: 600))
                : availableMusic
            guard remainingMusic.isValid && CMTimeCompare(remainingMusic, .zero) > 0 else {
                throw SmartVideoError.invalidMedia("Không còn nhạc sau điểm cắt.")
            }
            guard let track = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw SmartVideoError.cannotCreateWriter }

            var outputTime = CMTime.zero
            while CMTimeCompare(outputTime, cursor) < 0 {
                try Task.checkCancellation()
                let availableVideo = CMTimeSubtract(cursor, outputTime)
                let length = CMTimeMinimum(availableVideo, remainingMusic)
                try track.insertTimeRange(
                    CMTimeRange(start: start, duration: length),
                    of: musicSource,
                    at: outputTime
                )
                outputTime = CMTimeAdd(outputTime, length)
                if !repeatShortMusic { break }
            }
            musicEnd = outputTime
            let params = AVMutableAudioMixInputParameters(track: track)
            let baseVolume = min(1, max(0, musicVolume))
            let startsImmediately = voiceoverURL != nil && voiceoverOffset <= 0.05
            let startingVolume = startsImmediately ? baseVolume * 0.25 : baseVolume
            params.setVolume(startingVolume, at: .zero)
            let fadeIn = CMTimeMinimum(
                outputTime, CMTime(seconds: max(0, min(5, musicFadeIn)), preferredTimescale: 600)
            )
            if CMTimeCompare(fadeIn, .zero) > 0 {
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: startingVolume,
                    timeRange: CMTimeRange(start: .zero, duration: fadeIn))
            }
            musicParameters = params
        }

        if let voiceoverURL {
            let voiceAsset = AVURLAsset(url: voiceoverURL)
            guard let narration = try await voiceAsset.loadTracks(withMediaType: .audio).first else {
                throw SmartVideoError.invalidMedia("Tệp thuyết minh không có âm thanh.")
            }
            let narrationDuration = try await voiceAsset.load(.duration)
            let voiceStart = CMTime(seconds: min(max(0, voiceoverOffset), cursor.seconds),
                                   preferredTimescale: 600)
            let length = CMTimeMinimum(CMTimeSubtract(cursor, voiceStart), narrationDuration)
            if CMTimeCompare(length, .zero) > 0 {
                guard let track = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw SmartVideoError.cannotCreateWriter }
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: length),
                                          of: narration, at: voiceStart)
                narrationStart = voiceStart
                narrationEnd = CMTimeAdd(voiceStart, length)
                let narrationParams = AVMutableAudioMixInputParameters(track: track)
                narrationParams.setVolume(min(1, max(0, voiceoverVolume)), at: voiceStart)
                mixParameters.append(narrationParams)
            }
        }

        if let musicParameters {
            let base = min(1, max(0, musicVolume))
            let ducked = base * 0.25
            let fadeLength = CMTimeMinimum(
                musicEnd, CMTime(seconds: max(0, min(8, musicFadeOut)), preferredTimescale: 600)
            )
            let fadeStart = CMTimeSubtract(musicEnd, fadeLength)
            if let start = narrationStart,
               CMTimeCompare(narrationEnd, start) > 0,
               CMTimeCompare(start, fadeStart) < 0 {
                // Duck only while the narration is audible. Avoid constantly
                // attenuating background music during a late voiceover.
                if CMTimeCompare(start,
                                 CMTime(seconds: 0.25, preferredTimescale: 600)) > 0 {
                    let transitionLength = CMTimeMinimum(
                        CMTime(seconds: 0.15, preferredTimescale: 600),
                        CMTimeSubtract(narrationEnd, start)
                    )
                    if CMTimeCompare(transitionLength, .zero) > 0 {
                        musicParameters.setVolumeRamp(
                            fromStartVolume: base, toEndVolume: ducked,
                            timeRange: CMTimeRange(start: start, duration: transitionLength)
                        )
                    }
                }
                if CMTimeCompare(narrationEnd, fadeStart) < 0 {
                    let returnLength = CMTimeMinimum(
                        CMTime(seconds: 0.2, preferredTimescale: 600),
                        CMTimeSubtract(fadeStart, narrationEnd)
                    )
                    if CMTimeCompare(returnLength, .zero) > 0 {
                        musicParameters.setVolumeRamp(
                            fromStartVolume: ducked, toEndVolume: base,
                            timeRange: CMTimeRange(start: narrationEnd, duration: returnLength)
                        )
                    }
                }
            }
            if CMTimeCompare(fadeLength, .zero) > 0 {
                let isNarratingAtFade = narrationStart.map { start in
                    CMTimeCompare(start, fadeStart) <= 0 &&
                    CMTimeCompare(narrationEnd, fadeStart) >= 0
                } ?? false
                musicParameters.setVolumeRamp(
                    fromStartVolume: isNarratingAtFade ? ducked : base,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(start: fadeStart, duration: fadeLength)
                )
            }
            mixParameters.append(musicParameters)
        }

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
        flipHorizontal: Bool,
        flipVertical: Bool
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
        let fitted = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (size.width - extent.width * scale) / 2,
                y: (size.height - extent.height * scale) / 2
            ))
        let black = CIImage(color: .black).cropped(to: canvasRect)
        let styled = colorGrade(fitted, preset: imageLook)
        let staticFrame = styled.composited(over: black)
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
                frameImage = styled.transformed(by: scale)
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
            imageContext.render(finalFrame, to: pixelBuffer,
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
        switch preset {
        case .original:
            return image
        case .cinematic:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.82,
                kCIInputContrastKey: 1.16,
                kCIInputBrightnessKey: -0.015
            ])
        case .mono:
            return image.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.1
            ])
        case .warm:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.065, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.01, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.92, w: 0)
            ])
        case .cool:
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.94, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.07, w: 0)
            ])
        }
    }

}
