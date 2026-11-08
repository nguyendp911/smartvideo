import Foundation
import AVFoundation
import UIKit

struct TimelineBuild {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    let duration: CMTime
    let originalMixParameters: [AVAudioMixInputParameters]
}

/// Places clips on alternating video tracks so adjacent clips can overlap.
/// Supports actual dissolve transitions, source speed and source-audio ramps.
final class TimelineComposer {
    private struct ClipPart {
        let flipHorizontal: Bool
        let flipVertical: Bool
        let sourceURL: URL
        let asset: AVURLAsset
        let video: AVAssetTrack
        let sourceAudio: AVAssetTrack?
        let from: CMTime
        let sourceDuration: CMTime
        let outputDuration: CMTime
        let sourceSize: CGSize
        let sourceTransform: CGAffineTransform
    }

    func compose(
        clips: [TimelineClip],
        sourceURLs: [URL],
        renderSize: CGSize,
        contentMode: CanvasContentMode,
        transition: VideoTransition,
        transitionSeconds: Double,
        keepOriginalAudio: Bool
    ) async throws -> TimelineBuild {
        guard clips.count == sourceURLs.count, !clips.isEmpty else {
            throw SmartVideoError.invalidMedia("Timeline không hợp lệ.")
        }

        var parts: [ClipPart] = []
        for (clip, url) in zip(clips, sourceURLs) {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: url)
            guard let video = try await asset.loadTracks(withMediaType: .video).first else {
                throw SmartVideoError.missingVideoTrack(clip.filename)
            }
            let duration = try await asset.load(.duration)
            let from = clip.kind == .video
                ? CMTime(seconds: clip.startTime, preferredTimescale: 600) : .zero
            let length = CMTimeMinimum(
                CMTimeSubtract(duration, from),
                CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            guard length.isValid, CMTimeCompare(length, .zero) > 0 else {
                throw SmartVideoError.invalidMedia("Đoạn không có thời lượng: \(clip.filename)")
            }
            let speed = clip.kind == .video ? max(0.25, clip.playbackSpeed) : 1.0
            let output = CMTime(seconds: length.seconds / speed, preferredTimescale: 600)
            let audio = try await asset.loadTracks(withMediaType: .audio).first
            let natural = try await video.load(.naturalSize)
            let preferred = try await video.load(.preferredTransform)
            parts.append(ClipPart(
                flipHorizontal: clip.kind == .video && clip.flipHorizontal,
                flipVertical: clip.kind == .video && clip.flipVertical,
                sourceURL: url, asset: asset, video: video, sourceAudio: audio,
                from: from, sourceDuration: length, outputDuration: output,
                sourceSize: natural, sourceTransform: preferred
            ))
        }

        var overlaps = Array(repeating: CMTime.zero, count: max(0, parts.count - 1))
        if transition == .dissolve {
            for index in overlaps.indices {
                // Less than one quarter of each neighboring clip prevents
                // a triple-overlap and keeps clip ordering deterministic.
                let seconds = max(0, min(
                    transitionSeconds,
                    parts[index].outputDuration.seconds * 0.24,
                    parts[index + 1].outputDuration.seconds * 0.24
                ))
                overlaps[index] = CMTime(seconds: seconds, preferredTimescale: 600)
            }
        }

        var startTimes = [CMTime]()
        var endTimes = [CMTime]()
        for index in parts.indices {
            let start: CMTime = index == 0 ? .zero :
                CMTimeSubtract(endTimes[index - 1], overlaps[index - 1])
            startTimes.append(start)
            endTimes.append(CMTimeAdd(start, parts[index].outputDuration))
        }

        let composition = AVMutableComposition()
        guard let videoA = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoB = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw SmartVideoError.cannotCreateWriter
        }
        let videoTracks = [videoA, videoB]
        var audioTracks: [AVMutableCompositionTrack] = []
        for _ in 0..<2 {
            guard let audio = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw SmartVideoError.cannotCreateWriter }
            audioTracks.append(audio)
        }

        var trackAudioParams = audioTracks.map { AVMutableAudioMixInputParameters(track: $0) }
        var activeAudio = Array(repeating: false, count: 2)
        for index in parts.indices {
            try Task.checkCancellation()
            let part = parts[index]
            let slot = index % 2
            let range = CMTimeRange(start: part.from, duration: part.sourceDuration)
            try videoTracks[slot].insertTimeRange(
                range, of: part.video, at: startTimes[index]
            )
            if CMTimeCompare(part.outputDuration, part.sourceDuration) != 0 {
                videoTracks[slot].scaleTimeRange(
                    CMTimeRange(start: startTimes[index], duration: part.sourceDuration),
                    toDuration: part.outputDuration
                )
            }

            if keepOriginalAudio, let sourceAudio = part.sourceAudio {
                let availableRange = try await sourceAudio.load(.timeRange)
                let audioAvailable = CMTimeSubtract(availableRange.end, part.from)
                if audioAvailable.isValid && CMTimeCompare(audioAvailable, .zero) > 0 {
                    let audioLength = CMTimeMinimum(part.sourceDuration, audioAvailable)
                    let scaledAudioLength = CMTimeMultiplyByFloat64(
                        audioLength, multiplier: part.outputDuration.seconds / part.sourceDuration.seconds
                    )
                    let start = startTimes[index]
                    try audioTracks[slot].insertTimeRange(
                        CMTimeRange(start: part.from, duration: audioLength),
                        of: sourceAudio, at: start
                    )
                    if CMTimeCompare(scaledAudioLength, audioLength) != 0 {
                        audioTracks[slot].scaleTimeRange(
                            CMTimeRange(start: start, duration: audioLength),
                            toDuration: scaledAudioLength
                        )
                    }
                    activeAudio[slot] = true
                    let params = trackAudioParams[slot]
                    // Handle overlap across original audio segments.
                    let inFade = index > 0 ? overlaps[index - 1] : .zero
                    let outFade = index < overlaps.count ? overlaps[index] : .zero
                    params.setVolume(CMTimeCompare(inFade, .zero) > 0 ? 0 : 1, at: start)
                    let available = CMTimeMinimum(part.outputDuration, scaledAudioLength)
                    if CMTimeCompare(inFade, .zero) > 0 {
                        let fade = CMTimeMinimum(inFade, available)
                        params.setVolumeRamp(
                            fromStartVolume: 0, toEndVolume: 1,
                            timeRange: CMTimeRange(start: start, duration: fade)
                        )
                    }
                    if CMTimeCompare(outFade, .zero) > 0 {
                        let fadeAt = CMTimeSubtract(endTimes[index], outFade)
                        if CMTimeCompare(fadeAt, start) >= 0,
                           CMTimeCompare(CMTimeSubtract(endTimes[index], fadeAt), .zero) > 0 {
                            params.setVolumeRamp(
                                fromStartVolume: 1, toEndVolume: 0,
                                timeRange: CMTimeRange(start: fadeAt, duration: outFade)
                            )
                        }
                    }
                }
            }
        }

        let originalParams: [AVAudioMixInputParameters] = trackAudioParams.enumerated()
            .compactMap { index, value in activeAudio[index] ? value : nil }
        var instructions: [AVMutableVideoCompositionInstruction] = []

        func layer(at index: Int, for time: CMTime) -> AVMutableVideoCompositionLayerInstruction {
            let part = parts[index]
            let layer = AVMutableVideoCompositionLayerInstruction(
                assetTrack: videoTracks[index % 2]
            )
            var transform = aspectTransform(
                size: part.sourceSize,
                preferredTransform: part.sourceTransform,
                canvas: renderSize,
                mode: contentMode
            )
            if part.flipHorizontal {
                transform = transform.concatenating(
                    CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                      tx: renderSize.width, ty: 0)
                )
            }
            if part.flipVertical {
                transform = transform.concatenating(
                    CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                      tx: 0, ty: renderSize.height)
                )
            }
            layer.setTransform(transform, at: time)
            return layer
        }

        for index in parts.indices {
            let previousOverlap = index > 0 ? overlaps[index - 1] : .zero
            let nextOverlap = index < overlaps.count ? overlaps[index] : .zero
            let cleanStart = CMTimeAdd(startTimes[index], previousOverlap)
            let cleanEnd = CMTimeSubtract(endTimes[index], nextOverlap)
            let cleanDuration = CMTimeSubtract(cleanEnd, cleanStart)
            if CMTimeCompare(cleanDuration, .zero) > 0 {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: cleanStart, duration: cleanDuration)
                instruction.layerInstructions = [layer(at: index, for: cleanStart)]
                instruction.backgroundColor = UIColor.black.cgColor
                instructions.append(instruction)
            }

            if index < overlaps.count, CMTimeCompare(nextOverlap, .zero) > 0 {
                let transitionStart = cleanEnd
                let incoming = layer(at: index + 1, for: transitionStart)
                incoming.setOpacityRamp(
                    fromStartOpacity: 0, toEndOpacity: 1,
                    timeRange: CMTimeRange(start: transitionStart, duration: nextOverlap)
                )
                let outgoing = layer(at: index, for: transitionStart)
                let overlap = AVMutableVideoCompositionInstruction()
                overlap.timeRange = CMTimeRange(start: transitionStart, duration: nextOverlap)
                overlap.layerInstructions = [incoming, outgoing]
                overlap.backgroundColor = UIColor.black.cgColor
                instructions.append(overlap)
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions.sorted {
            CMTimeCompare($0.timeRange.start, $1.timeRange.start) < 0
        }
        return TimelineBuild(
            composition: composition,
            videoComposition: videoComposition,
            duration: endTimes.last ?? .zero,
            originalMixParameters: originalParams
        )
    }

    private func aspectTransform(
        size: CGSize,
        preferredTransform: CGAffineTransform,
        canvas: CGSize,
        mode: CanvasContentMode
    ) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: size)
            .applying(preferredTransform).standardized
        guard rect.width > 0, rect.height > 0 else { return .identity }
        let xScale = canvas.width / rect.width
        let yScale = canvas.height / rect.height
        let scale = mode == .fill ? max(xScale, yScale) : min(xScale, yScale)
        let offX = (canvas.width - rect.width * scale) / 2
        let offY = (canvas.height - rect.height * scale) / 2
        return preferredTransform
            .concatenating(CGAffineTransform(
                translationX: -rect.minX, y: -rect.minY
            ))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offX, y: offY))
    }
}
