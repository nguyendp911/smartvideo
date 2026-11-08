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
            let gain: Float = effect.muted ? 0 : min(1, max(0, effect.volume))
            let rise = min(max(0, effect.fadeIn), seconds * 0.48)
            let fall = min(max(0, effect.fadeOut), seconds * 0.48)

            parameter.setVolume(rise > 0 ? 0 : gain, at: timelineStart)
            if rise > 0 {
                parameter.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: gain,
                    timeRange: CMTimeRange(
                        start: timelineStart,
                        duration: CMTime(seconds: rise, preferredTimescale: 600)
                    )
                )
            }
            if fall > 0 {
                let fadeStart = CMTime(
                    seconds: start + seconds - fall, preferredTimescale: 600
                )
                parameter.setVolumeRamp(
                    fromStartVolume: gain, toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: fadeStart,
                        duration: CMTime(seconds: fall, preferredTimescale: 600)
                    )
                )
            }
            mixes.append(parameter)
        }
        return mixes
    }
}
