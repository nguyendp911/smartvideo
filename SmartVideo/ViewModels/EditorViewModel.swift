import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [TimelineClip] = []
    @Published var photoExportSettings = PhotoExportSettings()
    @Published var isExportingPhoto = false
    @Published var photoExportStatus = ""
    @Published var exportedPhotoURL: URL?
    @Published var exportedPhotoFiles: [URL] = []
    @Published var photoBatchZIPURL: URL?

    @Published var isRunningAIAutoCreator = false
    @Published var aiAutoCreatorStatus = ""
    @Published var aiAutoCreatorPlan: AIAutoCreationPlan?

    @Published var photoPresetFeedback = ""
    @Published var photoAutoPresetPlan: [PhotoAutoPresetProposal] = []
    @Published var isScanningPhotoPresets = false
    @Published var photoAutoPresetStatus = ""
    var photoPresetScanTask: Task<Void, Never>?

    var copiedPhotoPreset: (recipe: PhotoPreset, intensity: Double)?
    var hasCopiedPhotoPreset: Bool { copiedPhotoPreset != nil }

    @Published var imageOverlays: [ImageOverlayClip] = []
    @Published var isTrackingFace = false
    @Published var faceTrackingMessage: String?
    @Published var isTrackingObject = false
    @Published var objectTrackingMessage: String?
    @Published var videoOverlays: [VideoOverlayClip] = []
    @Published var textOverlays: [TextOverlayClip] = []
    @Published var mockupOverlays: [MockupOverlayClip] = []
    @Published var soundEffects: [SoundEffectClip] = []
    @Published var musicRegions: [SoundEffectClip] = []
    @Published var musicRegionMode = false
    @Published var isImportingMusicRegion = false
    var copiedMusicRegion: SoundEffectClip?
    @Published var isImportingSoundEffects = false
    @Published var isDetectingBeats = false
    @Published var musicBeatSourceTimes: [Double] = []
    @Published var detectedTempoBPM: Double = 0
    @Published var beatConfidence: Double = 0
    @Published var beatScanStart: Double = 0

    /// Mapped to the video timeline (not source media clock).
    var timelineBeatMarkers: [Double] {
        guard !musicRegionMode,
              !musicBeatSourceTimes.isEmpty, musicDuration > 0, totalDuration > 0 else {
            return []
        }
        let start = min(max(0, musicStartSeconds), musicDuration)
        let segment = min(max(0, musicDuration - start),
                          musicHighlightDuration > 0 ?
                            musicHighlightDuration : musicDuration)
        guard segment > 0.1 else { return [] }
        let count = repeatShortMusic ?
            min(60, max(1, Int(ceil(totalDuration / segment)))) : 1
        var markers: [Double] = []
        for iteration in 0..<count {
            let offset = Double(iteration) * segment
            for beat in musicBeatSourceTimes {
                let relative = beat - start
                if relative >= 0, relative < segment {
                    let timeline = relative + offset + musicTimelineOffset
                    if timeline <= totalDuration {
                        markers.append(timeline)
                    }
                }
            }
        }
        return markers.sorted()
    }
    @Published var timelineSecond: Double = 0
    @Published var timelineZoom: Double = 1.0
    @Published var projectName: String = "Dự án mới"
    @Published var projectID: UUID = UUID()
    @Published var availableProjects: [ProjectListItem] = []
    @Published var savedProjectNames: [String] = []
    @Published var lastSaveMessage: String?
    struct TimelineSnapshot {
        var clips: [TimelineClip]
        var subtitles: [SubtitleCue]
        var textOverlays: [TextOverlayClip]
        var imageOverlays: [ImageOverlayClip]
        var videoOverlays: [VideoOverlayClip]
        var vfxStartTime: Double
        var vfxEndTime: Double
        var soundEffects: [SoundEffectClip]
        var musicRegions: [SoundEffectClip]
        var mockupOverlays: [MockupOverlayClip]
        var musicRegionMode: Bool
        var projectID: UUID
        var musicTimelineOffset: Double
        var voiceoverOffset: Double
        var musicVolumeKeyframes: [AudioGainKeyframe]
        var voiceVolumeKeyframes: [AudioGainKeyframe]
    }
    var undoStack: [TimelineSnapshot] = []
    var redoStack: [TimelineSnapshot] = []
    var currentSnapshot: TimelineSnapshot {
        TimelineSnapshot(
            clips: clips,
            subtitles: subtitles, textOverlays: textOverlays,
            imageOverlays: imageOverlays, videoOverlays: videoOverlays,
            vfxStartTime: vfxStartTime, vfxEndTime: vfxEndTime,
            soundEffects: soundEffects,
            musicRegions: musicRegions, mockupOverlays: mockupOverlays,
            musicRegionMode: musicRegionMode,
            projectID: projectID,
            musicTimelineOffset: musicTimelineOffset,
            voiceoverOffset: voiceoverOffset,
            musicVolumeKeyframes: musicVolumeKeyframes,
            voiceVolumeKeyframes: voiceVolumeKeyframes
        )
    }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    @Published var subtitles: [SubtitleCue] = []
    @Published var subtitleAppearance = SubtitleAppearance()
    @Published var autoCaptionSource: AutoCaptionSource = .narration
    @Published var autoCaptionLanguage: AutoCaptionLanguage = .vietnamese
    @Published var allowAppleSpeechService = false
    @Published var replaceExistingAutoCaptions = false
    @Published var processLongAutoCaptions = true
    @Published var isGeneratingAutoCaptions = false
    @Published var autoCaptionStatus = ""
    let autoCaptionSpeech = AutoCaptionSpeech()
    @Published var transition: VideoTransition = .cut
    @Published var transitionSeconds: Double = 0.45
    @Published var vfxPresets: Set<VFXPreset> = []
    @Published var appliedStudioPresetID: String?
    @Published var studioPresetMessage: String = ""

    struct PresetUndo {
        let clips: [TimelineClip]
        let vfx: Set<VFXPreset>
        let strength: Double
        let coverage: VFXCoverage
        let start: Double
        let end: Double
        let transition: VideoTransition
        let transitionSeconds: Double
        let subtitleStyle: SubtitleAppearance
        let previousPresetID: String?
    }
    var studioPresetUndo: PresetUndo?
    var canUndoStudioPreset: Bool { studioPresetUndo != nil }
    @Published var vfxIntensity: Double = 0.30
    @Published var vfxCoverage: VFXCoverage = .videoOnly
    @Published var vfxStartTime: Double = 0
    @Published var vfxEndTime: Double = 0
    @Published var subtitleX: Double = 0.5
    @Published var subtitleY: Double = 0.83
    @Published var musicURL: URL?
    @Published var originalMusicURL: URL?
    @Published var musicMasteringSettings = VoiceMasteringSettings(
        bassDB: 0, midDB: 0, trebleDB: 0, compressorThreshold: -20,
        compressorRatio: 1.0, noiseGateEnabled: false,
        noiseGateThreshold: -46, outputGainDB: 0
    )
    @Published var isProcessingMusic = false
    @Published var musicProcessingMessage = ""
    @Published var voiceoverURL: URL?
    @Published var originalVoiceoverURL: URL?
    @Published var masteringSettings = VoiceMasteringSettings()
    @Published var isMasteringVoice = false
    @Published var masteringMessage = ""
    @Published var musicVolume: Float = 0.38
    @Published var musicStartSeconds: Double = 0
    @Published var musicTimelineOffset: Double = 0
    @Published var musicVolumeKeyframes: [AudioGainKeyframe] = []
    @Published var voiceVolumeKeyframes: [AudioGainKeyframe] = []
    @Published var musicDuration: Double = 0
    @Published var isImportingAudio = false
    @Published var isScanningMusic = false
    @Published var musicHighlightDuration: Double = 0
    @Published var voiceoverOffset: Double = 0
    @Published var voiceoverVolume: Float = 1
    @Published var voiceoverDuration: Double = 0
    @Published var stripMetadata: Bool = true
    @Published var musicHighlightLength: Double = 20
    @Published var musicHighlights: [MusicHighlight] = []
    @Published var exportedMusicHighlightURL: URL?
    @Published var isExportingMusicHighlight = false
    @Published var isAnalyzingMusicHighlights = false
    @Published var hook3sSuggestions: [Hook3sSuggestion] = []
    @Published var hook3sSourceClipID: UUID?
    @Published var hook3sStatus = ""
    @Published var isFindingHook3s = false
    @Published var isAutoTuningEnhance = false
    @Published var autoEnhanceStatus = ""
    struct HookInsertionBackup {
        let clips: [TimelineClip]
        let subtitles: [SubtitleCue]
        let text: [TextOverlayClip]
        let images: [ImageOverlayClip]
        let videos: [VideoOverlayClip]
        let mockups: [MockupOverlayClip]
        let sounds: [SoundEffectClip]
        let musicRegions: [SoundEffectClip]
        let musicOffset: Double
        let voiceOffset: Double
        let vfxStart: Double
        let vfxEnd: Double
        let timelineSecond: Double
    }
    var hook3sBackup: HookInsertionBackup?
    @Published var videoHighlights: [VideoHighlight] = []
    @Published var analyzedClipID: UUID?
    @Published var isAnalyzingVideoHighlights = false
    @Published var previousTimeline: [TimelineClip]?
    @Published var aiVisualReport: AIVisualReport?
    @Published var aiVisualClipID: UUID?
    @Published var aiVisualInstructions = ""
    @Published var aiVisualStatus = ""
    @Published var isAnalyzingVisualScenes = false
    @Published var aiRevoiceDraft: [SubtitleCue] = []
    @Published var aiGeminiModels: [GeminiAvailableModel] = []
    @Published var isLoadingGeminiModels = false
    @Published var aiGeminiModelStatus = ""
    @Published var aiGeminiModelName = ""
    @Published var aiRevoiceStyle = "Kể chuyện tự nhiên"
    @Published var aiRevoiceLanguage = "Tiếng Việt"
    @Published var aiRevoiceInstructions = ""
    @Published var isRewritingWithGemini = false
    @Published var isGeneratingSyncedRevoice = false
    @Published var aiRevoiceStatus = ""
    @Published var narrationText = ""
    @Published var narratorVoiceID: String = ""
    @Published var narratorTone: NarrationTone = .natural
    @Published var narratorRate: Float = 1.0
    @Published var narratorPitch: Float = 1.0
    @Published var silenceThreshold: Double = -39
    @Published var silenceGap: Double = 0.45
    @Published var isRemovingSilence = false
    @Published var lastSilenceRemoved: Double?
    @Published var aiPublishingVariants: [AIMetadataDraft] = []
    @Published var isGeneratingPublishingVariants = false
    @Published var aiMetadataDraft: AIMetadataDraft?
    @Published var aiMetadataStyle = "Tự nhiên, chuyên nghiệp"
    @Published var aiMetadataInstructions = ""
    @Published var aiMetadataStatus = ""
    @Published var isGeneratingAIMetadata = false
    @Published var metadata = ExportMetadata()
    @Published var addCustomMetadata = false
    @Published var musicFadeIn: Double = 0.3
    @Published var musicFadeOut: Double = 1.2
    @Published var separatedBackgroundURL: URL?
    @Published var isSeparatingAudio = false
    @Published var separationStatus = ""
    @Published var isGeneratingGeminiSpeech = false
    @Published var geminiSpeechModelName = ""
    @Published var geminiSpeechVoice = "Kore"
    @Published var geminiSpeechStyle = "Giọng tự nhiên, ấm áp"
    @Published var geminiSpeechStatus = ""
    @Published var isGeneratingNarration = false
    @Published var repeatShortMusic = true
    @Published var keepOriginalAudio = true
    @Published var quality: RenderQuality = .fullHD
    @Published var canvas: CanvasFormat = .portrait
    @Published var contentMode: CanvasContentMode = .fit
    @Published var isImporting = false
    @Published var isCreatingFreezeFrame = false
    @Published var isExporting = false
    @Published var isRenderingPreview = false
    @Published var renderedPreviewURL: URL?
    @Published var exportedURL: URL?
    @Published var errorText: String?
    @Published var didSaveToPhotos = false

    var totalDuration: Double {
        let raw = clips.reduce(0) { $0 + $1.renderedDuration }
        guard transition != .cut, clips.count > 1 else { return raw }
        let overlaps = zip(clips, clips.dropFirst()).reduce(0.0) { total, pair in
            total + min(transitionSeconds,
                        pair.0.renderedDuration * 0.24,
                        pair.1.renderedDuration * 0.24)
        }
        return max(0, raw - overlaps)
    }

}
