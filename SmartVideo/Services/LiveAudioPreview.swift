import Foundation
import AVFoundation
import Combine

/// Lightweight synchronous, on-device audio monitor for the *quick* timeline
/// preview. This is not the final mix (which is built by VideoRenderer).
/// The editor's 80ms transport clock drives positions in GLOBAL project time.
@MainActor
final class LiveAudioPreview: ObservableObject {
    @Published private(set) var warning: String?

    private var music: AVAudioPlayer?
    private var narration: AVAudioPlayer?
    private var effects: [UUID: AVAudioPlayer] = [:]
    private var loadedMusicURL: URL?
    private var loadedNarrationURL: URL?
    private var loadedEffects: [UUID: URL] = [:]

    func invalidate() {
        pause()
        music = nil
        narration = nil
        effects.removeAll()
        loadedMusicURL = nil
        loadedNarrationURL = nil
        loadedEffects.removeAll()
        warning = nil
    }

    func pause() {
        music?.pause()
        narration?.pause()
        for player in effects.values { player.pause() }
    }

    /// Check source URLs lazily, without decoding files on every 80ms tick.
    private func prepare(
        musicURL: URL?, narrationURL: URL?, soundEffects: [SoundEffectClip]
    ) {
        if loadedMusicURL != musicURL {
            music?.stop()
            loadedMusicURL = musicURL
            music = makePlayer(url: musicURL, name: "nhạc nền")
        }
        if loadedNarrationURL != narrationURL {
            narration?.stop()
            loadedNarrationURL = narrationURL
            narration = makePlayer(url: narrationURL, name: "thuyết minh")
        }
        let current = Dictionary(uniqueKeysWithValues:
            soundEffects.prefix(12).map { ($0.id, $0.fileURL) }
        )
        for (id, player) in effects where current[id] != loadedEffects[id] {
            player.stop()
            effects.removeValue(forKey: id)
        }
        for (id, url) in current where loadedEffects[id] != url {
            if let player = makePlayer(url: url, name: "âm FX") {
                effects[id] = player
            }
        }
        loadedEffects = current
    }

    private func makePlayer(url: URL?, name: String) -> AVAudioPlayer? {
        guard let url else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            guard player.prepareToPlay() else {
                warning = "Không mở được file \(name)."
                return nil
            }
            player.volume = 0
            return player
        } catch {
            warning = "Không mở được \(name): \(error.localizedDescription)"
            return nil
        }
    }

    /// Called by EditorView only while the global preview is truly moving.
    /// Pause immediately whenever video buffering, seeking or stopping.
    func sync(
        at timeline: Double, model: EditorViewModel,
        enabled: Bool, actuallyPlaying: Bool
    ) {
        guard enabled && actuallyPlaying,
              timeline.isFinite, timeline >= 0 else {
            pause()
            return
        }
        prepare(musicURL: model.musicURL, narrationURL: model.voiceoverURL,
                soundEffects: model.soundEffects)

        if let music {
            let end = LiveAudioPreviewMath.musicEnd(
                timelineEnd: model.totalDuration,
                fileDuration: music.duration,
                start: model.musicStartSeconds,
                highlightDuration: model.musicHighlightDuration,
                repeats: model.repeatShortMusic
            )
            let offset = LiveAudioPreviewMath.musicOffset(
                timeline: timeline, fileDuration: music.duration,
                start: model.musicStartSeconds,
                highlightDuration: model.musicHighlightDuration,
                repeats: model.repeatShortMusic
            )
            let narrationEnd: Double? = narration.map {
                max(0, model.voiceoverOffset) + $0.duration
            }
            let gain = LiveAudioPreviewMath.musicGain(
                timeline: timeline, baseVolume: model.musicVolume,
                musicEnd: end, fadeIn: model.musicFadeIn,
                fadeOut: model.musicFadeOut,
                narrationStart: narration == nil ?
                    nil : max(0, model.voiceoverOffset),
                narrationEnd: narrationEnd
            )
            syncPlayer(music, offset: offset, volume: gain)
        }

        if let narration {
            let offset = LiveAudioPreviewMath.regionOffset(
                timeline: timeline, regionStart: model.voiceoverOffset,
                sourceStart: 0, duration: narration.duration
            )
            syncPlayer(narration, offset: offset,
                       volume: min(1, max(0, model.voiceoverVolume)))
        }

        for effect in model.soundEffects.prefix(12) {
            guard let player = effects[effect.id] else { continue }
            let validDuration = min(
                max(0, effect.duration),
                max(0, player.duration - effect.sourceStart),
                max(0, model.totalDuration - effect.start)
            )
            let offset = LiveAudioPreviewMath.regionOffset(
                timeline: timeline, regionStart: effect.start,
                sourceStart: effect.sourceStart, duration: validDuration
            )
            let envelope = LiveAudioPreviewMath.envelope(
                timeline: timeline, start: effect.start,
                duration: validDuration,
                fadeIn: effect.fadeIn, fadeOut: effect.fadeOut
            )
            let relative = timeline - effect.start
            let keyframeGain = AudioAutomationMath.factor(
                at: relative / max(0.05, validDuration),
                frames: effect.volumeKeyframes
            )
            let gain: Float = effect.muted ? 0 :
                min(1, max(0, effect.volume)) * envelope * keyframeGain
            syncPlayer(player, offset: offset, volume: gain)
        }
    }

    private func syncPlayer(
        _ player: AVAudioPlayer, offset: Double?, volume: Float
    ) {
        guard let offset, offset.isFinite, offset >= 0,
              offset < player.duration, volume > 0.0001 else {
            player.pause()
            return
        }
        player.volume = volume.isFinite ? min(1, max(0, volume)) : 0
        if !player.isPlaying {
            player.currentTime = offset
            _ = player.play()
        } else if abs(player.currentTime - offset) > 0.23 {
            // Avoid audible micro-seeks on each tick; jump only after drift,
            // a slider edit or a looping/highlight segment boundary.
            player.currentTime = offset
        }
    }
}
