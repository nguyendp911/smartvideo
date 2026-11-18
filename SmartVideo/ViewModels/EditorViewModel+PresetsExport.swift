import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Curated professional preset studio

    var projectGradeIntensity: Double {
        clips.first?.lookIntensity ?? 1
    }

    func setProjectGradeIntensity(_ value: Double) {
        let strength = min(1, max(0, value))
        for index in clips.indices {
            clips[index].lookIntensity = strength
        }
    }

    func applyStudioPreset(_ preset: StudioPreset) {
        guard !clips.isEmpty else {
            errorText = "Hãy nhập ít nhất một clip ảnh hoặc video trước khi áp dụng preset."
            return
        }
        studioPresetUndo = PresetUndo(
            clips: clips, vfx: vfxPresets, strength: vfxIntensity,
            coverage: vfxCoverage, start: vfxStartTime, end: vfxEndTime,
            transition: transition, transitionSeconds: transitionSeconds,
            subtitleStyle: subtitleAppearance,
            previousPresetID: appliedStudioPresetID
        )
        // All settings are applied in memory and saved with the normal project.
        // Source images, videos, speech and music remain untouched.
        for index in clips.indices {
            clips[index].imageLook = preset.imageLook
            clips[index].lookIntensity = 1
            if clips[index].kind == .image {
                clips[index].imageMotion = preset.motion
            }
        }
        vfxPresets = Set(preset.effects)
        vfxIntensity = preset.intensity
        vfxCoverage = .videoOnly
        vfxStartTime = 0
        vfxEndTime = 0
        transition = preset.transition
        transitionSeconds = 0.42
        subtitleAppearance = preset.subtitleStyle.settings
        appliedStudioPresetID = preset.id
        studioPresetMessage = "Đã áp dụng \(preset.title) cho ảnh và video. " +
            "Màu được render vào từng khung video khi xuất MP4."
    }

    func undoStudioPreset() {
        guard let prior = studioPresetUndo else { return }
        clips = prior.clips
        vfxPresets = prior.vfx
        vfxIntensity = prior.strength
        vfxCoverage = prior.coverage
        vfxStartTime = prior.start
        vfxEndTime = prior.end
        transition = prior.transition
        transitionSeconds = prior.transitionSeconds
        subtitleAppearance = prior.subtitleStyle
        appliedStudioPresetID = prior.previousPresetID
        studioPresetUndo = nil
        studioPresetMessage = "Đã hoàn tác preset gần nhất."
    }

    @discardableResult
    func addStudioPresetTitle(_ preset: StudioPreset) -> UUID? {
        guard totalDuration >= 0.1 else {
            errorText = "Hãy nhập clip trước khi thêm tiêu đề."
            return nil
        }
        var item = TextOverlayClip()
        item.text = "NHẬP TIÊU ĐỀ"
        item.start = min(max(0, timelineSecond), max(0, totalDuration - 0.2))
        item.duration = min(3.2, max(0.12, totalDuration - item.start))
        item.startX = 0.5
        item.startY = 0.56
        item.endX = 0.5
        item.endY = 0.56
        item.fontSize = 64
        item.colorHex = preset.textColor
        item.opacity = 1
        item.useBackground = false
        item.easing = .easeInOut
        item.keyframes = preset.titleMotion.makeFrames(
            x: 0.5, y: 0.56, scale: 0.45, opacity: 1
        )
        textOverlays.append(item)
        studioPresetMessage = "Đã thêm tiêu đề \(preset.title). " +
            "Chạm vào lớp chữ để thay nội dung."
        return item.id
    }

    func applyCinematicPreset() {
        checkpoint()
        transition = .dissolve
        transitionSeconds = 0.45
        for index in clips.indices where clips[index].kind == .image {
            let motions: [ImageMotion] = [.zoomIn, .panRight, .zoomOut, .panLeft]
            clips[index].imageMotion = motions[index % motions.count]
            clips[index].imageLook = .cinematic
        }
    }

    func moveClip(id: UUID, delta: Int) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let to = index + delta
        guard clips.indices.contains(to) else { return }
        checkpoint()
        clips.swapAt(index, to)
    }

    func reorderClip(draggedID: UUID, before targetID: UUID) {
        guard let from = clips.firstIndex(where: { $0.id == draggedID }),
              let target = clips.firstIndex(where: { $0.id == targetID }),
              from != target else { return }
        checkpoint()
        let moved = clips.remove(at: from)
        let insertion = from < target ? target - 1 : target
        clips.insert(moved, at: max(0, min(insertion, clips.count)))
    }

    func export() { renderProject(previewOnly: false) }

    func renderSynchronizedPreview() { renderProject(previewOnly: true) }

    func renderProject(previewOnly: Bool) {
        guard !clips.isEmpty, !isExporting, !isRenderingPreview else { return }
        let previousPreview = renderedPreviewURL
        if previewOnly {
            isRenderingPreview = true
            renderedPreviewURL = nil
        } else {
            isExporting = true
            exportedURL = nil
            didSaveToPhotos = false
        }

        let workClips = clips
        let workImageOverlays = imageOverlays
        let workVideoOverlays = videoOverlays
        let workTextOverlays = textOverlays
        let workMockups = mockupOverlays
        let workSoundEffects = soundEffects
        let workMusicRegions = musicRegions
        let workMusicRegionMode = musicRegionMode
        let workTransition = transition
        let workTransitionSeconds = transitionSeconds
        let workVFX = VFXPreset.allCases.filter { vfxPresets.contains($0) }
        let workVFXIntensity = vfxIntensity
        let workVFXCoverage = vfxCoverage
        let workVFXStartTime = vfxStartTime
        let workVFXEndTime = vfxEndTime
        let workMusic = musicRegionMode ? nil : musicURL
        let workMusicVolume = musicVolume
        let workMusicStart = musicStartSeconds
        let workMusicOffset = musicTimelineOffset
        let workMusicFrames = musicVolumeKeyframes
        let workVoiceFrames = voiceVolumeKeyframes
        let workLoop = repeatShortMusic
        let workHighlightLength = musicHighlightDuration
        let workVoiceOffset = voiceoverOffset
        let workVoiceVolume = voiceoverVolume
        let workStripMetadata = stripMetadata
        let workMetadata = addCustomMetadata ? metadata : ExportMetadata()
        let workFadeIn = musicFadeIn
        let workFadeOut = musicFadeOut
        let workVoiceDuck = voiceDuck
        let workVoice = voiceoverURL
        let workSubtitles = subtitles
        let workSubtitleAppearance = subtitleAppearance
        let workSubtitleX = subtitleX
        let workSubtitleY = subtitleY
        let workKeepOriginal = keepOriginalAudio
        let workQuality: RenderQuality = previewOnly ? .hd : quality
        let workCanvas = canvas
        let workMode = contentMode

        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try await VideoRenderer().render(
                        clips: workClips,
                        imageOverlays: workImageOverlays,
                        videoOverlays: workVideoOverlays,
                        textOverlays: workTextOverlays,
                        mockupOverlays: workMockups,
                        soundEffects: workSoundEffects,
                        musicRegions: workMusicRegionMode ? workMusicRegions : [],
                        transition: workTransition,
                        transitionSeconds: workTransitionSeconds,
                        vfxPresets: workVFX,
                        vfxIntensity: workVFXIntensity,
                        vfxCoverage: workVFXCoverage,
                        vfxStartTime: workVFXStartTime,
                        vfxEndTime: workVFXEndTime,
                        musicURL: workMusic,
                        musicVolume: workMusicVolume,
                        musicStartSeconds: workMusicStart,
                        musicTimelineOffset: workMusicOffset,
                        musicVolumeKeyframes: workMusicFrames,
                        voiceVolumeKeyframes: workVoiceFrames,
                        repeatShortMusic: workLoop,
                        musicHighlightDuration: workHighlightLength,
                        voiceoverURL: workVoice,
                        voiceoverOffset: workVoiceOffset,
                        voiceoverVolume: workVoiceVolume,
                        subtitles: workSubtitles,
                        subtitleAppearance: workSubtitleAppearance,
                        subtitleX: workSubtitleX,
                        subtitleY: workSubtitleY,
                        keepOriginalAudio: workKeepOriginal,
                        quality: workQuality,
                        canvas: workCanvas,
                        contentMode: workMode,
                        stripMetadata: workStripMetadata,
                        exportMetadata: workMetadata,
                        musicFadeIn: workFadeIn,
                        musicFadeOut: workFadeOut,
                        voiceDuck: workVoiceDuck
                    )
                }.value
                if previewOnly {
                    if let prior = previousPreview, prior != url {
                        try? FileManager.default.removeItem(at: prior)
                    }
                    renderedPreviewURL = url
                } else {
                    exportedURL = url
                }
            } catch {
                errorText = (previewOnly ? "Preview thất bại: " : "Xuất video thất bại: ") +
                    error.localizedDescription
            }
            if previewOnly { isRenderingPreview = false }
            else { isExporting = false }
        }
    }

    func saveToPhotos() async {
        guard let exportedURL else { return }
        do {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                throw SmartVideoError.photoPermission
            }
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: exportedURL)
            }
            didSaveToPhotos = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}
