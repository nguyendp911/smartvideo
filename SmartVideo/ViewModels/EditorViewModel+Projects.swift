import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Local Projects

    func refreshProjects() {
        availableProjects = ProjectStore.list()
    }

    func saveProject() {
        do {
            let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                errorText = "Nhập tên dự án để lưu."
                return
            }
            let snapshot = SmartVideoProject(
                id: projectID, name: name, savedAt: Date(),
                clips: clips, imageOverlays: imageOverlays,
                videoOverlays: videoOverlays, textOverlays: textOverlays,
                soundEffects: soundEffects,
                beatSourceTimes: musicBeatSourceTimes,
                detectedTempoBPM: detectedTempoBPM,
                subtitles: subtitles,
                subtitleAppearance: subtitleAppearance,
                transition: transition.rawValue,
                transitionSeconds: transitionSeconds,
                canvas: canvas.rawValue, contentMode: contentMode.rawValue,
                quality: quality.rawValue,
                musicFileName: musicURL?.lastPathComponent,
                voiceFileName: voiceoverURL?.lastPathComponent,
                originalVoiceFileName: originalVoiceoverURL?.lastPathComponent,
                originalMusicFileName: originalMusicURL?.lastPathComponent,
                musicMasteringSettings: musicMasteringSettings,
                voiceMasteringSettings: masteringSettings,
                musicVolume: musicVolume,
                musicStartSeconds: musicStartSeconds,
                musicHighlightDuration: musicHighlightDuration,
                musicFadeIn: musicFadeIn, musicFadeOut: musicFadeOut,
                musicRepeat: repeatShortMusic,
                keepOriginalAudio: keepOriginalAudio,
                voiceOffset: voiceoverOffset, voiceVolume: voiceoverVolume,
                vfxPresets: VFXPreset.allCases.filter { vfxPresets.contains($0) }
                    .map(\.rawValue),
                vfxIntensity: vfxIntensity,
                vfxCoverage: vfxCoverage.rawValue,
                vfxStart: vfxStartTime, vfxEnd: vfxEndTime,
                subtitleX: subtitleX, subtitleY: subtitleY,
                stripMetadata: stripMetadata,
                addMetadata: addCustomMetadata, metadata: metadata,
                studioPresetID: appliedStudioPresetID,
                musicTimelineOffset: musicTimelineOffset,
                musicVolumeKeyframes: musicVolumeKeyframes,
                voiceVolumeKeyframes: voiceVolumeKeyframes,
                musicRegions: musicRegions,
                musicRegionMode: musicRegionMode,
                mockupOverlays: mockupOverlays,
                voiceDuck: voiceDuck
            )
            try ProjectStore.save(snapshot)
            projectName = name
            lastSaveMessage = "Đã lưu \(name)"
            refreshProjects()
        } catch {
            errorText = "Không lưu được dự án: \(error.localizedDescription)"
        }
    }

    func loadProject(_ id: UUID) {
        do {
            let p = try ProjectStore.load(id)
            let restoredClips = p.clips.map(ProjectStore.clipInMedia)
            let restoredMusic = ProjectStore.audioInMedia(p.musicFileName)
            let restoredOriginalMusic = ProjectStore.audioInMedia(p.originalMusicFileName)
            let restoredVoice = ProjectStore.audioInMedia(p.voiceFileName)
            let restoredOriginalVoice = ProjectStore.audioInMedia(p.originalVoiceFileName)
            let pipFiles = p.videoOverlays.map {
                MediaStorage.mediaDirectory.appendingPathComponent($0.fileURL.lastPathComponent)
            }
            let overlayFiles = p.imageOverlays.map {
                MediaStorage.mediaDirectory.appendingPathComponent($0.fileURL.lastPathComponent)
            }
            let textFillFiles = p.textOverlays.compactMap {
                $0.fillAssetURL.map { url in
                    MediaStorage.mediaDirectory.appendingPathComponent(
                        url.lastPathComponent
                    )
                }
            }
            let sfxFiles = p.soundEffects.map {
                MediaStorage.mediaDirectory.appendingPathComponent($0.fileURL.lastPathComponent)
            }
            let musicFiles = p.musicRegions.map {
                MediaStorage.mediaDirectory.appendingPathComponent($0.fileURL.lastPathComponent)
            }
            let allFiles = restoredClips.map(\.fileURL) +
                overlayFiles + textFillFiles + pipFiles + sfxFiles + musicFiles +
                [restoredMusic, restoredVoice, restoredOriginalVoice,
                 restoredOriginalMusic].compactMap { $0 }
            guard allFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw SmartVideoError.invalidMedia(
                    "Thiếu ảnh, video hoặc âm thanh gốc. Dự án cần các file trong Media của ứng dụng."
                )
            }
            // An undo must never restore media from another project.
            photoPresetScanTask?.cancel()
            photoAutoPresetPlan = []
            photoAutoPresetStatus = ""
            hook3sBackup = nil
            hook3sSuggestions = []
            undoStack.removeAll()
            redoStack.removeAll()
            projectID = p.id
            projectName = p.name
            appliedStudioPresetID = p.studioPresetID
            studioPresetUndo = nil
            studioPresetMessage = ""
            clips = restoredClips
            imageOverlays = p.imageOverlays.map {
                var overlay = $0
                overlay.fileURL = MediaStorage.mediaDirectory
                    .appendingPathComponent($0.fileURL.lastPathComponent)
                return overlay
            }
            videoOverlays = p.videoOverlays.map {
                var overlay = $0
                overlay.fileURL = MediaStorage.mediaDirectory
                    .appendingPathComponent($0.fileURL.lastPathComponent)
                return overlay
            }
            mockupOverlays = p.mockupOverlays
            textOverlays = p.textOverlays.map { text in
                var result = text
                if let url = result.fillAssetURL {
                    result.fillAssetURL = MediaStorage.mediaDirectory
                        .appendingPathComponent(url.lastPathComponent)
                }
                return result
            }
            musicBeatSourceTimes = p.beatSourceTimes
            detectedTempoBPM = p.detectedTempoBPM
            beatConfidence = 0
            soundEffects = p.soundEffects.map {
                var effect = $0
                effect.fileURL = MediaStorage.mediaDirectory.appendingPathComponent(
                    $0.fileURL.lastPathComponent
                )
                return effect
            }
            musicRegions = p.musicRegions.map {
                var item = $0
                item.fileURL = MediaStorage.mediaDirectory.appendingPathComponent(
                    $0.fileURL.lastPathComponent
                )
                return item
            }
            musicRegionMode = p.musicRegionMode
            voiceDuck = p.voiceDuck
            copiedMusicRegion = nil
            subtitles = p.subtitles
            subtitleAppearance = p.subtitleAppearance
            autoCaptionStatus = ""
            transition = VideoTransition.allCases.first {
                $0.rawValue == p.transition
            } ?? .cut
            transitionSeconds = p.transitionSeconds
            canvas = CanvasFormat.allCases.first {
                $0.rawValue == p.canvas
            } ?? .portrait
            contentMode = CanvasContentMode.allCases.first {
                $0.rawValue == p.contentMode
            } ?? .fit
            quality = RenderQuality.allCases.first {
                $0.rawValue == p.quality
            } ?? .fullHD
            musicURL = restoredMusic
            originalMusicURL = restoredOriginalMusic
            musicMasteringSettings = p.musicMasteringSettings
            musicProcessingMessage = ""
            renderedPreviewURL = nil
            voiceoverURL = restoredVoice
            originalVoiceoverURL = restoredOriginalVoice
            masteringSettings = p.voiceMasteringSettings
            masteringMessage = ""
            musicVolume = p.musicVolume
            musicStartSeconds = p.musicStartSeconds
            musicTimelineOffset = ProjectAudioTrackMath.safeStart(
                p.musicTimelineOffset, projectDuration: totalDuration
            )
            musicVolumeKeyframes = p.musicVolumeKeyframes
            voiceVolumeKeyframes = p.voiceVolumeKeyframes
            musicHighlightDuration = p.musicHighlightDuration
            musicFadeIn = p.musicFadeIn
            musicFadeOut = p.musicFadeOut
            repeatShortMusic = p.musicRepeat
            keepOriginalAudio = p.keepOriginalAudio
            voiceoverOffset = p.voiceOffset
            voiceoverVolume = p.voiceVolume
            vfxPresets = Set(VFXPreset.allCases.filter {
                p.vfxPresets.contains($0.rawValue)
            })
            vfxIntensity = p.vfxIntensity
            vfxCoverage = VFXCoverage.allCases.first {
                $0.rawValue == p.vfxCoverage
            } ?? .videoOnly
            vfxStartTime = p.vfxStart
            vfxEndTime = p.vfxEnd
            subtitleX = p.subtitleX
            subtitleY = p.subtitleY
            stripMetadata = p.stripMetadata
            addCustomMetadata = p.addMetadata
            metadata = p.metadata
            timelineSecond = 0
            // Refresh the MP3 duration asynchronously. Never put an
            // indefinite AVAsset duration into a Slider.
            if let restoredMusic {
                Task {
                    let seconds = try? await AVURLAsset(url: restoredMusic).load(.duration).seconds
                    if let seconds, seconds.isFinite, seconds > 0 {
                        musicDuration = seconds
                    }
                }
            } else {
                musicDuration = 0
            }
            lastSaveMessage = "Đã mở \(p.name)"
        } catch {
            errorText = "Không mở được dự án: \(error.localizedDescription)"
        }
    }

    func newProject() {
        photoPresetScanTask?.cancel()
        photoAutoPresetPlan = []
        photoAutoPresetStatus = ""
        hook3sBackup = nil
        hook3sSuggestions = []
        hook3sSourceClipID = nil
        undoStack.removeAll()
        redoStack.removeAll()
        projectID = UUID()
        projectName = "Dự án mới"
        appliedStudioPresetID = nil
        studioPresetUndo = nil
        studioPresetMessage = ""
        clips = []
        imageOverlays = []
        videoOverlays = []
        textOverlays = []
        mockupOverlays = []
        soundEffects = []
        musicRegions = []
        musicRegionMode = false
        voiceDuck = VoiceDuckSettings()
        copiedMusicRegion = nil
        musicBeatSourceTimes = []
        detectedTempoBPM = 0
        subtitles = []
        subtitleAppearance = SubtitleAppearance()
        autoCaptionStatus = ""
        musicURL = nil
        musicTimelineOffset = 0
        musicVolumeKeyframes = []
        voiceVolumeKeyframes = []
        originalMusicURL = nil
        musicMasteringSettings = VoiceMasteringSettings(
            bassDB: 0, midDB: 0, trebleDB: 0, compressorThreshold: -20,
            compressorRatio: 1, noiseGateEnabled: false,
            noiseGateThreshold: -46, outputGainDB: 0
        )
        musicProcessingMessage = ""
        renderedPreviewURL = nil
        voiceoverURL = nil
        voiceoverDuration = 0
        originalVoiceoverURL = nil
        masteringSettings = VoiceMasteringSettings()
        masteringMessage = ""
        musicDuration = 0
        timelineSecond = 0
        lastSaveMessage = "Đã tạo dự án trống"
    }

    func deleteProject(_ id: UUID) {
        do {
            try ProjectStore.delete(id)
            refreshProjects()
            if projectID == id { projectID = UUID() }
        } catch {
            errorText = "Không xóa được dự án: \(error.localizedDescription)"
        }
    }
}
