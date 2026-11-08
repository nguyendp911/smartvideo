import Foundation

/// A lightweight offline edit decision list (EDL). Assets remain in the
/// app's Documents/Media directory. No copy of the source media is made
/// when saving a project; project JSON references the existing files.
struct SmartVideoProject: Codable {
    var id: UUID
    var name: String
    var savedAt: Date
    var clips: [TimelineClip]
    var imageOverlays: [ImageOverlayClip]
    var videoOverlays: [VideoOverlayClip]
    var textOverlays: [TextOverlayClip]
    var soundEffects: [SoundEffectClip]
    var beatSourceTimes: [Double]
    var detectedTempoBPM: Double
    var subtitles: [SubtitleCue]
    var subtitleAppearance: SubtitleAppearance
    var transition: String
    var transitionSeconds: Double
    var canvas: String
    var contentMode: String
    var quality: String
    var musicFileName: String?
    var voiceFileName: String?
    var originalVoiceFileName: String?
    var originalMusicFileName: String?
    var musicMasteringSettings: VoiceMasteringSettings
    var voiceMasteringSettings: VoiceMasteringSettings
    var musicVolume: Float
    var musicStartSeconds: Double
    var musicHighlightDuration: Double
    var musicFadeIn: Double
    var musicFadeOut: Double
    var musicRepeat: Bool
    var keepOriginalAudio: Bool
    var voiceOffset: Double
    var voiceVolume: Float
    var vfxPresets: [String]
    var vfxIntensity: Double
    var vfxCoverage: String
    var vfxStart: Double
    var vfxEnd: Double
    var subtitleX: Double
    var subtitleY: Double
    var stripMetadata: Bool
    var addMetadata: Bool
    var metadata: ExportMetadata

    init(id: UUID, name: String, savedAt: Date, clips: [TimelineClip],
         imageOverlays: [ImageOverlayClip],
         videoOverlays: [VideoOverlayClip], textOverlays: [TextOverlayClip],
         soundEffects: [SoundEffectClip],
         beatSourceTimes: [Double], detectedTempoBPM: Double,
         subtitles: [SubtitleCue], subtitleAppearance: SubtitleAppearance,
         transition: String, transitionSeconds: Double, canvas: String,
         contentMode: String, quality: String, musicFileName: String?,
         voiceFileName: String?,
         originalVoiceFileName: String?,
         originalMusicFileName: String?,
         musicMasteringSettings: VoiceMasteringSettings,
         voiceMasteringSettings: VoiceMasteringSettings,
         musicVolume: Float, musicStartSeconds: Double,
         musicHighlightDuration: Double, musicFadeIn: Double,
         musicFadeOut: Double, musicRepeat: Bool, keepOriginalAudio: Bool,
         voiceOffset: Double, voiceVolume: Float, vfxPresets: [String],
         vfxIntensity: Double, vfxCoverage: String, vfxStart: Double,
         vfxEnd: Double, subtitleX: Double, subtitleY: Double,
         stripMetadata: Bool, addMetadata: Bool, metadata: ExportMetadata) {
        self.id = id
        self.name = name
        self.savedAt = savedAt
        self.clips = clips
        self.imageOverlays = imageOverlays
        self.videoOverlays = videoOverlays
        self.textOverlays = textOverlays
        self.soundEffects = soundEffects
        self.beatSourceTimes = beatSourceTimes
        self.detectedTempoBPM = detectedTempoBPM
        self.subtitles = subtitles
        self.subtitleAppearance = subtitleAppearance
        self.transition = transition
        self.transitionSeconds = transitionSeconds
        self.canvas = canvas
        self.contentMode = contentMode
        self.quality = quality
        self.musicFileName = musicFileName
        self.voiceFileName = voiceFileName
        self.originalVoiceFileName = originalVoiceFileName
        self.originalMusicFileName = originalMusicFileName
        self.musicMasteringSettings = musicMasteringSettings
        self.voiceMasteringSettings = voiceMasteringSettings
        self.musicVolume = musicVolume
        self.musicStartSeconds = musicStartSeconds
        self.musicHighlightDuration = musicHighlightDuration
        self.musicFadeIn = musicFadeIn
        self.musicFadeOut = musicFadeOut
        self.musicRepeat = musicRepeat
        self.keepOriginalAudio = keepOriginalAudio
        self.voiceOffset = voiceOffset
        self.voiceVolume = voiceVolume
        self.vfxPresets = vfxPresets
        self.vfxIntensity = vfxIntensity
        self.vfxCoverage = vfxCoverage
        self.vfxStart = vfxStart
        self.vfxEnd = vfxEnd
        self.subtitleX = subtitleX
        self.subtitleY = subtitleY
        self.stripMetadata = stripMetadata
        self.addMetadata = addMetadata
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case id, name, savedAt, clips, imageOverlays, videoOverlays,
             textOverlays, soundEffects, beatSourceTimes,
             detectedTempoBPM, subtitles, subtitleAppearance, transition,
             transitionSeconds, canvas, contentMode, quality, musicFileName,
             voiceFileName, originalVoiceFileName,
             originalMusicFileName, musicMasteringSettings,
             voiceMasteringSettings, musicVolume, musicStartSeconds,
             musicHighlightDuration, musicFadeIn, musicFadeOut, musicRepeat,
             keepOriginalAudio, voiceOffset, voiceVolume, vfxPresets,
             vfxIntensity, vfxCoverage, vfxStart, vfxEnd, subtitleX,
             subtitleY, stripMetadata, addMetadata, metadata
    }

