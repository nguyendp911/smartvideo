import Foundation
import AVFoundation

/// Adds independent audio tracks and ramps before MP4 export.
/// Source media is never modified and silent PIP video remains unaffected.
enum SoundEffectsMixer {
    static func add(
        _ effects: [SoundEffectClip],
        to composition: AVMutableComposition,
        timelineDuration: CMTime
    ) async throws -> [AVAudioMixInputParameters] {
        let total = timelineDuration.seconds
        guard total.isFinite, total > 0 else { return [] }
        var mixes: [AVAudioMixInputParameters] = []

        for effect in effects.prefix(12) {
            try Task.checkCancellation()
            guard effect.start < total,
                  effect.duration >= 0.05,
                  effect.originalDuration > 0 else { continue }

            let asset = AVURLAsset(url: effect.fileURL)
            guard let sourceTrack = try await asset.loadTracks(
                withMediaType: .audio
            ).first else {
                throw SmartVideoError.invalidMedia(
                    "Không có audio trong hiệu ứng: \(effect.filename)"
                )
            }
            let fileDuration = try await asset.load(.duration)
            guard fileDuration.seconds.isFinite,
                  fileDuration.seconds > 0 else { continue }

            let start = max(0, effect.start)
            let from = max(0, effect.sourceStart)
            let remainingSource = fileDuration.seconds - from
            let remainingTimeline = total - start
            let seconds = min(effect.duration, remainingSource, remainingTimeline)
            guard seconds >= 0.05 else { continue }

            guard let destination = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw SmartVideoError.cannotCreateWriter }

            let timelineStart = CMTime(seconds: start, preferredTimescale: 600)
            let range = CMTimeRange(
                start: CMTime(seconds: from, preferredTimescale: 600),
                duration: CMTime(seconds: seconds, preferredTimescale: 600)
            )
            try destination.insertTimeRange(
                range, of: sourceTrack, at: timelineStart
            )

            let parameter = AVMutableAudioMixInputParameters(
                track: destination
            )
            let points = AudioAutomationMath.envelope(
                duration: seconds, volume: effect.volume,
                muted: effect.muted, fadeIn: effect.fadeIn,
                fadeOut: effect.fadeOut, frames: effect.volumeKeyframes
            )
            if let first = points.first {
                parameter.setVolume(first.gain, at: timelineStart)
            }
            // Keyframes and fades share one non-overlapping envelope.
            for (a, b) in zip(points, points.dropFirst()) {
                let duration = b.second - a.second
                guard duration > 0 else { continue }
                let from = CMTimeAdd(timelineStart, CMTime(
                    seconds: a.second, preferredTimescale: 60_000
                ))
                parameter.setVolumeRamp(
                    fromStartVolume: a.gain, toEndVolume: b.gain,
                    timeRange: CMTimeRange(
                        start: from, duration: CMTime(
                            seconds: duration, preferredTimescale: 60_000
                        )
                    )
                )
            }
            mixes.append(parameter)
        }
        return mixes
    }
}
