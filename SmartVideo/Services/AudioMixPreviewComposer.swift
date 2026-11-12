import Foundation
import AVFoundation

/// Lightweight in-memory audio mix used for review without writing MP4.
/// Same project-track offset and gain math as the final VideoRenderer.
/// Original video clip source audio is intentionally not included here.
enum AudioMixPreviewComposer {
    @MainActor
    static func makeItem(
        duration: Double,
        musicURL: URL?,
        musicStart: Double,
        musicTimelineOffset: Double,
        musicHighlightDuration: Double,
        repeatMusic: Bool,
        musicVolume: Float,
        musicVolumeKeyframes: [AudioGainKeyframe],
        musicFadeIn: Double,
        musicFadeOut: Double,
        narrationURL: URL?,
        narrationStart: Double,
        narrationVolume: Float,
        voiceVolumeKeyframes: [AudioGainKeyframe],
        musicRegions: [SoundEffectClip],
        effects: [SoundEffectClip]
    ) async throws -> AVPlayerItem {
        guard duration.isFinite, duration > 0 else {
            throw SmartVideoError.invalidMedia(
                "Chưa có video/ảnh để nghe bản phối."
            )
        }
        let total = CMTime(seconds: duration, preferredTimescale: 600)
        let composition = AVMutableComposition()
        var mixes: [AVAudioMixInputParameters] = []

        func mix(
            _ track: AVMutableCompositionTrack,
            at start: Double,
            points: [(second: Double, gain: Float)]
        ) -> AVAudioMixInputParameters {
            let params = AVMutableAudioMixInputParameters(track: track)
            let at = CMTime(seconds: start, preferredTimescale: 60_000)
            if let first = points.first {
                params.setVolume(first.gain, at: at)
            }
            for (a, b) in zip(points, points.dropFirst()) {
                guard b.second > a.second else { continue }
                params.setVolumeRamp(
                    fromStartVolume: a.gain, toEndVolume: b.gain,
                    timeRange: CMTimeRange(
                        start: CMTimeAdd(at, CMTime(
                            seconds: a.second, preferredTimescale: 60_000
                        )),
                        duration: CMTime(
                            seconds: b.second - a.second,
                            preferredTimescale: 60_000
                        )
                    )
                )
            }
            return params
        }

        var voiceAt: Double?
        var voiceEnd: Double?
        if let narrationURL {
            let asset = AVURLAsset(url: narrationURL)
            guard let source = try await asset.loadTracks(
                withMediaType: .audio
            ).first else {
                throw SmartVideoError.invalidMedia(
                    "Thuyết minh không có track âm thanh."
                )
            }
            let fileDuration = try await asset.load(.duration).seconds
            let start = ProjectAudioTrackMath.safeStart(
                narrationStart, projectDuration: duration
            )
            let seconds = min(max(0, fileDuration), duration - start)
            if seconds > 0.05 {
                guard let output = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw SmartVideoError.cannotCreateWriter }
                try output.insertTimeRange(
                    CMTimeRange(
                        start: .zero,
                        duration: CMTime(seconds: seconds,
                                         preferredTimescale: 600)
                    ), of: source,
                    at: CMTime(seconds: start,
                               preferredTimescale: 600)
                )
                voiceAt = start
                voiceEnd = start + seconds
                mixes.append(mix(output, at: start,
                    points: ProjectAudioTrackMath.points(
                        duration: seconds, volume: narrationVolume,
                        fadeIn: 0, fadeOut: 0,
                        keyframes: voiceVolumeKeyframes
                    )))
            }
        }

        if let musicURL {
            let asset = AVURLAsset(url: musicURL)
            guard let source = try await asset.loadTracks(
                withMediaType: .audio
            ).first else {
                throw SmartVideoError.invalidMedia(
                    "Không đọc được track nhạc nền."
                )
            }
            let fileSeconds = try await asset.load(.duration).seconds
            let offset = min(max(0, musicStart),
                             max(0, fileSeconds - 0.05))
            let section = musicHighlightDuration > 0
                ? min(fileSeconds - offset, musicHighlightDuration)
                : fileSeconds - offset
            let at = ProjectAudioTrackMath.safeStart(
                musicTimelineOffset, projectDuration: duration
            )
            let span = ProjectAudioTrackMath.musicDuration(
                projectDuration: duration, timelineStart: at,
                fileDuration: fileSeconds, sourceStart: offset,
                highlightDuration: musicHighlightDuration,
                repeats: repeatMusic
            )
            if section > 0.05 && span > 0.05 {
                guard let output = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw SmartVideoError.cannotCreateWriter }
                var played = 0.0
                while played < span - 0.01 {
                    try Task.checkCancellation()
                    let length = min(section, span - played)
                    guard length > 0.02 else { break }
                    try output.insertTimeRange(
                        CMTimeRange(
                            start: CMTime(seconds: offset,
                                          preferredTimescale: 600),
                            duration: CMTime(seconds: length,
                                             preferredTimescale: 600)
                        ), of: source,
                        at: CMTime(seconds: at + played,
                                   preferredTimescale: 600)
                    )
                    played += length
                    if !repeatMusic { break }
                }
                mixes.append(mix(output, at: at,
                    points: ProjectAudioTrackMath.points(
                        duration: played, volume: musicVolume,
                        fadeIn: musicFadeIn, fadeOut: musicFadeOut,
                        keyframes: musicVolumeKeyframes,
                        narrationStart: voiceAt.map { $0 - at },
                        narrationEnd: voiceEnd.map { $0 - at }
                    )))
            }
        }

        mixes.append(contentsOf: try await SoundEffectsMixer.add(
            musicRegions, to: composition, timelineDuration: total,
            narrationStart: voiceAt, narrationEnd: voiceEnd
        ))
        mixes.append(contentsOf: try await SoundEffectsMixer.add(
            effects, to: composition, timelineDuration: total
        ))
        guard !mixes.isEmpty else {
            throw SmartVideoError.invalidMedia(
                "Chưa có nhạc, thuyết minh hoặc SFX để nghe thử."
            )
        }
        let item = AVPlayerItem(asset: composition)
        let result = AVMutableAudioMix()
        result.inputParameters = mixes
        item.audioMix = result
        return item
    }
}
