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
        let audioVolume: Float
        let audioMuted: Bool
        let audioFadeIn: Double
        let audioFadeOut: Double
        let from: CMTime
        let sourceDuration: CMTime
        let outputDuration: CMTime
        let sourceSize: CGSize
        let sourceTransform: CGAffineTransform
    }

    func compose(
        clips: [TimelineClip],
        sourceURLs: [URL],
        videoOverlays: [VideoOverlayClip],
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
                audioVolume: clip.sourceAudioVolume,
                audioMuted: clip.sourceAudioMuted,
                audioFadeIn: clip.sourceAudioFadeIn,
                audioFadeOut: clip.sourceAudioFadeOut,
                from: from, sourceDuration: length, outputDuration: output,
                sourceSize: natural, sourceTransform: preferred
            ))
        }

        var overlaps = Array(repeating: CMTime.zero, count: max(0, parts.count - 1))
        if transition != .cut {
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
                    // Apply original-audio gain, explicit user fades and
                    // transition crossfades as one non-overlapping envelope.
                    // Important: stacking overlapping setVolumeRamp calls
                    // otherwise overwrites earlier fades in AVAudioMix.
                    let params = trackAudioParams[slot]
                    let inFade = index > 0 ? overlaps[index - 1] : .zero
                    let outFade = index < overlaps.count ? overlaps[index] : .zero
                    let available = CMTimeMinimum(part.outputDuration, scaledAudioLength)
                    let nodes = ClipAudioEnvelope.points(
                        duration: available.seconds,
                        volume: part.audioVolume, muted: part.audioMuted,
                        fadeIn: part.audioFadeIn, fadeOut: part.audioFadeOut,
                        incomingOverlap: inFade.seconds,
                        outgoingOverlap: outFade.seconds
                    )
                    if let first = nodes.first {
                        params.setVolume(first.gain, at: start)
                    }
                    for pair in zip(nodes, nodes.dropFirst()) {
                        let (first, second) = pair
                        let time = CMTimeAdd(start, CMTime(
                            seconds: first.second, preferredTimescale: 60_000
                        ))
                        let duration = CMTime(
                            seconds: second.second - first.second,
                            preferredTimescale: 60_000
                        )
                        guard CMTimeCompare(duration, .zero) > 0 else { continue }
                        params.setVolumeRamp(
                            fromStartVolume: first.gain,
                            toEndVolume: second.gain,
                            timeRange: CMTimeRange(start: time, duration: duration)
                        )
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
                let outgoing = layer(at: index, for: transitionStart)
                let overlap = AVMutableVideoCompositionInstruction()
                overlap.timeRange = CMTimeRange(start: transitionStart, duration: nextOverlap)
                overlap.layerInstructions = [incoming, outgoing]
                if transition == .dissolve {
                    // Cross dissolve: the top (incoming) layer fades over
                    // the previous clip for the full overlap duration.
                    incoming.setOpacityRamp(
                        fromStartOpacity: 0, toEndOpacity: 1,
                        timeRange: CMTimeRange(start: transitionStart, duration: nextOverlap)
                    )
                } else {
                    // Dip transition: the outgoing clip vanishes into a
                    // solid background, then the incoming clip appears.
                    // Two half-length ramps avoid an accidental crossfade.
                    let half = CMTimeMultiplyByFloat64(nextOverlap, multiplier: 0.5)
                    let midpoint = CMTimeAdd(transitionStart, half)
                    outgoing.setOpacityRamp(
                        fromStartOpacity: 1, toEndOpacity: 0,
                        timeRange: CMTimeRange(start: transitionStart, duration: half)
                    )
                    incoming.setOpacity(0, at: transitionStart)
                    incoming.setOpacityRamp(
                        fromStartOpacity: 0, toEndOpacity: 1,
                        timeRange: CMTimeRange(start: midpoint,
                                               duration: CMTimeSubtract(nextOverlap, half))
                    )
                }
                overlap.backgroundColor = (transition == .dipWhite ?
                    UIColor.white : UIColor.black).cgColor
                instructions.append(overlap)
            }
        }

        // Insert each PIP video onto its own muted composition track.
        // Split composition instructions at overlay boundaries so the video
        // source is layered in front of the appropriate timeline clips.
        struct VideoLayerSpan {
            let start: CMTime
            let end: CMTime
            let instruction: AVMutableVideoCompositionLayerInstruction
        }
        var videoSpans: [VideoLayerSpan] = []
        let timelineEnd = endTimes.last ?? .zero

        for overlay in videoOverlays.prefix(4) {
            try Task.checkCancellation()
            guard overlay.duration > 0.04,
                  overlay.start < timelineEnd.seconds else { continue }
            let asset = AVURLAsset(url: overlay.fileURL)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw SmartVideoError.missingVideoTrack(overlay.filename)
            }
            let duration = try await asset.load(.duration)
            guard duration.seconds.isFinite && duration.seconds > overlay.sourceStart else {
                throw SmartVideoError.invalidMedia("Overlay video có mốc thời gian lỗi.")
            }
            let from = CMTime(seconds: max(0, overlay.sourceStart),
                              preferredTimescale: 600)
            let start = CMTime(seconds: max(0, overlay.start),
                               preferredTimescale: 600)
            let availableSource = CMTimeSubtract(duration, from)
            let availableTimeline = CMTimeSubtract(timelineEnd, start)
            let chosen = CMTimeMinimum(
                CMTimeMinimum(availableSource, availableTimeline),
                CMTime(seconds: overlay.duration, preferredTimescale: 600)
            )
            guard CMTimeCompare(chosen, .zero) > 0 else { continue }

            guard let outputTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw SmartVideoError.cannotCreateWriter }
            try outputTrack.insertTimeRange(
                CMTimeRange(start: from, duration: chosen),
                of: source, at: start
            )

            let natural = try await source.load(.naturalSize)
            let orientation = try await source.load(.preferredTransform)
            let entry = AVMutableVideoCompositionLayerInstruction(
                assetTrack: outputTrack
            )

            // AVFoundation accepts linear ramps. Sampling the shared easing
            // / Catmull-Rom trajectory into short transform and opacity ramps
            // makes the exported video agree with the timeline preview.
            let keyframes = OverlayKeyframeSampler.frames(for: overlay)
            let durationSeconds = max(0.05, overlay.duration)
            let visibleSeconds = chosen.seconds
            let samplePoints = OverlayKeyframeSampler.samples(
                frames: keyframes, easing: overlay.easing,
                path: overlay.pathMode, stepsPerSegment: 8
            )
            if samplePoints.count >= 2 {
                for i in 0..<(samplePoints.count - 1) {
                    try Task.checkCancellation()
                    let a = samplePoints[i]
                    let b = samplePoints[i + 1]
                    let localFrom = a.progress * durationSeconds
                    let localTo = min(visibleSeconds,
                                      b.progress * durationSeconds)
                    guard localFrom < visibleSeconds,
                          localTo - localFrom >= 0.001 else { continue }
                    let left = a
                    let right = localTo < b.progress * durationSeconds - 0.0001
                        ? OverlayKeyframeSampler.sample(
                            overlay, atProgress: localTo / durationSeconds
                          ) : b
                    let beginTransform = pipTransform(
                        sourceSize: natural, preferred: orientation,
                        canvas: renderSize, x: left.x, y: left.y,
                        width: left.scale, rotationDegrees: left.rotationDegrees
                    )
                    let endTransform = pipTransform(
                        sourceSize: natural, preferred: orientation,
                        canvas: renderSize, x: right.x, y: right.y,
                        width: right.scale, rotationDegrees: right.rotationDegrees
                    )
                    let range = CMTimeRange(
                        start: CMTime(seconds: start.seconds + localFrom,
                                      preferredTimescale: 600),
                        duration: CMTime(seconds: localTo - localFrom,
                                         preferredTimescale: 600)
                    )
                    entry.setTransformRamp(
                        fromStart: beginTransform, toEnd: endTransform,
                        timeRange: range
                    )
                    entry.setOpacityRamp(
                        fromStartOpacity: Float(left.opacity),
                        toEndOpacity: Float(right.opacity),
                        timeRange: range
                    )
                }
            }
            videoSpans.append(VideoLayerSpan(
                start: start, end: CMTimeAdd(start, chosen), instruction: entry
            ))
        }

        if !videoSpans.isEmpty {
            var rebuilt: [AVMutableVideoCompositionInstruction] = []
            for instruction in instructions {
                let firstTime = instruction.timeRange.start
                let lastTime = instruction.timeRange.end
                var boundaries: [CMTime] = [firstTime, lastTime]
                for span in videoSpans {
                    if CMTimeCompare(span.start, firstTime) > 0 &&
                       CMTimeCompare(span.start, lastTime) < 0 {
                        boundaries.append(span.start)
                    }
                    if CMTimeCompare(span.end, firstTime) > 0 &&
                       CMTimeCompare(span.end, lastTime) < 0 {
                        boundaries.append(span.end)
                    }
                }
                boundaries.sort { CMTimeCompare($0, $1) < 0 }
                for index in 0..<(boundaries.count - 1) {
                    let from = boundaries[index]
                    let to = boundaries[index + 1]
                    guard CMTimeCompare(to, from) > 0 else { continue }
                    let piece = AVMutableVideoCompositionInstruction()
                    piece.timeRange = CMTimeRange(
                        start: from, duration: CMTimeSubtract(to, from)
                    )
                    piece.backgroundColor = instruction.backgroundColor ?? UIColor.black.cgColor
                    let active = videoSpans.filter {
                        CMTimeCompare($0.start, from) <= 0 &&
                        CMTimeCompare($0.end, from) > 0
                    }
                    // Higher overlay z-order first; composition instructions
                    // list front-to-back.
                    piece.layerInstructions = active.reversed().map {
                        $0.instruction as AVVideoCompositionLayerInstruction
                    } +
                        instruction.layerInstructions
                    rebuilt.append(piece)
                }
            }
            instructions = rebuilt
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

    private func pipTransform(
        sourceSize: CGSize,
        preferred: CGAffineTransform,
        canvas: CGSize,
        x: Double, y: Double, width: Double,
        rotationDegrees: Double = 0
    ) -> CGAffineTransform {
        let source = CGRect(origin: .zero, size: sourceSize)
            .applying(preferred).standardized
        guard source.width > 0, source.height > 0 else { return .identity }
        let desiredWidth = canvas.width * CGFloat(min(0.95, max(0.1, width)))
        let factor = desiredWidth / source.width
        let desiredHeight = source.height * factor
        let centerX = CGFloat(min(1, max(0, x))) * canvas.width
        let centerY = CGFloat(min(1, max(0, y))) * canvas.height
        return preferred
            .concatenating(CGAffineTransform(
                translationX: -source.minX, y: -source.minY
            ))
            .concatenating(CGAffineTransform(scaleX: factor, y: factor))
            .concatenating(CGAffineTransform(
                translationX: -desiredWidth / 2,
                y: -desiredHeight / 2
            ))
            .concatenating(CGAffineTransform(
                rotationAngle: CGFloat(rotationDegrees) * .pi / 180
            ))
            .concatenating(CGAffineTransform(
                translationX: centerX, y: centerY
            ))
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
