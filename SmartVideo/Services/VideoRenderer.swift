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
        musicURL: URL?,
        musicVolume: Float,
        keepOriginalAudio: Bool,
        quality: RenderQuality,
        canvas: CanvasFormat
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
                    bitRate: quality.bitRate
                )
                sourceURLs.append(temporary)
            } else {
                sourceURLs.append(clip.fileURL)
            }
        }

        let composition = AVMutableComposition()
        guard let destinationVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SmartVideoError.cannotCreateWriter
        }

        let originalAudio = keepOriginalAudio
            ? composition.addMutableTrack(withMediaType: .audio,
                                          preferredTrackID: kCMPersistentTrackID_Invalid)
            : nil

        var instructions: [AVMutableVideoCompositionInstruction] = []
        var cursor = CMTime.zero

        for (clip, sourceURL) in zip(clips, sourceURLs) {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: sourceURL)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw SmartVideoError.missingVideoTrack(clip.filename)
            }

            let sourceDuration = try await asset.load(.duration)
            let from = clip.kind == .video
                ? CMTime(seconds: clip.startTime, preferredTimescale: 600)
                : .zero
            let available = CMTimeSubtract(sourceDuration, from)
            let desired = CMTime(seconds: clip.duration, preferredTimescale: 600)
            let actual = CMTimeMinimum(available, desired)
            guard actual.isValid && CMTimeCompare(actual, .zero) > 0 else {
                throw SmartVideoError.invalidMedia("Đoạn video có thời lượng không hợp lệ: \(clip.filename)")
            }

            let sourceRange = CMTimeRange(start: from, duration: actual)
            try destinationVideo.insertTimeRange(sourceRange, of: sourceVideo, at: cursor)

            if let destinationAudio = originalAudio,
               let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                let trackRange = try await sourceAudio.load(.timeRange)
                let audioAvailable = CMTimeSubtract(trackRange.end, from)
                if audioAvailable.isValid && CMTimeCompare(audioAvailable, .zero) > 0 {
                    let audioLength = CMTimeMinimum(actual, audioAvailable)
                    try destinationAudio.insertTimeRange(
                        CMTimeRange(start: from, duration: audioLength),
                        of: sourceAudio,
                        at: cursor
                    )
                }
            }

            let naturalSize = try await sourceVideo.load(.naturalSize)
            let preferred = try await sourceVideo.load(.preferredTransform)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: destinationVideo)
            layer.setTransform(
                aspectFitTransform(size: naturalSize, preferredTransform: preferred, canvas: size),
                at: cursor
            )
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: actual)
            instruction.layerInstructions = [layer]
            instruction.backgroundColor = UIColor.black.cgColor
            instructions.append(instruction)
            cursor = CMTimeAdd(cursor, actual)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = instructions
        videoComposition.frameDuration = CMTime(value: 1, timescale: framesPerSecond)
        videoComposition.renderSize = size

        var mix: AVMutableAudioMix?
        if let musicURL {
            let musicAsset = AVURLAsset(url: musicURL)
            guard let musicSource = try await musicAsset.loadTracks(withMediaType: .audio).first else {
                throw SmartVideoError.invalidMedia("Tệp nhạc không chứa track âm thanh.")
            }
            let musicLength = try await musicAsset.load(.duration)
            guard musicLength.isValid && CMTimeCompare(musicLength, .zero) > 0 else {
                throw SmartVideoError.invalidMedia("Tệp nhạc có thời lượng không hợp lệ.")
            }
            guard let musicTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw SmartVideoError.cannotCreateWriter
            }

            // Repeat the selected track for the length of the full video.
            var at = CMTime.zero
            while CMTimeCompare(at, cursor) < 0 {
                try Task.checkCancellation()
                let remaining = CMTimeSubtract(cursor, at)
                let length = CMTimeMinimum(remaining, musicLength)
                try musicTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: length),
                    of: musicSource,
                    at: at
                )
                at = CMTimeAdd(at, length)
            }

            let params = AVMutableAudioMixInputParameters(track: musicTrack)
            params.setVolume(min(1, max(0, musicVolume)), at: .zero)
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = [params]
            mix = audioMix
        }

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

    /// Rebase rotated source coordinates into a visible rectangle,
    /// scale with letterboxing, and center in the requested output canvas.
    private func aspectFitTransform(
        size: CGSize,
        preferredTransform: CGAffineTransform,
        canvas: CGSize
    ) -> CGAffineTransform {
        let transformed = CGRect(origin: .zero, size: size)
            .applying(preferredTransform).standardized
        guard transformed.width > 0 && transformed.height > 0 else {
            return .identity
        }
        let scale = min(canvas.width / transformed.width, canvas.height / transformed.height)
        let offsetX = (canvas.width - transformed.width * scale) / 2
        let offsetY = (canvas.height - transformed.height * scale) / 2

        return preferredTransform
            .concatenating(CGAffineTransform(
                translationX: -transformed.minX,
                y: -transformed.minY
            ))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }

    private func writeStillImage(
        at imageURL: URL,
        to destinationURL: URL,
        duration: Double,
        size: CGSize,
        bitRate: Int
    ) async throws {
        guard let image = CIImage(contentsOf: imageURL, options: [.applyOrientationProperty: true]) else {
            throw SmartVideoError.invalidMedia("Không mở được ảnh: \(imageURL.lastPathComponent)")
        }

        let canvasRect = CGRect(origin: .zero, size: size)
        let extent = image.extent
        guard extent.width > 0 && extent.height > 0 else {
            throw SmartVideoError.invalidMedia("Ảnh không có kích thước hợp lệ.")
        }
        let scale = min(size.width / extent.width, size.height / extent.height)
        let fitted = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(
                translationX: (size.width - extent.width * scale) / 2,
                y: (size.height - extent.height * scale) / 2
            ))
        let black = CIImage(color: .black).cropped(to: canvasRect)
        let frameImage = fitted.composited(over: black)
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
            imageContext.render(frameImage, to: pixelBuffer, bounds: canvasRect, colorSpace: colorSpace)
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
}
