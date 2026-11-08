import SwiftUI
import PhotosUI
import Photos
import AVFoundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [TimelineClip] = []
    @Published var imageOverlays: [ImageOverlayClip] = []
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
    private var undoStack: [[TimelineClip]] = []
    private var redoStack: [[TimelineClip]] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    @Published var subtitles: [SubtitleCue] = []
    @Published var transition: VideoTransition = .cut
    @Published var transitionSeconds: Double = 0.45
    @Published var vfxPresets: Set<VFXPreset> = []
    @Published var vfxIntensity: Double = 0.30
    @Published var vfxCoverage: VFXCoverage = .videoOnly
    @Published var vfxStartTime: Double = 0
    @Published var vfxEndTime: Double = 0
    @Published var subtitleX: Double = 0.5
    @Published var subtitleY: Double = 0.83
    @Published var musicURL: URL?
    @Published var voiceoverURL: URL?
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
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var errorText: String?
    @Published var didSaveToPhotos = false

    var totalDuration: Double {
        let raw = clips.reduce(0) { $0 + $1.renderedDuration }
        guard transition == .dissolve, clips.count > 1 else { return raw }
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
                    lastSilenceRemoved = cleaned.removedDuration
                }
            } catch {
                errorText = "Không xóa được khoảng lặng: \(error.localizedDescription)"
            }
        }
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
        soundEffects.removeAll { $0.id == id }
    }

    func moveSoundEffectToPlayhead(_ id: UUID) {
        guard let index = soundEffects.firstIndex(where: { $0.id == id }) else {
            return
        }
        soundEffects[index].start = min(
            max(0, timelineSecond), max(0, totalDuration - 0.1)
        )
    }

    @discardableResult
    func duplicateSoundEffect(_ id: UUID) -> UUID? {
        guard soundEffects.count < 12,
              let index = soundEffects.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var duplicate = soundEffects[index]
        duplicate.id = UUID()
        duplicate.start = min(
            max(0, soundEffects[index].end), max(0, totalDuration - 0.1)
        )
        soundEffects.insert(duplicate, at: index + 1)
        return duplicate.id
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
                transition: transition.rawValue,
                transitionSeconds: transitionSeconds,
                canvas: canvas.rawValue, contentMode: contentMode.rawValue,
                quality: quality.rawValue,
                musicFileName: musicURL?.lastPathComponent,
                voiceFileName: voiceoverURL?.lastPathComponent,
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
                addMetadata: addCustomMetadata, metadata: metadata
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
            let restoredVoice = ProjectStore.audioInMedia(p.voiceFileName)
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
                [restoredMusic, restoredVoice].compactMap { $0 }
            guard allFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
                throw SmartVideoError.invalidMedia(
                    "Thiếu ảnh, video hoặc âm thanh gốc. Dự án cần các file trong Media của ứng dụng."
                )
            }
            checkpoint()
            projectID = p.id
            projectName = p.name
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
            voiceoverURL = restoredVoice
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
        checkpoint()
        projectID = UUID()
        projectName = "Dự án mới"
        clips = []
        imageOverlays = []
        videoOverlays = []
        textOverlays = []
        soundEffects = []
        musicBeatSourceTimes = []
        detectedTempoBPM = 0
        subtitles = []
        musicURL = nil
        voiceoverURL = nil
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
        undoStack.append(clips)
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        objectWillChange.send()
    }

    func undoEdit() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(clips)
        clips = previous
        timelineSecond = min(timelineSecond, totalDuration)
        objectWillChange.send()
    }

    func redoEdit() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(clips)
        clips = next
        timelineSecond = min(timelineSecond, totalDuration)
        objectWillChange.send()
    }

    func timelineStart(of index: Int) -> Double {
        guard clips.indices.contains(index) else { return 0 }
        var cursor = 0.0
        for item in 0..<index {
            cursor += clips[item].renderedDuration
            if transition == .dissolve {
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
            let leftSourceSeconds = leftOutput * source.playbackSpeed
            left.duration = leftSourceSeconds
            right.startTime = source.startTime + leftSourceSeconds
            right.duration = max(0.1, source.duration - leftSourceSeconds)
        } else {
            left.duration = leftOutput
            right.duration = max(0.1, source.duration - leftOutput)
        }
        clips.replaceSubrange(index...index, with: [left, right])
        return right.id
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

    func export() {
        guard !clips.isEmpty, !isExporting else { return }
        isExporting = true
        exportedURL = nil
        didSaveToPhotos = false

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
        let workSubtitleX = subtitleX
        let workSubtitleY = subtitleY
        let workKeepOriginal = keepOriginalAudio
        let workQuality = quality
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
                exportedURL = url
            } catch {
                errorText = error.localizedDescription
            }
            isExporting = false
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
