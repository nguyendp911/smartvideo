import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Local rhythm detection and SFX synchronization

    func analyzeMusicBeats() {
        guard let url = musicURL, !isDetectingBeats else {
            if musicURL == nil {
                errorText = "Hãy chọn nhạc MP3/M4A trong Âm thanh trước."
            }
            return
        }
        isDetectingBeats = true
        musicBeatSourceTimes = []
        detectedTempoBPM = 0
        beatConfidence = 0
        let sourceStart = musicStartSeconds
        let segment = musicHighlightDuration
        Task {
            defer { isDetectingBeats = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await MusicBeatAnalyzer.analyze(
                        url: url, start: sourceStart,
                        scanDuration: segment > 0 ? min(segment, 90) : 90
                    )
                }.value
                guard musicURL == url else { return }
                musicBeatSourceTimes = result.sourceTimes
                detectedTempoBPM = result.tempoBPM
                beatConfidence = result.confidence
                beatScanStart = sourceStart
            } catch {
                errorText = "Không phân tích được nhịp MP3: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func snapSoundToNearestBeat(_ id: UUID) -> Bool {
        guard let index = soundEffects.firstIndex(where: { $0.id == id }) else {
            return false
        }
        guard !timelineBeatMarkers.isEmpty else {
            errorText = "Hãy bấm Phân tích nhịp trước khi căn SFX."
            return false
        }
        let current = soundEffects[index].start
        guard let nearest = timelineBeatMarkers.min(by: {
            abs($0 - current) < abs($1 - current)
        }) else { return false }
        soundEffects[index].start = min(
            max(0, nearest), max(0, totalDuration - 0.1)
        )
        return true
    }

    func snapAllSoundsToBeats() {
        guard !timelineBeatMarkers.isEmpty else {
            errorText = "Hãy phân tích nhạc để có các mốc nhịp trước."
            return
        }
        for effect in soundEffects {
            _ = snapSoundToNearestBeat(effect.id)
        }
    }
    // MARK: - Independent sound-effect tracks

    func importSoundEffect(from sourceURL: URL) {
        guard !isImportingSoundEffects else { return }
        guard !clips.isEmpty, soundEffects.count < 12 else {
            errorText = clips.isEmpty ?
                "Cần nhập clip video/ảnh trước khi chèn âm thanh." :
                "Dự án giới hạn tối đa 12 track hiệu ứng âm thanh."
            return
        }
        isImportingSoundEffects = true
        do {
            let local = try copyScoped(sourceURL, fallbackExtension: "m4a")
            Task {
                defer { isImportingSoundEffects = false }
                do {
                    let asset = AVURLAsset(url: local)
                    guard !(try await asset.loadTracks(
                        withMediaType: .audio
                    )).isEmpty else {
                        throw SmartVideoError.invalidMedia(
                            "Không tìm thấy âm thanh trong file."
                        )
                    }
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite && duration >= 0.1 else {
                        throw SmartVideoError.invalidMedia(
                            "Tệp âm thanh có thời lượng không hợp lệ."
                        )
                    }
                    checkpoint()
                    soundEffects.append(SoundEffectClip.create(
                        url: local, audioDuration: duration,
                        timelineStart: timelineSecond, timelineEnd: totalDuration
                    ))
                } catch {
                    try? FileManager.default.removeItem(at: local)
                    errorText = "Không nhập được SFX: \(error.localizedDescription)"
                }
            }
        } catch {
            isImportingSoundEffects = false
            errorText = "Không đọc được tệp SFX: \(error.localizedDescription)"
        }
    }

    func addBuiltInSound(_ preset: BuiltInSoundEffect) {
        guard !clips.isEmpty, soundEffects.count < 12 else {
            errorText = clips.isEmpty ?
                "Hãy thêm video hoặc ảnh trước khi sử dụng SFX." :
                "Tối đa 12 track SFX."
            return
        }
        let at = timelineSecond
        let total = totalDuration
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try BuiltInSoundEffects.create(preset)
                }.value
                if soundEffects.count < 12 {
                    let asset = AVURLAsset(url: url)
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite && duration > 0 else {
                        throw SmartVideoError.invalidMedia(
                            "Không tạo được âm thanh mẫu."
                        )
                    }
                    checkpoint()
                    soundEffects.append(SoundEffectClip.create(
                        url: url, audioDuration: duration,
                        timelineStart: at, timelineEnd: total
                    ))
                }
            } catch {
                errorText = "Không tạo được SFX: \(error.localizedDescription)"
            }
        }
    }

    func removeSoundEffect(_ id: UUID) {
        guard soundEffects.contains(where: { $0.id == id }) else { return }
        checkpoint()
        soundEffects.removeAll { $0.id == id }
    }

    func moveSoundEffectToPlayhead(_ id: UUID) {
        guard let index = soundEffects.firstIndex(where: { $0.id == id }) else {
            return
        }
        checkpoint()
        soundEffects[index].start = min(
            max(0, timelineSecond), max(0, totalDuration - 0.1)
        )
    }

    /// Global project position. Set recordUndo=false while dragging after
    /// a single beginSoundEffectsEdit checkpoint in the gesture.
    func moveSoundEffect(
        _ id: UUID, to second: Double,
        recordUndo: Bool = true
    ) {
        guard let index = soundEffects.firstIndex(where: { $0.id == id }),
              second.isFinite else { return }
        let cap = max(0, totalDuration - max(0.1, soundEffects[index].duration))
        let target = min(cap, max(0, second))
        guard abs(soundEffects[index].start - target) > 0.0001 else { return }
        if recordUndo { checkpoint() }
        soundEffects[index].start = target
    }

    @discardableResult
    func duplicateSoundEffect(_ id: UUID) -> UUID? {
        guard soundEffects.count < 12,
              let index = soundEffects.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        checkpoint()
        var duplicate = soundEffects[index]
        duplicate.id = UUID()
        duplicate.start = min(
            max(0, soundEffects[index].end), max(0, totalDuration - 0.1)
        )
        soundEffects.insert(duplicate, at: index + 1)
        return duplicate.id
    }
    // MARK: - Interactive sound FX waveform & volume automation

    /// Add a keyframe to the currently selected SFX at the GLOBAL playhead.
    /// A keyframe changes gain relative to the clip's master volume.
    @discardableResult
    func addSoundVolumeKeyframe(_ id: UUID) -> UUID? {
        guard let index = soundEffects.firstIndex(where: { $0.id == id })
        else { return nil }
        let effect = soundEffects[index]
        let relative = timelineSecond - effect.start
        guard relative >= 0 && relative <= effect.duration else {
            errorText = "Đặt con trỏ trong khoảng thời gian của âm FX trước."
            return nil
        }
        let p = AudioAutomationMath.clampProgress(
            relative / max(0.1, effect.duration)
        )
        if let existing = effect.volumeKeyframes.first(where: {
            abs($0.progress - p) < 0.012
        }) { return existing.id }
        guard effect.volumeKeyframes.count < 16 else {
            errorText = "Giới hạn 16 điểm âm lượng mỗi track FX."
            return nil
        }
        let value = AudioAutomationMath.factor(
            at: p, frames: effect.volumeKeyframes
        )
        let key = AudioGainKeyframe(progress: p, gain: value)
        checkpoint()
        soundEffects[index].volumeKeyframes = AudioAutomationMath.normalized(
            effect.volumeKeyframes + [key]
        )
        return key.id
    }

    func updateSoundVolumeKeyframe(
        _ effectID: UUID, frameID: UUID, gain: Float
    ) {
        guard let index = soundEffects.firstIndex(where: {
            $0.id == effectID
        }), let point = soundEffects[index].volumeKeyframes.firstIndex(
            where: { $0.id == frameID }
        ) else { return }
        let safe = AudioAutomationMath.clampGain(gain)
        if soundEffects[index].volumeKeyframes[point].gain != safe {
            soundEffects[index].volumeKeyframes[point].gain = safe
        }
    }

    /// Drag a keyframe's horizontal time and vertical volume directly on
    /// the multi-track lane. Preserve ordering and identity of every node.
    func moveSoundVolumeKeyframe(
        _ effectID: UUID, frameID: UUID,
        progress: Double, gain: Float
    ) {
        guard let index = soundEffects.firstIndex(where: {
            $0.id == effectID
        }), let node = soundEffects[index].volumeKeyframes.firstIndex(
            where: { $0.id == frameID }
        ) else { return }
        let frames = soundEffects[index].volumeKeyframes
        let lower = node == 0 ? 0 :
            min(1, frames[node - 1].progress + 0.01)
        let upper = node == frames.count - 1 ? 1 :
            max(0, frames[node + 1].progress - 0.01)
        soundEffects[index].volumeKeyframes[node].progress =
            min(upper, max(lower,
                AudioAutomationMath.clampProgress(progress)))
        soundEffects[index].volumeKeyframes[node].gain =
            AudioAutomationMath.clampGain(gain)
    }

    func deleteSoundVolumeKeyframe(_ effectID: UUID, frameID: UUID) {
        guard let index = soundEffects.firstIndex(where: {
            $0.id == effectID
        }) else { return }
        guard soundEffects[index].volumeKeyframes.contains(where: {
            $0.id == frameID
        }) else { return }
        checkpoint()
        soundEffects[index].volumeKeyframes.removeAll {
            $0.id == frameID
        }
    }

    func resetSoundVolumeKeyframes(_ id: UUID) {
        guard let index = soundEffects.firstIndex(where: {
            $0.id == id
        }) else { return }
        guard !soundEffects[index].volumeKeyframes.isEmpty else { return }
        checkpoint()
        soundEffects[index].volumeKeyframes = []
    }

    /// Split one SFX region at the playhead without re-encoding its source.
    /// The keyframe curve is remapped to both halves with edge anchors.
    @discardableResult
    func splitSoundEffectAtPlayhead(_ id: UUID) -> UUID? {
        guard soundEffects.count < 12,
              let index = soundEffects.firstIndex(where: { $0.id == id })
        else {
            errorText = "Không thể tách: tối đa 12 track FX."
            return nil
        }
        let source = soundEffects[index]
        let local = timelineSecond - source.start
        guard local >= 0.1 && source.duration - local >= 0.1 else {
            errorText = "Đặt con trỏ cách mép FX tối thiểu 0,1 giây."
            return nil
        }
        let p = local / source.duration
        checkpoint()
        var left = source
        var right = source
        left.duration = local
        left.fadeOut = 0
        right.id = UUID()
        right.start = source.start + local
        right.sourceStart = source.sourceStart + local
        right.duration = source.duration - local
        right.fadeIn = 0
        left.volumeKeyframes = AudioAutomationMath.slice(
            source.volumeKeyframes, start: 0, end: p
        )
        right.volumeKeyframes = AudioAutomationMath.slice(
            source.volumeKeyframes, start: p, end: 1
        )
        soundEffects.replaceSubrange(index...index, with: [left, right])
        return right.id
    }
}
