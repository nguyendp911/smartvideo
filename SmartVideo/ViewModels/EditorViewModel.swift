import SwiftUI
import PhotosUI
import Photos
import AVFoundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [TimelineClip] = []
    @Published var imageOverlays: [ImageOverlayClip] = []
    @Published var isTrackingFace = false
    @Published var faceTrackingMessage: String?
    @Published var isTrackingObject = false
    @Published var objectTrackingMessage: String?
    @Published var videoOverlays: [VideoOverlayClip] = []
    @Published var textOverlays: [TextOverlayClip] = []
    @Published var soundEffects: [SoundEffectClip] = []
    @Published var isImportingSoundEffects = false
    @Published var isDetectingBeats = false
    @Published var musicBeatSourceTimes: [Double] = []
    @Published var detectedTempoBPM: Double = 0
    @Published var beatConfidence: Double = 0
    @Published var beatScanStart: Double = 0

    /// Mapped to the video timeline (not source media clock).
    var timelineBeatMarkers: [Double] {
        guard !musicBeatSourceTimes.isEmpty, musicDuration > 0, totalDuration > 0 else {
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
                    let timeline = relative + offset
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
    private struct TimelineSnapshot {
        var clips: [TimelineClip]
        var soundEffects: [SoundEffectClip]
        var projectID: UUID
    }
    private var undoStack: [TimelineSnapshot] = []
    private var redoStack: [TimelineSnapshot] = []
    private var currentSnapshot: TimelineSnapshot {
        TimelineSnapshot(
            clips: clips, soundEffects: soundEffects, projectID: projectID
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
    private let autoCaptionSpeech = AutoCaptionSpeech()
    @Published var transition: VideoTransition = .cut
    @Published var transitionSeconds: Double = 0.45
    @Published var vfxPresets: Set<VFXPreset> = []
    @Published var appliedStudioPresetID: String?
    @Published var studioPresetMessage: String = ""

    private struct PresetUndo {
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
    private var studioPresetUndo: PresetUndo?
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
    @Published var musicDuration: Double = 0
    @Published var isImportingAudio = false
    @Published var isScanningMusic = false
    @Published var musicHighlightDuration: Double = 0
    @Published var voiceoverOffset: Double = 0
    @Published var voiceoverVolume: Float = 1
    @Published var stripMetadata: Bool = true
    @Published var musicHighlightLength: Double = 20
    @Published var musicHighlights: [MusicHighlight] = []
    @Published var exportedMusicHighlightURL: URL?
    @Published var isExportingMusicHighlight = false
    @Published var isAnalyzingMusicHighlights = false
    @Published var videoHighlights: [VideoHighlight] = []
    @Published var analyzedClipID: UUID?
    @Published var isAnalyzingVideoHighlights = false
    @Published var previousTimeline: [TimelineClip]?
    @Published var narrationText = ""
    @Published var narratorVoiceID: String = ""
    @Published var narratorTone: NarrationTone = .natural
    @Published var narratorRate: Float = 1.0
    @Published var narratorPitch: Float = 1.0
    @Published var silenceThreshold: Double = -39
    @Published var silenceGap: Double = 0.45
    @Published var isRemovingSilence = false
    @Published var lastSilenceRemoved: Double?
    @Published var metadata = ExportMetadata()
    @Published var addCustomMetadata = false
    @Published var musicFadeIn: Double = 0.3
    @Published var musicFadeOut: Double = 1.2
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

    func importSelections(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        checkpoint()
        isImporting = true
        defer { isImporting = false }

        for selection in selections {
            do {
                let isMovie = selection.supportedContentTypes.contains { $0.conforms(to: .movie) }
                if isMovie {
                    guard let result = try await selection.loadTransferable(type: PickedMovie.self) else {
                        throw SmartVideoError.invalidMedia("Không tải được video từ thư viện.")
                    }
                    let asset = AVURLAsset(url: result.url)
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite && duration > 0 else {
                        throw SmartVideoError.invalidMedia("Video không có thời lượng hợp lệ.")
                    }
                    clips.append(TimelineClip(kind: .video, fileURL: result.url,
                                              duration: duration, originalDuration: duration))
                } else {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw SmartVideoError.invalidMedia("Không tải được ảnh từ thư viện.")
                    }
                    let url = try MediaStorage.storeImage(data: data)
                    clips.append(TimelineClip(kind: .image, fileURL: url,
                                              duration: 3, originalDuration: 3))
                }
            } catch {
                errorText = "Một mục không thể nhập: \(error.localizedDescription)"
            }
        }
    }

    /// Copies a downloaded social video into the editable project's Media
    /// folder; vault entries can then be deleted without losing this clip.
    func importFromDownloadLibrary(_ video: SavedSocialVideo) async -> UUID? {
        guard FileManager.default.fileExists(atPath: video.fileURL.path) else {
            errorText = "Video trong Kho đã bị mất. Hãy tải lại."
            return nil
        }
        do {
            let local = try MediaStorage.copyToMedia(
                video.fileURL, fallbackExtension: "mp4"
            )
            do {
                let asset = AVURLAsset(url: local)
                guard !(try await asset.loadTracks(
                    withMediaType: .video
                )).isEmpty else {
                    throw SmartVideoError.invalidMedia(
                        "Tệp này không có track video hợp lệ."
                    )
                }
                let duration = try await asset.load(.duration).seconds
                guard duration.isFinite && duration > 0 else {
                    throw SmartVideoError.invalidMedia(
                        "Không đọc được thời lượng video."
                    )
                }
                checkpoint()
                let clip = TimelineClip(
                    kind: .video, fileURL: local,
                    duration: duration, originalDuration: duration
                )
                clips.append(clip)
                timelineSecond = timelineStart(of: clips.count - 1)
                return clip.id
            } catch {
                try? FileManager.default.removeItem(at: local)
                throw error
            }
        } catch {
            errorText = "Không đưa vào timeline được: \(error.localizedDescription)"
            return nil
        }
    }

    func importMusic(from sourceURL: URL) {
        guard !isImportingAudio else { return }
        isImportingAudio = true
        do {
            // Copy the security-scoped URL before the Files picker finishes.
            let localURL = try copyScoped(sourceURL, fallbackExtension: "mp3")
            Task {
                defer { isImportingAudio = false }
                do {
                    let asset = AVURLAsset(url: localURL)
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard !tracks.isEmpty else {
                        throw SmartVideoError.invalidMedia("Tệp vừa chọn không có track âm thanh.")
                    }
                    let duration = try await asset.load(.duration).seconds
                    // Never publish an indefinite or NaN duration to a SwiftUI Slider.
                    guard duration.isFinite && duration > 0 else {
                        throw SmartVideoError.invalidMedia(
                            "Không đọc được thời lượng MP3. Hãy thử MP3 hoặc M4A hợp lệ."
                        )
                    }
                    musicDuration = duration
                    musicBeatSourceTimes = []
                    detectedTempoBPM = 0
                    beatConfidence = 0
                    musicStartSeconds = 0
            musicHighlightDuration = 0
            musicHighlights = []
            exportedMusicHighlightURL = nil
                    musicURL = localURL
                    originalMusicURL = nil
                    musicProcessingMessage = ""
                    musicMasteringSettings = MusicTonePreset.original.settings
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    errorText = "Không nhập được nhạc: \(error.localizedDescription)"
                }
            }
        } catch {
            isImportingAudio = false
            errorText = "Không mở được MP3: \(error.localizedDescription)"
        }
    }

    func suggestMusicCut() {
        guard let url = musicURL, !isScanningMusic else { return }
        isScanningMusic = true
        Task {
            do {
                let suggested = try await Task.detached(priority: .userInitiated) {
                    try await MusicAnalyzer.firstAudibleSecond(in: url)
                }.value
                if musicURL == url {
                    musicStartSeconds = min(suggested, max(0, musicDuration - 0.1))
                }
            } catch {
                errorText = "Không tự tìm được điểm vào nhạc: \(error.localizedDescription)"
            }
            isScanningMusic = false
        }
    }

    func importVoiceover(from sourceURL: URL) {
        do {
            let localURL = try copyScoped(sourceURL, fallbackExtension: "m4a")
            Task {
                do {
                    let asset = AVURLAsset(url: localURL)
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard !tracks.isEmpty else {
                        throw SmartVideoError.invalidMedia(
                            "Tệp thuyết minh không có track âm thanh."
                        )
                    }
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite && duration > 0 else {
                        throw SmartVideoError.invalidMedia(
                            "Tệp thuyết minh không có thời lượng hợp lệ."
                        )
                    }
                    voiceoverURL = localURL
                    originalVoiceoverURL = nil
                    masteringMessage = ""
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    errorText = "Không nhập được thuyết minh: \(error.localizedDescription)"
                }
            }
        } catch {
            errorText = "Không thể mở tệp giọng đọc: \(error.localizedDescription)"
        }
    }

    func importSubtitles(from sourceURL: URL) {
        do {
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: sourceURL)
            let parsed = try SubtitleFile.parse(
                data, filename: sourceURL.lastPathComponent, videoDuration: totalDuration
            )
            guard !parsed.isEmpty else {
                throw SmartVideoError.invalidMedia("Tệp TXT/SRT không có nội dung phụ đề.")
            }
            subtitles = parsed
        } catch {
            errorText = "Không nhập được phụ đề: \(error.localizedDescription)"
        }
    }

    // MARK: - Speech to timed Auto Captions

    func generateAutoCaptions(selectedClipID: UUID?) {
        guard !isGeneratingAutoCaptions, !clips.isEmpty else { return }
        let language = autoCaptionLanguage.rawValue
        let allowApple = allowAppleSpeechService
        let replaceExisting = replaceExistingAutoCaptions

        let audioURL: URL
        let sourceStart: Double
        let sourceLimit: Double
        let timelineOffset: Double
        let speed: Double

        switch autoCaptionSource {
        case .narration:
            guard let voiceoverURL else {
                errorText = "Hãy thêm thuyết minh trước khi tạo Auto Captions."
                return
            }
            audioURL = voiceoverURL
            sourceStart = 0
            sourceLimit = max(0, totalDuration - voiceoverOffset)
            timelineOffset = voiceoverOffset
            speed = 1
        case .selectedVideo:
            guard let index = clips.firstIndex(where: { $0.id == selectedClipID }),
                  clips[index].kind == .video else {
                errorText = "Chọn một clip VIDEO có tiếng nói trên timeline."
                return
            }
            let clip = clips[index]
            audioURL = clip.fileURL
            sourceStart = clip.startTime
            speed = max(0.25, clip.playbackSpeed)
            sourceLimit = clip.duration
            timelineOffset = timelineStart(of: index)
        }

        let processLong = processLongAutoCaptions
        let projectIDAtStart = projectID
        isGeneratingAutoCaptions = true
        autoCaptionStatus = "Đang kiểm tra nguồn âm thanh…"

        Task {
            defer { isGeneratingAutoCaptions = false }
            do {
                let asset = AVURLAsset(url: audioURL)
                let fileLength = try await asset.load(.duration).seconds
                guard fileLength.isFinite, fileLength > sourceStart else {
                    throw SmartVideoError.invalidMedia("Nguồn audio có thời lượng không hợp lệ.")
                }
                // Bound to a maximum of 10 minutes per run. The service
                // is asked to recognize a small independent chunk each time.
                let availableSource = min(
                    max(0, fileLength - sourceStart),
                    max(0, sourceLimit),
                    max(0, (totalDuration - timelineOffset) * speed),
                    processLong ? 600 : 52
                )
                guard availableSource >= 0.5 else {
                    throw SmartVideoError.invalidMedia(
                        "Không có đủ tiếng nói trong phạm vi timeline."
                    )
                }
                let chunkSeconds = 52.0
                let partCount = Int(ceil(availableSource / chunkSeconds))
                var translated = [SubtitleCue]()
                for part in 0..<partCount {
                    try Task.checkCancellation()
                    let localOffset = Double(part) * chunkSeconds
                    let length = min(chunkSeconds, availableSource - localOffset)
                    guard length >= 0.5 else { continue }
                    autoCaptionStatus = "Đoạn \(part + 1)/\(partCount): trích âm thanh…"
                    let temporary = try await AutoCaptionSpeech.extractAudio(
                        from: audioURL,
                        beginningAt: sourceStart + localOffset,
                        maximumDuration: length
                    )
                    // Delete the M4A even if recognition fails.
                    let cues: [SubtitleCue]
                    do {
                        autoCaptionStatus = "Đoạn \(part + 1)/\(partCount): " +
                            "nhận diện \(language)…"
                        cues = try await autoCaptionSpeech.recognize(
                            fileURL: temporary,
                            localeIdentifier: language,
                            allowAppleService: allowApple
                        )
                    } catch {
                        try? FileManager.default.removeItem(at: temporary)
                        throw error
                    }
                    try? FileManager.default.removeItem(at: temporary)
                    for cue in cues {
                        let position = timelineOffset +
                            (localOffset + cue.start) / speed
                        let finish = min(
                            totalDuration,
                            timelineOffset + (localOffset + cue.end) / speed
                        )
                        guard position < totalDuration,
                              finish > position else { continue }
                        let words = cue.words.map { word in
                            SubtitleWord(
                                start: timelineOffset +
                                    (localOffset + word.start) / speed,
                                end: min(
                                    totalDuration,
                                    timelineOffset + (localOffset + word.end) / speed
                                ),
                                text: word.text
                            )
                        }
                        translated.append(SubtitleCue(
                            start: position, end: max(position + 0.10, finish),
                            text: cue.text, words: words
                        ))
                    }
                    autoCaptionStatus = "Đã nhận diện \(part + 1)/\(partCount) " +
                        "đoạn · \(translated.count) câu."
                }
                guard !translated.isEmpty else {
                    throw SmartVideoError.invalidMedia(
                        "Không có lời nói được nhận diện trong phần đã quét."
                    )
                }
                // Do not apply speech to an entirely different project.
                guard projectID == projectIDAtStart else { return }
                if replaceExisting {
                    subtitles = translated
                } else {
                    subtitles.append(contentsOf: translated)
                    subtitles.sort { $0.start < $1.start }
                }
                autoCaptionStatus = "Đã tạo \(translated.count) câu và " +
                    "\(translated.reduce(0) { $0 + $1.words.count }) " +
                    "mốc từ. Hãy kiểm tra và sửa các chỗ nhận diện sai."
            } catch {
                autoCaptionStatus = ""
                errorText = "Auto Captions: \(error.localizedDescription)"
            }
        }
    }

    func addSubtitle() {
        let start = min(totalDuration, (subtitles.last?.end ?? 0))
        let end = min(max(totalDuration, 0.5), start + 3)
        subtitles.append(SubtitleCue(start: start, end: max(start + 0.1, end), text: "Phụ đề mới"))
    }

    func exportSRT() -> URL? {
        do {
            let target = MediaStorage.exportsDirectory
                .appendingPathComponent("SmartVideo-PhuDe-\(UUID().uuidString.prefix(6)).srt")
            try SubtitleFile.makeSRT(subtitles).write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            errorText = "Không tạo được file SRT: \(error.localizedDescription)"
            return nil
        }
    }

    private func copyScoped(_ url: URL, fallbackExtension: String) throws -> URL {
        guard url.isFileURL else {
            throw SmartVideoError.invalidMedia("Nguồn âm thanh không phải tệp cục bộ.")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try MediaStorage.copyToMedia(url, fallbackExtension: fallbackExtension)
    }

    // MARK: - AI-assisted local video selection

    func suggestVideoHighlights(for clip: TimelineClip) {
        guard clip.kind == .video, !isAnalyzingVideoHighlights else { return }
        isAnalyzingVideoHighlights = true
        analyzedClipID = clip.id
        videoHighlights = []
        let sourceURL = clip.fileURL
        let sourceStart = clip.startTime
        let sourceDuration = clip.duration

        Task {
            defer { isAnalyzingVideoHighlights = false }
            do {
                let highlights = try await Task.detached(priority: .utility) {
                    try await VideoHighlightsAnalyzer.find(
                        in: sourceURL,
                        sourceStart: sourceStart,
                        sourceDuration: sourceDuration
                    )
                }.value
                if analyzedClipID == clip.id {
                    videoHighlights = highlights
                }
            } catch {
                errorText = "Không chọn được video highlight: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func applyVideoHighlights(clipID: UUID, selected: [VideoHighlight]) -> UUID? {
        guard let index = clips.firstIndex(where: { $0.id == clipID }),
              clips[index].kind == .video,
              !selected.isEmpty else { return nil }

        let source = clips[index]
        var replacements: [TimelineClip] = []
        for highlight in selected.sorted(by: { $0.start < $1.start }) {
            var result = source
            result.id = UUID()
            result.startTime = min(
                source.originalDuration,
                max(0, source.startTime + highlight.start)
            )
            result.duration = min(
                highlight.duration,
                max(0, source.originalDuration - result.startTime)
            )
            if result.duration >= 0.1 {
                replacements.append(result)
            }
        }
        guard !replacements.isEmpty else { return nil }
        previousTimeline = clips
        clips.replaceSubrange(index...index, with: replacements)
        analyzedClipID = nil
        videoHighlights = []
        return replacements.first?.id
    }

    func undoHighlights() {
        guard let previousTimeline else { return }
        clips = previousTimeline
        self.previousTimeline = nil
        analyzedClipID = nil
        videoHighlights = []
    }

    // MARK: - Music highlights

    func suggestMusicHighlights() {
        guard let file = musicURL, !isAnalyzingMusicHighlights else { return }
        let length = musicHighlightLength
        musicHighlights = []
        isAnalyzingMusicHighlights = true
        Task {
            defer { isAnalyzingMusicHighlights = false }
            do {
                let suggestions = try await Task.detached(priority: .utility) {
                    try await SmartMusicHighlights.find(in: file, desiredLength: length)
                }.value
                if file == musicURL {
                    musicHighlights = suggestions
                }
            } catch {
                errorText = "Phân tích nhạc thất bại: \(error.localizedDescription)"
            }
        }
    }

    func exportMusicHighlight() {
        guard let url = musicURL, musicHighlightDuration > 0,
              !isExportingMusicHighlight else { return }
        isExportingMusicHighlight = true
        exportedMusicHighlightURL = nil
        let start = musicStartSeconds
        let duration = musicHighlightDuration
        Task {
            defer { isExportingMusicHighlight = false }
            do {
                exportedMusicHighlightURL = try await MusicSegmentExporter.export(
                    inputURL: url, start: start, duration: duration
                )
            } catch {
                errorText = "Không xuất được MP3 highlight: \(error.localizedDescription)"
            }
        }
    }

    func useMusicHighlight(_ highlight: MusicHighlight) {
        guard musicURL != nil else { return }
        musicStartSeconds = min(max(0, highlight.start),
                                max(0, musicDuration - 0.1))
        musicHighlightDuration = min(highlight.duration,
                                     max(0, musicDuration - musicStartSeconds))
        exportedMusicHighlightURL = nil
    }

    // MARK: - Narration from text

    func generateNarrationFromText() {
        guard !isGeneratingNarration else { return }
        isGeneratingNarration = true
        let text = narrationText
        Task {
            defer { isGeneratingNarration = false }
            do {
                let url = try await NarrationSpeechWriter().render(
                    text: text,
                    voiceIdentifier: narratorVoiceID.isEmpty ? nil : narratorVoiceID,
                    tone: narratorTone,
                    rateAdjustment: narratorRate,
                    pitchAdjustment: narratorPitch
                )
                voiceoverURL = url
                originalVoiceoverURL = nil
                masteringMessage = ""
            } catch {
                errorText = "Không tạo được giọng thuyết minh: \(error.localizedDescription)"
            }
        }
    }

    func removeSilenceFromNarration() {
        guard let source = voiceoverURL, !isRemovingSilence else { return }
        isRemovingSilence = true
        let threshold = silenceThreshold
        let gap = silenceGap
        Task {
            defer { isRemovingSilence = false }
            do {
                let cleaned = try await Task.detached(priority: .userInitiated) {
                    try await VoiceSilenceEditor.removeSilence(
                        from: source, thresholdDecibels: threshold,
                        minimumGap: gap, padding: 0.12
                    )
                }.value
                // Don't replace audio if a different take was selected.
                if voiceoverURL == source {
                    voiceoverURL = cleaned.url
                    originalVoiceoverURL = nil
                    masteringMessage = ""
                    lastSilenceRemoved = cleaned.removedDuration
                }
            } catch {
                errorText = "Không xóa được khoảng lặng: \(error.localizedDescription)"
            }
        }
    }

    func applyVoiceMastering() {
        guard !isMasteringVoice, !isRemovingSilence,
              let current = voiceoverURL else {
            if voiceoverURL == nil {
                errorText = "Hãy thu, nhập hoặc tạo giọng thuyết minh trước."
            }
            return
        }
        let source = originalVoiceoverURL ?? current
        let settings = masteringSettings
        isMasteringVoice = true
        masteringMessage = ""
        Task {
            defer { isMasteringVoice = false }
            do {
                let target = try await Task.detached(priority: .userInitiated) {
                    try VoiceMasteringProcessor.process(
                        sourceURL: source, settings: settings
                    )
                }.value
                // Avoid switching the narration if the user imported a
                // different take while processing was still running.
                guard voiceoverURL == current else {
                    try? FileManager.default.removeItem(at: target)
                    return
                }
                originalVoiceoverURL = source
                voiceoverURL = target
                masteringMessage = "Đã xử lý EQ + compressor" +
                    (settings.noiseGateEnabled ? " + noise gate" : "") +
                    ". Bản gốc vẫn được giữ."
            } catch {
                errorText = "Không xử lý được giọng đọc: \(error.localizedDescription)"
            }
        }
    }

    func normalizeNarration() {
        guard !isMasteringVoice, let current = voiceoverURL else {
            if voiceoverURL == nil {
                errorText = "Hãy chọn bản thuyết minh để chuẩn hóa."
            }
            return
        }
        let source = current
        isMasteringVoice = true
        masteringMessage = ""
        Task {
            defer { isMasteringVoice = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try AudioLoudnessNormalizer.normalize(
                        sourceURL: source, targetDBFS: -20
                    )
                }.value
                guard voiceoverURL == source else {
                    try? FileManager.default.removeItem(at: result.outputURL)
                    return
                }
                originalVoiceoverURL = originalVoiceoverURL ?? source
                voiceoverURL = result.outputURL
                masteringMessage = String(
                    format: "Chuẩn hóa giọng: %.1f → %.1f dBFS RMS (gain %+.1f dB).",
                    result.inputRMSDBFS, result.outputRMSDBFS, result.appliedGainDB
                )
            } catch {
                errorText = "Không chuẩn hóa được thuyết minh: \(error.localizedDescription)"
            }
        }
    }

    func applyMusicMastering() {
        guard !isProcessingMusic, let current = musicURL else {
            if musicURL == nil { errorText = "Chọn nhạc nền trước." }
            return
        }
        isProcessingMusic = true
        musicProcessingMessage = ""
        var settings = musicMasteringSettings
        settings.noiseGateEnabled = false
        let source = originalMusicURL ?? current
        Task {
            defer { isProcessingMusic = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try VoiceMasteringProcessor.process(
                        sourceURL: source, settings: settings
                    )
                }.value
                guard musicURL == current else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                originalMusicURL = source
                musicURL = url
                musicProcessingMessage = "Đã áp dụng EQ/compressor vào nhạc nền. Giữ nguyên bản gốc."
            } catch {
                errorText = "Không xử lý được nhạc: \(error.localizedDescription)"
            }
        }
    }

    func normalizeMusic() {
        guard !isProcessingMusic, let current = musicURL else {
            if musicURL == nil { errorText = "Chọn nhạc nền trước." }
            return
        }
        isProcessingMusic = true
        musicProcessingMessage = ""
        let source = current
        Task {
            defer { isProcessingMusic = false }
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try AudioLoudnessNormalizer.normalize(
                        sourceURL: source, targetDBFS: -18
                    )
                }.value
                guard musicURL == source else {
                    try? FileManager.default.removeItem(at: report.outputURL)
                    return
                }
                originalMusicURL = originalMusicURL ?? source
                musicURL = report.outputURL
                musicProcessingMessage = String(
                    format: "Chuẩn hóa nhạc: %.1f → %.1f dBFS RMS (gain %+.1f dB).",
                    report.inputRMSDBFS, report.outputRMSDBFS,
                    report.appliedGainDB
                )
            } catch {
                errorText = "Không chuẩn hóa được nhạc: \(error.localizedDescription)"
            }
        }
    }

    func restoreOriginalMusic() {
        guard !isProcessingMusic, let original = originalMusicURL else {
            return
        }
        musicURL = original
        originalMusicURL = nil
        musicProcessingMessage = "Đã khôi phục nhạc gốc."
    }

    func restoreOriginalNarration() {
        guard !isMasteringVoice, let original = originalVoiceoverURL else {
            return
        }
        voiceoverURL = original
        originalVoiceoverURL = nil
        masteringMessage = "Đã khôi phục bản thuyết minh gốc."
    }

    func createSubtitlesFromNarrationText() {
        let text = narrationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, totalDuration > 0 else {
            errorText = "Cần nhập lời thuyết minh và thêm ảnh/video vào timeline."
            return
        }
        let formatted = text.replacingOccurrences(
            of: #"(?<=[.!?。！？])\s+"#, with: "\n",
            options: .regularExpression
        )
        guard let data = formatted.data(using: .utf8) else { return }
        do {
            subtitles = try SubtitleFile.parse(
                data, filename: "narration.txt", videoDuration: totalDuration
            )
        } catch {
            errorText = "Không tạo được phụ đề: \(error.localizedDescription)"
        }
    }

    // MARK: - Independent PIP overlay track

    func importImageOverlay(_ selection: PhotosPickerItem) async {
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw SmartVideoError.invalidMedia("Không tải được ảnh phủ.")
            }
            let file = try MediaStorage.storeOverlayImage(data: data)
            var overlay = ImageOverlayClip(fileURL: file)
            overlay.start = min(timelineSecond, max(0, totalDuration - 0.2))
            overlay.duration = min(3, max(0.2, totalDuration - overlay.start))
            imageOverlays.append(overlay)
        } catch {
            errorText = "Không thêm được overlay: \(error.localizedDescription)"
        }
    }

    /// Detect the primary face and turn its positions into real overlay
    /// keyframes. Requires the entire overlay to fit one source video clip.
    /// All computation is local through Vision/AVFoundation.
    func autoTrackFace(overlayID: UUID) async {
        guard !isTrackingFace && !isTrackingObject else { return }
        guard let overlay = imageOverlays.first(where: { $0.id == overlayID }),
              let target = clipAtTimeline(overlay.start + 0.01),
              clips.indices.contains(target.index) else {
            errorText = "Hãy chọn một overlay ảnh nằm trên đoạn video."
            return
        }
        let clip = clips[target.index]
        let clipStart = timelineStart(of: target.index)
        guard clip.kind == .video,
              overlay.start >= clipStart - 0.001,
              overlay.end <= clipStart + clip.renderedDuration + 0.01 else {
            errorText = "Để tự bám mặt, đặt overlay nằm trọn trong một clip video."
            return
        }
        let startingProject = projectID
        isTrackingFace = true
        faceTrackingMessage = "Đang dò khuôn mặt và tạo keyframe…"
        defer { isTrackingFace = false }

        do {
            let frames = try await OverlayFaceTracker.generate(
                clip: clip, overlay: overlay,
                localStart: overlay.start - clipStart,
                renderSize: canvas.size(for: .hd),
                contentMode: contentMode
            )
            guard startingProject == projectID,
                  clips.contains(where: { $0.id == clip.id && $0 == clip }),
                  let index = imageOverlays.firstIndex(where: {
                      $0.id == overlayID && $0 == overlay
                  }) else {
                throw SmartVideoError.invalidMedia(
                    "Dự án đã thay đổi khi đang phân tích. Hãy thử lại."
                )
            }
            imageOverlays[index].keyframes = frames
            imageOverlays[index].easing = .linear
            imageOverlays[index].pathMode = .straight
            imageOverlays[index].startX = frames.first?.x ?? overlay.startX
            imageOverlays[index].startY = frames.first?.y ?? overlay.startY
            imageOverlays[index].endX = frames.last?.x ?? overlay.endX
            imageOverlays[index].endY = frames.last?.y ?? overlay.endY
            faceTrackingMessage = "Đã tạo \(frames.count) keyframe bám khuôn mặt."
        } catch {
            errorText = "Không theo dõi được khuôn mặt: \(error.localizedDescription)"
            faceTrackingMessage = nil
        }
    }

    /// Vision's VNTrackObjectRequest follows the region underneath the
    /// image overlay. Unlike face detection, this tracks a selected object.
    func autoTrackObject(overlayID: UUID) async {
        guard !isTrackingFace && !isTrackingObject else { return }
        guard let overlay = imageOverlays.first(where: { $0.id == overlayID }),
              let target = clipAtTimeline(overlay.start + 0.01),
              clips.indices.contains(target.index) else {
            errorText = "Hãy chọn một ảnh phủ trên đoạn video để bám vật thể."
            return
        }
        let clip = clips[target.index]
        let clipStart = timelineStart(of: target.index)
        guard clip.kind == .video,
              overlay.start >= clipStart - 0.001,
              overlay.end <= clipStart + clip.renderedDuration + 0.01 else {
            errorText = "Đặt lớp ảnh phủ nằm trọn trong một clip video."
            return
        }
        let initialProject = projectID
        isTrackingObject = true
        objectTrackingMessage = "Đang chạy Vision Object Tracking…"
        defer { isTrackingObject = false }
        do {
            let frames = try await OverlayObjectTracker.generate(
                clip: clip, overlay: overlay,
                localStart: overlay.start - clipStart,
                renderSize: canvas.size(for: .hd),
                contentMode: contentMode
            )
            guard initialProject == projectID,
                  clips.contains(where: { $0.id == clip.id && $0 == clip }),
                  let index = imageOverlays.firstIndex(where: {
                      $0.id == overlayID && $0 == overlay
                  }) else {
                throw SmartVideoError.invalidMedia(
                    "Dự án đã được sửa. Vui lòng thực hiện lại."
                )
            }
            imageOverlays[index].keyframes = frames
            imageOverlays[index].easing = .linear
            imageOverlays[index].pathMode = .straight
            imageOverlays[index].startX = frames.first?.x ?? overlay.startX
            imageOverlays[index].startY = frames.first?.y ?? overlay.startY
            imageOverlays[index].endX = frames.last?.x ?? overlay.endX
            imageOverlays[index].endY = frames.last?.y ?? overlay.endY
            objectTrackingMessage = "Đã tạo \(frames.count) keyframe bám vật thể."
        } catch {
            errorText = "Theo dõi vật thể thất bại: \(error.localizedDescription)"
            objectTrackingMessage = nil
        }
    }

    // MARK: - Image overlay multi-point keyframe editing

    @discardableResult
    func addImageOverlayKeyframe(_ id: UUID, atTimeline second: Double) -> UUID? {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var overlay = imageOverlays[index]
        guard overlay.duration > 0.15 else { return nil }
        let progress = min(0.985, max(0.015,
            (second - overlay.start) / overlay.duration
        ))
        if overlay.keyframes.isEmpty {
            overlay.keyframes = OverlayKeyframeSampler.frames(for: overlay)
        }
        if let existing = overlay.keyframes.first(where: {
            abs($0.progress - progress) < 0.015
        }) {
            return existing.id
        }
        guard overlay.keyframes.count < 16 else {
            errorText = "Giới hạn 16 keyframe trên mỗi lớp ảnh."
            return nil
        }
        var sample = OverlayKeyframeSampler.sample(
            overlay, atProgress: progress
        )
        sample.id = UUID()
        sample.progress = progress
        overlay.keyframes.append(sample)
        overlay.keyframes.sort { $0.progress < $1.progress }
        imageOverlays[index] = overlay
        return sample.id
    }

    func removeImageOverlayKeyframe(_ id: UUID, frameID: UUID) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard let k = imageOverlays[index].keyframes.firstIndex(where: {
            $0.id == frameID
        }) else { return }
        let frames = imageOverlays[index].keyframes
        // Endpoints anchor the visible segment, never remove them.
        guard k > 0, k < frames.count - 1 else { return }
        imageOverlays[index].keyframes.remove(at: k)
    }

    func applyImageKeyframePreset(_ id: UUID, preset: ImageKeyframePreset) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return
        }
        imageOverlays[index].keyframes = preset.makeFrames(
            from: imageOverlays[index]
        )
    }

    func clearImageKeyframes(_ id: UUID) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return
        }
        let current = imageOverlays[index]
        let frames = OverlayKeyframeSampler.frames(for: current)
        guard let first = frames.first, let last = frames.last else { return }
        imageOverlays[index].startX = first.x
        imageOverlays[index].startY = first.y
        imageOverlays[index].endX = last.x
        imageOverlays[index].endY = last.y
        imageOverlays[index].scale = first.scale
        imageOverlays[index].opacity = first.opacity
        imageOverlays[index].rotationDegrees = first.rotationDegrees
        imageOverlays[index].keyframes = []
    }

    func translateImageOverlay(_ id: UUID, dx: Double, dy: Double) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }),
              dx.isFinite, dy.isFinite else { return }
        let item = imageOverlays[index]
        let frames = OverlayKeyframeSampler.frames(for: item)
        let minX = frames.map(\.x).min() ?? 0.5
        let maxX = frames.map(\.x).max() ?? 0.5
        let minY = frames.map(\.y).min() ?? 0.5
        let maxY = frames.map(\.y).max() ?? 0.5
        let shiftX = min(max(dx, 0.03 - minX), 0.97 - maxX)
        let shiftY = min(max(dy, 0.03 - minY), 0.97 - maxY)
        if item.keyframes.isEmpty {
            imageOverlays[index].startX += shiftX
            imageOverlays[index].endX += shiftX
            imageOverlays[index].startY += shiftY
            imageOverlays[index].endY += shiftY
        } else {
            for frameIndex in imageOverlays[index].keyframes.indices {
                imageOverlays[index].keyframes[frameIndex].x += shiftX
                imageOverlays[index].keyframes[frameIndex].y += shiftY
            }
        }
    }

    func removeImageOverlay(_ id: UUID) {
        imageOverlays.removeAll { $0.id == id }
    }

    func importVideoOverlay(_ selection: PhotosPickerItem) async {
        guard videoOverlays.count < 4 else {
            errorText = "Tối đa bốn lớp video PIP để tránh quá tải iPhone."
            return
        }
        do {
            guard let movie = try await selection.loadTransferable(type: PickedMovie.self) else {
                throw SmartVideoError.invalidMedia("Không tải được video PIP.")
            }
            let asset = AVURLAsset(url: movie.url)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else {
                throw SmartVideoError.invalidMedia("Tệp overlay không có hình ảnh video.")
            }
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite && seconds > 0.1 else {
                throw SmartVideoError.invalidMedia("Thời lượng video PIP không hợp lệ.")
            }
            var item = VideoOverlayClip(fileURL: movie.url)
            item.start = min(timelineSecond, max(0, totalDuration - 0.2))
            item.duration = min(seconds, max(0.1, totalDuration - item.start))
            item.sourceDuration = seconds
            videoOverlays.append(item)
        } catch {
            errorText = "Không nhập được video Overlay: \(error.localizedDescription)"
        }
    }

    func addTextOverlay() {
        guard totalDuration > 0 else {
            errorText = "Hãy thêm clip video/ảnh trước khi tạo lớp chữ."
            return
        }
        var item = TextOverlayClip()
        item.start = min(timelineSecond, max(0, totalDuration - 0.2))
        item.duration = min(3, max(0.1, totalDuration - item.start))
        textOverlays.append(item)
    }

    func removeVideoOverlay(_ id: UUID) {
        videoOverlays.removeAll { $0.id == id }
    }

    func removeTextOverlay(_ id: UUID) {
        textOverlays.removeAll { $0.id == id }
    }

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
                studioPresetID: appliedStudioPresetID
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
            let sfxFiles = p.soundEffects.map {
                MediaStorage.mediaDirectory.appendingPathComponent($0.fileURL.lastPathComponent)
            }
            let allFiles = restoredClips.map(\.fileURL) + overlayFiles + pipFiles + sfxFiles +
                [restoredMusic, restoredVoice, restoredOriginalVoice,
                 restoredOriginalMusic].compactMap { $0 }
            guard allFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw SmartVideoError.invalidMedia(
                    "Thiếu ảnh, video hoặc âm thanh gốc. Dự án cần các file trong Media của ứng dụng."
                )
            }
            // An undo must never restore media from another project.
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
            textOverlays = p.textOverlays
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
        soundEffects = []
        musicBeatSourceTimes = []
        detectedTempoBPM = 0
        subtitles = []
        subtitleAppearance = SubtitleAppearance()
        autoCaptionStatus = ""
        musicURL = nil
        originalMusicURL = nil
        musicMasteringSettings = VoiceMasteringSettings(
            bassDB: 0, midDB: 0, trebleDB: 0, compressorThreshold: -20,
            compressorRatio: 1, noiseGateEnabled: false,
            noiseGateThreshold: -46, outputGainDB: 0
        )
        musicProcessingMessage = ""
        renderedPreviewURL = nil
        voiceoverURL = nil
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

    // MARK: - Precise, non-destructive timeline editing

    private func checkpoint() {
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
        soundEffects = previous.soundEffects
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
        soundEffects = next.soundEffects
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

    private func renderProject(previewOnly: Bool) {
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
        let workSoundEffects = soundEffects
        let workTransition = transition
        let workTransitionSeconds = transitionSeconds
        let workVFX = VFXPreset.allCases.filter { vfxPresets.contains($0) }
        let workVFXIntensity = vfxIntensity
        let workVFXCoverage = vfxCoverage
        let workVFXStartTime = vfxStartTime
        let workVFXEndTime = vfxEndTime
        let workMusic = musicURL
        let workMusicVolume = musicVolume
        let workMusicStart = musicStartSeconds
        let workLoop = repeatShortMusic
        let workHighlightLength = musicHighlightDuration
        let workVoiceOffset = voiceoverOffset
        let workVoiceVolume = voiceoverVolume
        let workStripMetadata = stripMetadata
        let workMetadata = addCustomMetadata ? metadata : ExportMetadata()
        let workFadeIn = musicFadeIn
        let workFadeOut = musicFadeOut
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
                        soundEffects: workSoundEffects,
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
                        musicFadeOut: workFadeOut
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