    // Old v2.8 projects did not contain overlays.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        savedAt = try values.decode(Date.self, forKey: .savedAt)
        clips = try values.decode([TimelineClip].self, forKey: .clips)
        imageOverlays = try values.decodeIfPresent([ImageOverlayClip].self,
                                                   forKey: .imageOverlays) ?? []
        videoOverlays = try values.decodeIfPresent([VideoOverlayClip].self,
                                                   forKey: .videoOverlays) ?? []
        textOverlays = try values.decodeIfPresent([TextOverlayClip].self,
                                                  forKey: .textOverlays) ?? []
        soundEffects = try values.decodeIfPresent([SoundEffectClip].self,
                                                  forKey: .soundEffects) ?? []
        beatSourceTimes = try values.decodeIfPresent([Double].self,
                                                    forKey: .beatSourceTimes) ?? []
        detectedTempoBPM = try values.decodeIfPresent(Double.self,
                                                     forKey: .detectedTempoBPM) ?? 0
        subtitles = try values.decode([SubtitleCue].self, forKey: .subtitles)
        subtitleAppearance = try values.decodeIfPresent(
            SubtitleAppearance.self, forKey: .subtitleAppearance
        ) ?? SubtitleAppearance()
        transition = try values.decode(String.self, forKey: .transition)
        transitionSeconds = try values.decode(Double.self, forKey: .transitionSeconds)
        canvas = try values.decode(String.self, forKey: .canvas)
        contentMode = try values.decode(String.self, forKey: .contentMode)
        quality = try values.decode(String.self, forKey: .quality)
        musicFileName = try values.decodeIfPresent(String.self, forKey: .musicFileName)
        voiceFileName = try values.decodeIfPresent(String.self, forKey: .voiceFileName)
        originalVoiceFileName = try values.decodeIfPresent(
            String.self, forKey: .originalVoiceFileName
        )
        originalMusicFileName = try values.decodeIfPresent(
            String.self, forKey: .originalMusicFileName
        )
        musicMasteringSettings = try values.decodeIfPresent(
            VoiceMasteringSettings.self, forKey: .musicMasteringSettings
        ) ?? MusicTonePreset.original.settings
        voiceMasteringSettings = try values.decodeIfPresent(
            VoiceMasteringSettings.self, forKey: .voiceMasteringSettings
        ) ?? VoiceMasteringSettings()
        musicVolume = try values.decode(Float.self, forKey: .musicVolume)
        musicStartSeconds = try values.decode(Double.self, forKey: .musicStartSeconds)
        musicHighlightDuration = try values.decode(Double.self, forKey: .musicHighlightDuration)
        musicFadeIn = try values.decode(Double.self, forKey: .musicFadeIn)
        musicFadeOut = try values.decode(Double.self, forKey: .musicFadeOut)
        musicRepeat = try values.decode(Bool.self, forKey: .musicRepeat)
        keepOriginalAudio = try values.decode(Bool.self, forKey: .keepOriginalAudio)
        voiceOffset = try values.decode(Double.self, forKey: .voiceOffset)
        voiceVolume = try values.decode(Float.self, forKey: .voiceVolume)
        vfxPresets = try values.decode([String].self, forKey: .vfxPresets)
        vfxIntensity = try values.decode(Double.self, forKey: .vfxIntensity)
        vfxCoverage = try values.decode(String.self, forKey: .vfxCoverage)
        vfxStart = try values.decode(Double.self, forKey: .vfxStart)
        vfxEnd = try values.decode(Double.self, forKey: .vfxEnd)
        subtitleX = try values.decode(Double.self, forKey: .subtitleX)
        subtitleY = try values.decode(Double.self, forKey: .subtitleY)
        stripMetadata = try values.decode(Bool.self, forKey: .stripMetadata)
        addMetadata = try values.decode(Bool.self, forKey: .addMetadata)
        metadata = try values.decode(ExportMetadata.self, forKey: .metadata)
    }
}

struct ProjectListItem: Identifiable {
    let id: UUID
    let name: String
    let savedAt: Date
    let clipCount: Int
}

enum ProjectStore {
    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }

    private static func file(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json")
    }

    static func save(_ project: SmartVideoProject) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: file(for: project.id), options: .atomic)
    }

    static func load(_ id: UUID) throws -> SmartVideoProject {
        let data = try Data(contentsOf: file(for: id))
        return try JSONDecoder().decode(SmartVideoProject.self, from: data)
    }

    static func list() -> [ProjectListItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let project = try? JSONDecoder().decode(
                    SmartVideoProject.self, from: data
                  ) else { return nil }
            return ProjectListItem(id: project.id, name: project.name,
                                   savedAt: project.savedAt,
                                   clipCount: project.clips.count)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    static func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: file(for: id))
    }

    static func clipInMedia(_ clip: TimelineClip) -> TimelineClip {
        var result = clip
        result.fileURL = MediaStorage.mediaDirectory
            .appendingPathComponent(clip.fileURL.lastPathComponent)
        return result
    }

    static func audioInMedia(_ name: String?) -> URL? {
        guard let name else { return nil }
        return MediaStorage.mediaDirectory.appendingPathComponent(name)
    }
}
