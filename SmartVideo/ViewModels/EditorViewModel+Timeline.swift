import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Precise, non-destructive timeline editing

    func checkpoint() {
        undoStack.append(currentSnapshot)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        objectWillChange.send()
    }

    /// An edit gesture should checkpoint once at its beginning, not once
    /// for every animation frame or slider change.
    func beginSoundEffectsEdit() {
        checkpoint()
    }

    func undoEdit() {
        guard let previous = undoStack.popLast(),
              previous.projectID == projectID else {
            undoStack.removeAll()
            redoStack.removeAll()
            return
        }
        redoStack.append(currentSnapshot)
        clips = previous.clips
        subtitles = previous.subtitles
        textOverlays = previous.textOverlays
        imageOverlays = previous.imageOverlays
        videoOverlays = previous.videoOverlays
        vfxStartTime = previous.vfxStartTime
        vfxEndTime = previous.vfxEndTime
        soundEffects = previous.soundEffects
        musicRegions = previous.musicRegions
        mockupOverlays = previous.mockupOverlays
        musicRegionMode = previous.musicRegionMode
        musicTimelineOffset = previous.musicTimelineOffset
        voiceoverOffset = previous.voiceoverOffset
        musicVolumeKeyframes = previous.musicVolumeKeyframes
        voiceVolumeKeyframes = previous.voiceVolumeKeyframes
        timelineSecond = min(timelineSecond, totalDuration)
        objectWillChange.send()
    }

    func redoEdit() {
        guard let next = redoStack.popLast(),
              next.projectID == projectID else {
            undoStack.removeAll()
            redoStack.removeAll()
            return
        }
        undoStack.append(currentSnapshot)
        clips = next.clips
        subtitles = next.subtitles
        textOverlays = next.textOverlays
        imageOverlays = next.imageOverlays
        videoOverlays = next.videoOverlays
        vfxStartTime = next.vfxStartTime
        vfxEndTime = next.vfxEndTime
        soundEffects = next.soundEffects
        musicRegions = next.musicRegions
        mockupOverlays = next.mockupOverlays
        musicRegionMode = next.musicRegionMode
        musicTimelineOffset = next.musicTimelineOffset
        voiceoverOffset = next.voiceoverOffset
        musicVolumeKeyframes = next.musicVolumeKeyframes
        voiceVolumeKeyframes = next.voiceVolumeKeyframes
        timelineSecond = min(timelineSecond, totalDuration)
        objectWillChange.send()
    }

    func timelineStart(of index: Int) -> Double {
        guard clips.indices.contains(index) else { return 0 }
        var cursor = 0.0
        for item in 0..<index {
            cursor += clips[item].renderedDuration
            if transition != .cut {
                cursor -= min(transitionSeconds,
                    clips[item].renderedDuration * 0.24,
                    clips[item + 1].renderedDuration * 0.24)
            }
        }
        return cursor
    }

    func clipAtTimeline(_ second: Double) -> (index: Int, local: Double)? {
        guard !clips.isEmpty else { return nil }
        let target = min(max(0, second), max(totalDuration - 0.001, 0))
        // An overlap is displayed using the incoming clip, as in the
        // default timeline compositor.
        for index in clips.indices.reversed() {
            let start = timelineStart(of: index)
            if target >= start {
                return (index, min(clips[index].renderedDuration,
                                    max(0, target - start)))
            }
        }
        return (0, 0)
    }

    /// Presets and custom points change rendered duration without altering
    /// original media. A preset change is a single undoable operation.
    func applySpeedCurve(_ preset: SpeedCurvePreset, to id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].kind == .video else { return }
        checkpoint()
        clips[index].speedCurve = SpeedCurveMath.normalized(preset.points)
        if !clips[index].speedCurve.isEmpty {
            clips[index].playbackSpeed = 1
        }
        timelineSecond = min(timelineSecond, totalDuration)
    }

    /// A five-node curve editor. Call beginSpeedCurveEdit() when a slider
    /// gesture begins so one gesture corresponds to one undo checkpoint.
    func beginSpeedCurveEdit() {
        checkpoint()
    }

    func changeSpeedCurveNode(_ id: UUID, at index: Int, to speed: Double) {
        guard let clipIndex = clips.firstIndex(where: { $0.id == id }),
              clips[clipIndex].kind == .video,
              clips[clipIndex].speedCurve.indices.contains(index),
              speed.isFinite else { return }
        clips[clipIndex].speedCurve[index].speed =
            min(SpeedCurveMath.maxSpeed,
                max(SpeedCurveMath.minSpeed, speed))
        timelineSecond = min(timelineSecond, totalDuration)
    }
    // MARK: - Clip source audio studio

    /// Called when the user starts a slider drag, so one gesture is one undo.
    func beginClipAudioEdit() {
        checkpoint()
    }

    func setClipAudioMuted(_ id: UUID, muted: Bool) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].kind == .video,
              clips[index].sourceAudioMuted != muted else { return }
        checkpoint()
        clips[index].sourceAudioMuted = muted
    }

    func resetClipAudio(_ id: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == id }),
              clips[index].kind == .video else { return }
        checkpoint()
        clips[index].sourceAudioMuted = false
        clips[index].sourceAudioVolume = 1
        clips[index].sourceAudioFadeIn = 0
        clips[index].sourceAudioFadeOut = 0
    }

    @discardableResult
    func splitClip(at second: Double) -> UUID? {
        guard let position = clipAtTimeline(second) else { return nil }
        let index = position.index
        let source = clips[index]
        let outputSeconds = source.renderedDuration
        let leftOutput = position.local
        // Prevent sub-frame/near-zero pieces.
        guard leftOutput >= 0.20, outputSeconds - leftOutput >= 0.20 else {
            errorText = "Đặt con trỏ cách mép đoạn ít nhất 0,2 giây rồi tách."
            return nil
        }

        checkpoint()
        var left = source
        var right = source
        right.id = UUID()
        if source.kind == .video {
            let leftSourceSeconds: Double
            if source.speedCurve.isEmpty {
                leftSourceSeconds = leftOutput * max(0.25, source.playbackSpeed)
            } else {
                leftSourceSeconds = SpeedCurveMath.sourceOffset(
                    atOutputSecond: leftOutput, sourceDuration: source.duration,
                    points: source.speedCurve
                )
            }
            left.duration = leftSourceSeconds
            right.startTime = source.startTime + leftSourceSeconds
            right.duration = max(0.1, source.duration - leftSourceSeconds)
            // A split does not add a new fade-out/fade-in at the cut.
            // Preserve fades on the two outer edges; the new pieces can
            // still be edited independently in Clip Audio Studio.
            left.sourceAudioFadeOut = 0
            right.sourceAudioFadeIn = 0
            if !source.speedCurve.isEmpty {
                let splitAt = leftSourceSeconds / max(0.001, source.duration)
                left.speedCurve = SpeedCurveMath.trimmed(
                    source.speedCurve, from: 0, to: splitAt
                )
                right.speedCurve = SpeedCurveMath.trimmed(
                    source.speedCurve, from: splitAt, to: 1
                )
            }
        } else {
            left.duration = leftOutput
            right.duration = max(0.1, source.duration - leftOutput)
        }
        clips.replaceSubrange(index...index, with: [left, right])
        return right.id
    }

    /// Extract an actual source frame, not a screenshot of the preview.
    /// The generated image becomes an editable timeline clip, so project
    /// persistence, export, undo/redo, and the existing still renderer work.
    /// A freeze is silent by design and never modifies its source video.
    @discardableResult
    func freezeFrame(clipID: UUID, atLocalSecond second: Double,
                     holdSeconds: Double = 1.5) async -> UUID? {
        guard !isCreatingFreezeFrame,
              let originalIndex = clips.firstIndex(where: { $0.id == clipID }),
              clips[originalIndex].kind == .video else {
            errorText = "Chọn một đoạn video để đóng băng khung hình."
            return nil
        }
        let source = clips[originalIndex]
        let startingProject = projectID
        let local = min(source.renderedDuration, max(0,
            second.isFinite ? second : 0))
        let frameSourceOffset = source.speedCurve.isEmpty
            ? local * max(0.25, source.playbackSpeed)
            : SpeedCurveMath.sourceOffset(
                atOutputSecond: local, sourceDuration: source.duration,
                points: source.speedCurve
            )
        let captureSecond = min(
            source.startTime + source.duration - 0.01,
            source.startTime + frameSourceOffset
        )
        isCreatingFreezeFrame = true
        defer { isCreatingFreezeFrame = false }

        do {
            let asset = AVURLAsset(url: source.fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // Keep memory usage manageable for iPhone 12 Pro Max.
            generator.maximumSize = CGSize(width: 1920, height: 1920)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02,
                                                             preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02,
                                                            preferredTimescale: 600)
            let (frame, _) = try await generator.image(
                at: CMTime(seconds: max(source.startTime, captureSecond),
                           preferredTimescale: 600)
            )
            guard let jpeg = UIImage(cgImage: frame).jpegData(
                compressionQuality: 0.96
            ) else {
                throw SmartVideoError.invalidMedia("Không thể mã hóa khung hình.")
            }
            let stillURL = try MediaStorage.storeImage(data: jpeg)

            // The user may have switched projects or edited this clip while
            // AVFoundation was extracting the frame. Never edit stale data.
            guard startingProject == projectID,
                  let index = clips.firstIndex(where: { $0.id == clipID }),
                  clips[index] == source else {
                try? FileManager.default.removeItem(at: stillURL)
                throw SmartVideoError.invalidMedia(
                    "Clip đã thay đổi. Vui lòng thực hiện lại."
                )
            }
            checkpoint()
            let hold = min(12, max(0.2, holdSeconds))
            let frozen = TimelineClip(
                kind: .image, fileURL: stillURL,
                duration: hold, originalDuration: hold,
                imageLook: source.imageLook,
                lookIntensity: source.lookIntensity,
                colorAdjustments: source.colorAdjustments,
                personBackground: source.personBackground,
                flipHorizontal: source.flipHorizontal,
                flipVertical: source.flipVertical
            )
            let freezeIndex: Int
            if local >= 0.2 && source.renderedDuration - local >= 0.2 {
                // Split by source time, preserving non-1x playback speed.
                let leftSourceSeconds = frameSourceOffset
                var left = source
                var right = source
                left.duration = leftSourceSeconds
                right.id = UUID()
                right.startTime = source.startTime + leftSourceSeconds
                right.duration = source.duration - leftSourceSeconds
                // Freeze inserts a silent still. Do not introduce extra
                // fades at the newly split clip edges.
                left.sourceAudioFadeOut = 0
                right.sourceAudioFadeIn = 0
                if !source.speedCurve.isEmpty {
                    let splitAt = leftSourceSeconds / max(0.001, source.duration)
                    left.speedCurve = SpeedCurveMath.trimmed(
                        source.speedCurve, from: 0, to: splitAt
                    )
                    right.speedCurve = SpeedCurveMath.trimmed(
                        source.speedCurve, from: splitAt, to: 1
                    )
                }
                clips.replaceSubrange(index...index, with: [left, frozen, right])
                freezeIndex = index + 1
            } else if local < 0.2 {
                clips.insert(frozen, at: index)
                freezeIndex = index
            } else {
                clips.insert(frozen, at: index + 1)
                freezeIndex = index + 1
            }
            timelineSecond = timelineStart(of: freezeIndex)
            return frozen.id
        } catch {
            errorText = "Không thể đóng băng khung hình: \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func duplicateClip(id: UUID) -> UUID? {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return nil }
        checkpoint()
        var copy = clips[index]
        copy.id = UUID()
        clips.insert(copy, at: index + 1)
        return copy.id
    }

    func removeClip(id: UUID) {
        guard clips.contains(where: { $0.id == id }) else { return }
        checkpoint()
        clips.removeAll { $0.id == id }
        timelineSecond = min(timelineSecond, totalDuration)
    }

    /// One-tap edit template using real motion and dissolve exports.
    /// This modifies project settings only and never touches original media.
}
