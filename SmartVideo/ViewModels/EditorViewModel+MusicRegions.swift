import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Multi-music regions (5.4)

    /// Legacy music remains in the project until the user explicitly chooses
    /// its mode. Only one music mode is audible in preview and MP4.
    func selectMusicRegionMode(_ enabled: Bool) {
        guard enabled != musicRegionMode else { return }
        checkpoint()
        musicRegionMode = enabled
    }

    /// Creates a non-destructive region from the current legacy background
    /// music, retaining the selected source trim and volume automation.
    @discardableResult
    func addCurrentMusicAsRegion() -> UUID? {
        guard let musicURL, musicDuration > 0.1,
              !clips.isEmpty, musicRegions.count < 12 else {
            errorText = "Chọn nhạc nền hợp lệ, thêm video và còn chỗ trống (tối đa 12 đoạn)."
            return nil
        }
        guard let region = MusicRegionEditMath.fromLegacy(
            url: musicURL, fileDuration: musicDuration,
            sourceStart: musicStartSeconds,
            highlightDuration: musicHighlightDuration,
            timelineStart: musicTimelineOffset,
            projectDuration: totalDuration,
            volume: musicVolume,
            fadeIn: musicFadeIn, fadeOut: musicFadeOut,
            frames: musicVolumeKeyframes
        ) else {
            errorText = "Đoạn nguồn quá ngắn hoặc thời lượng nhạc không hợp lệ."
            return nil
        }
        checkpoint()
        musicRegions.append(region)
        musicRegionMode = true
        return region.id
    }

    func importMusicRegion(from sourceURL: URL) {
        guard !isImportingMusicRegion,
              !clips.isEmpty, musicRegions.count < 12 else {
            errorText = "Cần có video và còn chỗ trống (tối đa 12 đoạn nhạc)."
            return
        }
        isImportingMusicRegion = true
        do {
            let local = try copyScoped(
                sourceURL, fallbackExtension: "m4a"
            )
            Task {
                defer { isImportingMusicRegion = false }
                do {
                    let asset = AVURLAsset(url: local)
                    guard !(try await asset.loadTracks(
                        withMediaType: .audio
                    )).isEmpty else {
                        throw SmartVideoError.invalidMedia(
                            "Tệp nhạc không có âm thanh."
                        )
                    }
                    let seconds = try await asset.load(.duration).seconds
                    guard seconds.isFinite && seconds > 0.1 else {
                        throw SmartVideoError.invalidMedia(
                            "Thời lượng nhạc không hợp lệ."
                        )
                    }
                    guard musicRegions.count < 12 else {
                        try? FileManager.default.removeItem(at: local)
                        return
                    }
                    var region = SoundEffectClip.create(
                        url: local, audioDuration: seconds,
                        timelineStart: timelineSecond,
                        timelineEnd: totalDuration
                    )
                    region.duration = min(
                        max(0.1, seconds),
                        max(0.1, totalDuration - region.start)
                    )
                    region.volume = 0.38
                    region.fadeIn = 0.20
                    region.fadeOut = 0.35
                    checkpoint()
                    musicRegions.append(region)
                    musicRegionMode = true
                } catch {
                    try? FileManager.default.removeItem(at: local)
                    errorText = "Không nhập được đoạn nhạc: \(error.localizedDescription)"
                }
            }
        } catch {
            isImportingMusicRegion = false
            errorText = "Không mở được nhạc từ Tệp: \(error.localizedDescription)"
        }
    }

    func moveMusicRegion(
        _ id: UUID, to second: Double,
        recordUndo: Bool = true
    ) {
        guard let index = musicRegions.firstIndex(where: {
            $0.id == id
        }), second.isFinite else { return }
        let region = musicRegions[index]
        let target = AudioTimelineMath.clampStart(
            second, duration: region.duration,
            projectDuration: totalDuration
        )
        guard abs(target - region.start) > 0.0001 else { return }
        if recordUndo { checkpoint() }
        musicRegions[index].start = target
    }

    @discardableResult
    func duplicateMusicRegion(_ id: UUID, at second: Double? = nil) -> UUID? {
        guard musicRegions.count < 12,
              let region = musicRegions.first(where: {
                  $0.id == id
              }) else { return nil }
        let next = MusicRegionEditMath.duplicate(
            region, at: second ?? region.end,
            projectDuration: totalDuration
        )
        checkpoint()
        musicRegions.append(next)
        musicRegionMode = true
        return next.id
    }

    func copyMusicRegion(_ id: UUID) {
        copiedMusicRegion = musicRegions.first(where: { $0.id == id })
    }

    @discardableResult
    func pasteMusicRegionAtPlayhead() -> UUID? {
        guard let copiedMusicRegion else {
            errorText = "Sao chép một đoạn nhạc trước khi dán."
            return nil
        }
        guard musicRegions.count < 12 else {
            errorText = "Tối đa 12 đoạn nhạc."
            return nil
        }
        let region = MusicRegionEditMath.duplicate(
            copiedMusicRegion, at: timelineSecond,
            projectDuration: totalDuration
        )
        checkpoint()
        musicRegions.append(region)
        musicRegionMode = true
        return region.id
    }

    @discardableResult
    func splitMusicRegionAtPlayhead(_ id: UUID) -> UUID? {
        guard musicRegions.count < 12,
              let index = musicRegions.firstIndex(where: {
                  $0.id == id
              }) else {
            errorText = "Tối đa 12 đoạn nhạc hoặc không tìm thấy đoạn."
            return nil
        }
        let original = musicRegions[index]
        guard let pieces = MusicRegionEditMath.split(
            original, at: timelineSecond
        ) else {
            errorText = "Đặt con trỏ cách hai mép đoạn nhạc ít nhất 0,1 giây."
            return nil
        }
        checkpoint()
        musicRegions.replaceSubrange(
            index...index, with: [pieces.left, pieces.right]
        )
        return pieces.right.id
    }

    func removeMusicRegion(_ id: UUID) {
        guard musicRegions.contains(where: { $0.id == id }) else { return }
        checkpoint()
        musicRegions.removeAll { $0.id == id }
        // Keep clip mode even if empty to avoid unexpectedly re-enabling
        // the legacy full-length music when the last clip is deleted.
    }

    @discardableResult
    func addMusicRegionKeyframe(_ id: UUID) -> UUID? {
        guard let index = musicRegions.firstIndex(where: {
            $0.id == id
        }) else { return nil }
        let region = musicRegions[index]
        let p = (timelineSecond - region.start) /
            max(0.1, region.duration)
        guard p >= 0 && p <= 1 else {
            errorText = "Đặt con trỏ nằm trong đoạn nhạc."
            return nil
        }
        if let existing = region.volumeKeyframes.first(where: {
            abs($0.progress - p) < 0.012
        }) { return existing.id }
        guard region.volumeKeyframes.count < 16 else {
            errorText = "Tối đa 16 keyframe cho mỗi đoạn nhạc."
            return nil
        }
        let gain = AudioAutomationMath.factor(
            at: p, frames: region.volumeKeyframes
        )
        let frame = AudioGainKeyframe(progress: p, gain: gain)
        checkpoint()
        musicRegions[index].volumeKeyframes = AudioAutomationMath.normalized(
            region.volumeKeyframes + [frame]
        )
        return frame.id
    }

    func moveMusicRegionKeyframe(
        _ id: UUID, frameID: UUID,
        progress: Double, gain: Float
    ) {
        guard let index = musicRegions.firstIndex(where: {
            $0.id == id
        }), let frameIndex = musicRegions[index].volumeKeyframes.firstIndex(
            where: { $0.id == frameID }
        ) else { return }
        let frames = musicRegions[index].volumeKeyframes
        let lower = frameIndex == 0 ?
            0 : frames[frameIndex - 1].progress + 0.01
        let upper = frameIndex == frames.count - 1 ?
            1 : frames[frameIndex + 1].progress - 0.01
        musicRegions[index].volumeKeyframes[frameIndex].progress =
            max(lower, min(upper, AudioAutomationMath.clampProgress(progress)))
        musicRegions[index].volumeKeyframes[frameIndex].gain =
            AudioAutomationMath.clampGain(gain)
    }

    func deleteMusicRegionKeyframe(_ id: UUID, frameID: UUID) {
        guard let index = musicRegions.firstIndex(where: {
            $0.id == id
        }), musicRegions[index].volumeKeyframes.contains(where: {
            $0.id == frameID
        }) else { return }
        checkpoint()
        musicRegions[index].volumeKeyframes.removeAll {
            $0.id == frameID
        }
    }
    // MARK: - Project music and narration keyframe automation

    func projectAudioStart(_ lane: ProjectAudioLane) -> Double {
        lane == .music ? musicTimelineOffset : voiceoverOffset
    }

    func projectAudioDuration(_ lane: ProjectAudioLane) -> Double {
        switch lane {
        case .music:
            return ProjectAudioTrackMath.musicDuration(
                projectDuration: totalDuration,
                timelineStart: musicTimelineOffset,
                fileDuration: musicDuration,
                sourceStart: musicStartSeconds,
                highlightDuration: musicHighlightDuration,
                repeats: repeatShortMusic
            )
        case .narration:
            return min(max(0, totalDuration - voiceoverOffset),
                       max(0, voiceoverDuration))
        }
    }

    func projectAudioFrames(_ lane: ProjectAudioLane) -> [AudioGainKeyframe] {
        lane == .music ? musicVolumeKeyframes : voiceVolumeKeyframes
    }

    func projectAudioMove(
        _ lane: ProjectAudioLane, to second: Double,
        recordUndo: Bool = true
    ) {
        guard second.isFinite else { return }
        let length: Double = lane == .music ?
            min(0.1, max(0.05, projectAudioDuration(lane))) :
            max(0.1, voiceoverDuration)
        let target = AudioTimelineMath.clampStart(
            second, duration: length, projectDuration: totalDuration
        )
        guard abs(projectAudioStart(lane) - target) > 0.0001 else {
            return
        }
        if recordUndo { checkpoint() }
        if lane == .music { musicTimelineOffset = target }
        else { voiceoverOffset = target }
    }

    @discardableResult
    func addProjectAudioKeyframe(_ lane: ProjectAudioLane) -> UUID? {
        let offset = projectAudioStart(lane)
        let length = projectAudioDuration(lane)
        guard length >= 0.1,
              timelineSecond >= offset,
              timelineSecond <= offset + length else {
            errorText = "Đặt con trỏ nằm trong đoạn nhạc/giọng đọc."
            return nil
        }
        let position = AudioAutomationMath.clampProgress(
            (timelineSecond - offset) / length
        )
        let frames = projectAudioFrames(lane)
        if let existing = frames.first(where: {
            abs($0.progress - position) <= 0.01
        }) { return existing.id }
        guard frames.count < 16 else {
            errorText = "Giới hạn 16 keyframe âm lượng cho mỗi track."
            return nil
        }
        let gain = AudioAutomationMath.factor(
            at: position, frames: frames
        )
        let key = AudioGainKeyframe(progress: position, gain: gain)
        checkpoint()
        let adjusted = AudioAutomationMath.normalized(frames + [key])
        if lane == .music { musicVolumeKeyframes = adjusted }
        else { voiceVolumeKeyframes = adjusted }
        return key.id
    }

    /// A drag starts with one checkpoint, then updates without undo churn.
    func moveProjectAudioKeyframe(
        _ lane: ProjectAudioLane, id: UUID,
        progress: Double, gain: Float
    ) {
        var frames = projectAudioFrames(lane)
        guard let index = frames.firstIndex(where: {
            $0.id == id
        }) else { return }
        let left = index == 0 ? 0 : frames[index - 1].progress + 0.01
        let right = index == frames.count - 1 ?
            1 : frames[index + 1].progress - 0.01
        frames[index].progress = max(left, min(right,
            AudioAutomationMath.clampProgress(progress)))
        frames[index].gain = AudioAutomationMath.clampGain(gain)
        if lane == .music { musicVolumeKeyframes = frames }
        else { voiceVolumeKeyframes = frames }
    }

    func removeProjectAudioKeyframe(
        _ lane: ProjectAudioLane, id: UUID
    ) {
        let frames = projectAudioFrames(lane)
        guard frames.contains(where: { $0.id == id }) else { return }
        checkpoint()
        let reduced = frames.filter { $0.id != id }
        if lane == .music { musicVolumeKeyframes = reduced }
        else { voiceVolumeKeyframes = reduced }
    }

    func clearProjectAudioKeyframes(_ lane: ProjectAudioLane) {
        guard !projectAudioFrames(lane).isEmpty else { return }
        checkpoint()
        if lane == .music { musicVolumeKeyframes = [] }
        else { voiceVolumeKeyframes = [] }
    }
}
