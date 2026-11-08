import Foundation
import AVFoundation

/// Play a lightweight in-memory audio mix without encoding an MP4.
/// Includes background music, narration and up to 12 SFX tracks.
/// Video clip source audio is intentionally excluded.
enum AudioMixPreviewComposer {
    static func makeItem(
        duration: Double,
        musicURL: URL?,
        musicStart: Double,
        musicHighlightDuration: Double,
        repeatMusic: Bool,
        musicVolume: Float,
        musicFadeIn: Double,
        musicFadeOut: Double,
        narrationURL: URL?,
        narrationStart: Double,
        narrationVolume: Float,
        effects: [SoundEffectClip]
    ) async throws -> AVPlayerItem {
        guard duration.isFinite && duration > 0 else {
            throw SmartVideoError.invalidMedia("Chưa có video/ảnh để nghe bản phối.")
        }
        let total = CMTime(seconds: duration, preferredTimescale: 600)
        let composition = AVMutableComposition()
        var mixParameters: [AVAudioMixInputParameters] = []

        if let musicURL {
            let asset = AVURLAsset(url: musicURL)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw SmartVideoError.invalidMedia("Không đọc được track nhạc nền.")
            }
            let fileSeconds = try await asset.load(.duration).seconds
            let offset = min(max(0, musicStart), max(0, fileSeconds - 0.1))
            let take = min(
                fileSeconds - offset,
                musicHighlightDuration > 0 ? musicHighlightDuration : fileSeconds
            )
            if take > 0.04 {
                guard let output = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw SmartVideoError.cannotCreateWriter }
                var cursor = 0.0
                while cursor < duration - 0.01 {
                    let length = min(take, duration - cursor)
                    guard length > 0.02 else { break }
                    try output.insertTimeRange(CMTimeRange(
                        start: CMTime(seconds: offset, preferredTimescale: 600),
                        duration: CMTime(seconds: length, preferredTimescale: 600)
                    ), of: source,
                    at: CMTime(seconds: cursor, preferredTimescale: 600))
                    cursor += length
                    if !repeatMusic { break }
                }

                let parameters = AVMutableAudioMixInputParameters(track: output)
                let volume = min(1, max(0, musicVolume))
                parameters.setVolume(volume, at: .zero)
                let fadeIn = min(max(0, musicFadeIn), cursor / 2)
                let fadeOut = min(max(0, musicFadeOut), cursor / 2)
                if fadeIn > 0.01 {
                    parameters.setVolumeRamp(
                        fromStartVolume: 0, toEndVolume: volume,
                        timeRange: CMTimeRange(
                            start: .zero,
                            duration: CMTime(seconds: fadeIn,
                                             preferredTimescale: 600)
                        )
                    )
                }
                if fadeOut > 0.01 {
                    parameters.setVolumeRamp(
                        fromStartVolume: volume, toEndVolume: 0,
                        timeRange: CMTimeRange(
                            start: CMTime(seconds: cursor - fadeOut,
                                          preferredTimescale: 600),
                            duration: CMTime(seconds: fadeOut,
                                             preferredTimescale: 600)
                        )
                    )
                }
                mixParameters.append(parameters)
            }
        }

        if let narrationURL {
            let asset = AVURLAsset(url: narrationURL)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw SmartVideoError.invalidMedia("Thuyết minh không có track âm thanh.")
            }
            let fileSeconds = try await asset.load(.duration).seconds
            let at = min(max(0, narrationStart), duration)
            let take = min(fileSeconds, duration - at)
            if take > 0.04 {
                guard let destination = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else { throw SmartVideoError.cannotCreateWriter }
                try destination.insertTimeRange(CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: take, preferredTimescale: 600)
                ), of: source, at: CMTime(seconds: at, preferredTimescale: 600))
                let parameters = AVMutableAudioMixInputParameters(track: destination)
                parameters.setVolume(
                    min(1, max(0, narrationVolume)),
                    at: CMTime(seconds: at, preferredTimescale: 600)
                )
                mixParameters.append(parameters)
            }
        }

        mixParameters.append(contentsOf: try await SoundEffectsMixer.add(
            effects, to: composition, timelineDuration: total
        ))
        guard !mixParameters.isEmpty else {
            throw SmartVideoError.invalidMedia(
                "Chưa có nhạc, thuyết minh hoặc SFX để nghe thử."
            )
        }
        let item = AVPlayerItem(asset: composition)
        let mix = AVMutableAudioMix()
        mix.inputParameters = mixParameters
        item.audioMix = mix
        return item
    }
}
