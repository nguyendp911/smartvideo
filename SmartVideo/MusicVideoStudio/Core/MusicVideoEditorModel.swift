import SwiftUI
import PhotosUI

extension MusicVideoStudio {
    /// Editing state of the studio: the project (a value type), selection,
    /// undo/redo, autosave and the shared playback clock. Views observe this
    /// for structure and `PlaybackEngine` separately for time, so playback
    /// ticks never re-render the inspector or toolbar.
    @MainActor
    final class MusicVideoEditorModel: ObservableObject {
        @Published private(set) var project: VideoProject
        @Published var selection: Set<UUID> = []
        @Published var multiSelect = false
        @Published var scale = TimelineScale()
        @Published private(set) var isImporting = false
        @Published private(set) var importProgress = ""
        @Published private(set) var statusMessage: String?
        /// Where a dragged clip edge is snapping (drawn as a guide line).
        @Published private(set) var snapGuide: ProjectTime?
        /// The lyrics layer whose editor sheet is open.
        @Published var lyricsEditorLayerID: UUID?
        @Published private(set) var lyricsBusy = ""
        /// Snap lines shown while dragging on the canvas.
        @Published var transformGuides = TransformGuides()
        /// Permanent centre cross + safe-area frame on the canvas.
        @Published var showSafeArea = false
        var transformSession: TransformSession?
        /// Bumped whenever a spectrum finishes loading, so the preview redraws.
        @Published private(set) var spectrumVersion = 0
        private var spectra: [String: SpectrumData] = [:]
        private var spectrumRequests = Set<String>()

        let playback = PlaybackEngine()
        let audio = AudioPlaybackEngine()
        let manager: ProjectManager

        private var history = UndoHistory<VideoProject>()
        private var saveTask: Task<Void, Never>?

        init(manager: ProjectManager = ProjectManager(), project: VideoProject? = nil) {
            self.manager = manager
            if let project {
                self.project = project
            } else if let id = manager.latestProjectID(), let saved = try? manager.load(id) {
                self.project = saved
            } else {
                self.project = VideoProject()
            }
            playback.configure(duration: self.project.duration, fps: self.project.fps)
            playback.observer = audio
            audio.onInterruption = { [weak self] in self?.playback.pause() }
            syncAudio()
            prepareSpectra()
        }

        /// Keeps the live audio engine in step with the project's audio clips.
        func syncAudio() {
            let manager = self.manager, projectID = project.id
            audio.update(audios: project.audios,
                         mediaURL: { manager.mediaURL(projectID: projectID, file: $0.mediaFile) },
                         time: playback.state.time)
        }

        // MARK: Derived

        var canUndo: Bool { history.canUndo }
        var canRedo: Bool { history.canRedo }

        var selectedCores: [LayerCore] { project.allCores.filter { selection.contains($0.id) } }
        var editableSelection: Set<UUID> { TimelineEngine.editable(selection, in: project) }

        func mediaURL(for photo: PhotoLayer) -> URL {
            manager.mediaURL(projectID: project.id, file: photo.mediaFile)
        }

        // MARK: Mutations

        /// Apply a change WITHOUT recording undo (use inside a continuous edit).
        func mutate(_ change: (inout VideoProject) -> Void) {
            var next = project
            change(&next)
            apply(next)
        }

        private func apply(_ candidate: VideoProject) {
            guard candidate != project else { return }
            var next = candidate
            next.modifiedAt = Date()
            let audioChanged = next.audios != project.audios
            project = next
            playback.configure(duration: project.duration, fps: project.fps)
            if audioChanged { syncAudio() }
            prepareSpectra()
            scheduleSave()
        }

        /// One undo step, then apply. A change that alters nothing records nothing.
        func edit(_ change: (inout VideoProject) -> Void) {
            var next = project
            change(&next)
            guard next != project else { return }
            history.checkpoint(project)
            apply(next)
        }

        /// Call once when a slider drag / text edit begins.
        func beginEdit() { history.checkpoint(project) }

        func undo() {
            guard let previous = history.undo(current: project) else { return }
            restore(previous)
        }

        func redo() {
            guard let next = history.redo(current: project) else { return }
            restore(next)
        }

        private func restore(_ snapshot: VideoProject) {
            project = snapshot
            selection = selection.filter { project.core(for: $0) != nil }
            playback.configure(duration: project.duration, fps: project.fps)
            syncAudio()
            scheduleSave()
        }

        // MARK: Selection

        func select(_ id: UUID, additive: Bool) {
            if additive || multiSelect {
                if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            } else {
                selection = [id]
            }
        }

        func clearSelection() { selection.removeAll() }

        func setStatus(_ message: String?) { statusMessage = message }

        // MARK: Layer actions

        func addText() {
            let time = playback.state.frameTime
            var created: UUID?
            edit { created = TimelineEngine.addText("Nhập chữ", at: time, to: &$0) }
            if let created { selection = [created] }
        }

        func duplicateSelection() {
            let ids = selection
            var created: [UUID] = []
            edit { created = TimelineEngine.duplicate(ids, in: &$0) }
            if !created.isEmpty { selection = Set(created) }
        }

        func deleteSelection() {
            let ids = editableSelection
            guard !ids.isEmpty else { return }
            edit { $0.removeLayers(ids) }
            selection.subtract(ids)
        }

        func resetTransformOfSelection() {
            let ids = selection
            edit { TimelineEngine.resetTransform(ids, in: &$0) }
        }

        func setAspect(_ aspect: AspectRatio) { edit { $0.aspect = aspect } }
        func setFPS(_ fps: Int) { edit { $0.fps = ProjectTime.supportedFrameRates.contains(fps) ? fps : $0.fps } }
        func rename(_ name: String) { mutate { $0.name = name } }

        // MARK: Timeline editing (drag, trim, split, ripple, order)

        /// One continuous clip interaction: the ranges at the moment it began,
        /// so every drag event is computed from the origin (no drift).
        struct ClipEditSession {
            let primary: UUID
            let origins: [UUID: TimeRange]
        }

        private var snapThreshold: ProjectTime {
            ProjectTime(seconds: 8 / max(1, scale.pixelsPerSecond))      // 8 pt on screen
        }

        /// Starts moving/trimming `id` (and the rest of an existing selection
        /// that contains it). nil when the layer is locked. One undo step.
        func beginClipEdit(_ id: UUID) -> ClipEditSession? {
            guard let core = project.core(for: id), !core.isLocked else { return nil }
            if !selection.contains(id) { selection = [id] }
            let ids = editableSelection.union([id])
            var origins: [UUID: TimeRange] = [:]
            for c in project.allCores where ids.contains(c.id) { origins[c.id] = c.range }
            history.checkpoint(project)
            return ClipEditSession(primary: id, origins: origins)
        }

        func moveClips(_ session: ClipEditSession, deltaSeconds: Double) {
            let points = TimelineEditing.snapPoints(
                in: project, excluding: Set(session.origins.keys), playhead: playback.state.time)
            let threshold = snapThreshold
            var snapped: ProjectTime?
            mutate { p in
                snapped = TimelineEditing.move(origins: session.origins, delta: ProjectTime(seconds: deltaSeconds),
                                               in: &p, snapPoints: points, threshold: threshold)
            }
            snapGuide = snapped
        }

        func trimClip(_ session: ClipEditSession, edge: TrimEdge, deltaSeconds: Double) {
            guard let origin = session.origins[session.primary] else { return }
            let points = TimelineEditing.snapPoints(
                in: project, excluding: [session.primary], playhead: playback.state.time)
            let threshold = snapThreshold
            var snapped: ProjectTime?
            mutate { p in
                snapped = TimelineEditing.trim(id: session.primary, origin: origin, edge: edge,
                                               delta: ProjectTime(seconds: deltaSeconds), in: &p,
                                               snapPoints: points, threshold: threshold)
            }
            snapGuide = snapped
        }

        func endClipEdit() { snapGuide = nil }

        /// Cuts the selected layers (or, with no selection, everything under the
        /// playhead) at the playhead.
        func splitAtPlayhead() {
            let time = playback.state.frameTime
            let ids = selection.isEmpty ? Set(TimelineEngine.activeLayerIDs(in: project, at: time)) : selection
            var created: [UUID] = []
            edit { created = TimelineEditing.split(ids, at: time, in: &$0) }
            if created.isEmpty {
                statusMessage = "Đặt con trỏ bên trong một clip (cách mép ít nhất 0,1 giây) rồi bấm Cắt."
            } else {
                statusMessage = nil
                selection = Set(created)
            }
        }

        /// Delete and close the gap on the same track.
        func rippleDeleteSelection() {
            let ids = editableSelection
            guard !ids.isEmpty else { return }
            edit { TimelineEditing.rippleDelete(ids, in: &$0) }
            selection.subtract(ids)
        }

        func packPhotos() { edit { TimelineEditing.packPhotos(in: &$0) } }

        /// Move the selected photo earlier (-1) or later (+1) in play order.
        func movePhotoInOrder(_ offset: Int) {
            guard let photo = selectedPhotoLayer() else { return }
            var moved = false
            edit { moved = TimelineEditing.movePhoto(photo.core.id, by: offset, in: &$0) }
            statusMessage = moved ? nil : "Ảnh đã ở đầu hoặc cuối danh sách, hoặc đang bị khóa."
        }

        func setAllPhotoDurations(_ seconds: Double) {
            edit { TimelineEditing.setAllPhotoDurations(ProjectTime(seconds: seconds), in: &$0) }
        }

        func selectAll() { selection = Set(project.allCores.map(\.id)) }

        // MARK: Bindings for the inspector

        /// Reads the first selected layer, writes to every editable selected layer.
        func coreBinding<T>(_ keyPath: WritableKeyPath<LayerCore, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedCores.first?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for id in ids { project.updateCore(id) { $0[keyPath: keyPath] = value } }
                    }
                }
            )
        }

        /// Lock / visibility must work on locked layers too.
        func flagBinding(_ keyPath: WritableKeyPath<LayerCore, Bool>) -> Binding<Bool> {
            Binding(
                get: { [weak self] in self?.selectedCores.first?[keyPath: keyPath] ?? false },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.selection
                    self.edit { project in
                        for id in ids { project.updateCore(id) { $0[keyPath: keyPath] = value } }
                    }
                }
            )
        }

        /// Seconds binding for start / duration, snapped to whole frames.
        func timeBinding(_ keyPath: WritableKeyPath<LayerCore, ProjectTime>, minimum: Double) -> Binding<Double> {
            Binding(
                get: { [weak self] in self?.selectedCores.first?[keyPath: keyPath].seconds ?? 0 },
                set: { [weak self] seconds in
                    guard let self else { return }
                    let fps = self.project.fps
                    let value = ProjectTime(seconds: max(minimum, seconds)).quantized(fps: fps)
                    let ids = self.editableSelection
                    self.mutate { project in
                        for id in ids { project.updateCore(id) { $0[keyPath: keyPath] = value } }
                    }
                }
            )
        }

        func selectedTextLayer() -> TextLayer? {
            project.texts.first { selection.contains($0.core.id) }
        }

        func selectedPhotoLayer() -> PhotoLayer? {
            project.photos.first { selection.contains($0.core.id) }
        }

        func textBinding<T>(_ keyPath: WritableKeyPath<TextLayer, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedTextLayer()?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for i in project.texts.indices where ids.contains(project.texts[i].core.id) {
                            project.texts[i][keyPath: keyPath] = value
                        }
                    }
                }
            )
        }

        func photoBinding<T>(_ keyPath: WritableKeyPath<PhotoLayer, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedPhotoLayer()?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for i in project.photos.indices where ids.contains(project.photos[i].core.id) {
                            project.photos[i][keyPath: keyPath] = value
                        }
                    }
                }
            )
        }

        // MARK: Timeline zoom

        func zoom(by factor: Double) { scale.pixelsPerSecond *= factor }

        func fitTimeline(width: Double) {
            scale = TimelineScale.fitting(duration: project.duration, width: width)
        }

        // MARK: Photos

        func importPhotos(_ items: [PhotosPickerItem]) async {
            guard !items.isEmpty, !isImporting else { return }
            isImporting = true
            statusMessage = nil
            let projectID = project.id
            let manager = self.manager
            var imported: [TimelineEngine.ImportedPhoto] = []
            var failed = 0
            for (index, item) in items.enumerated() {
                importProgress = "Đang nhập \(index + 1)/\(items.count)…"
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { failed += 1; continue }
                    let photo = try await Task.detached(priority: .userInitiated) {
                        try manager.storeImage(data: data, projectID: projectID)
                    }.value
                    imported.append(photo)
                } catch {
                    failed += 1
                }
            }
            if !imported.isEmpty, project.id == projectID {
                var created: [UUID] = []
                edit { created = TimelineEngine.appendPhotos(imported, to: &$0) }
                selection = Set(created)
                prefetch(around: playback.state.frameTime)
            }
            statusMessage = failed > 0 ? "Không nhập được \(failed) ảnh." : nil
            importProgress = ""
            isImporting = false
        }

        /// Decode the photos about to appear so they are on screen without a blank frame.
        func prefetch(around time: ProjectTime, lookAhead: Double = 3, maxPixel: Int = 1536) {
            let until = time + ProjectTime(seconds: lookAhead)
            let urls = project.photos
                .filter { $0.core.isVisible && $0.core.start < until && $0.core.end > time }
                .map { mediaURL(for: $0) }
            PhotoImageCache.shared.prefetch(urls, maxPixel: maxPixel)
        }

        // MARK: Audio and vinyl

        func importAudio(from url: URL) async {
            guard !isImporting else { return }
            isImporting = true
            importProgress = "Đang nhập nhạc…"
            let projectID = project.id
            do {
                let imported = try await manager.storeAudio(from: url, projectID: projectID)
                guard project.id == projectID else { isImporting = false; return }
                var created: UUID?
                let time = project.audios.isEmpty ? ProjectTime.zero : playback.state.frameTime
                edit { created = TimelineEngine.addAudio(imported, at: time, to: &$0) }
                if let created { selection = [created] }
                statusMessage = nil
            } catch {
                statusMessage = error.localizedDescription
            }
            importProgress = ""
            isImporting = false
        }

        func addVinyl() {
            let cover = selectedPhotoLayer()?.mediaFile ?? project.photos.first?.mediaFile
            let time = playback.state.frameTime
            var created: UUID?
            edit { created = TimelineEngine.addVinyl(at: time, coverFile: cover, to: &$0) }
            if let created { selection = [created] }
        }

        func fitPhotosToAudio() {
            guard let audio = selectedAudioLayer() ?? project.audios.first else { return }
            let seconds = audio.core.duration.seconds
            edit { TimelineEngine.fitPhotos(toDuration: seconds, in: &$0) }
        }

        func selectedAudioLayer() -> AudioLayer? { project.audios.first { selection.contains($0.core.id) } }
        func selectedVinylLayer() -> VinylLayer? { project.vinyls.first { selection.contains($0.core.id) } }

        func audioBinding<T>(_ keyPath: WritableKeyPath<AudioLayer, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedAudioLayer()?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for i in project.audios.indices where ids.contains(project.audios[i].core.id) {
                            project.audios[i][keyPath: keyPath] = value
                        }
                    }
                }
            )
        }

        func vinylBinding<T>(_ keyPath: WritableKeyPath<VinylLayer, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedVinylLayer()?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for i in project.vinyls.indices where ids.contains(project.vinyls[i].core.id) {
                            project.vinyls[i][keyPath: keyPath] = value
                        }
                    }
                }
            )
        }

        /// Trim handle drag on the audio trimmer (continuous: call `beginEdit()` first).
        func setAudioTrim(_ id: UUID, sourceStart: Double, sourceEnd: Double) {
            mutate { _ = TimelineEditing.setAudioTrim(id, sourceStart: sourceStart, sourceEnd: sourceEnd, in: &$0) }
        }

        /// Timeline lanes that exist right now: the always-visible ones plus any with layers.
        var visibleTracks: [TrackKind] {
            let used = Set(project.allCores.map(\.track))
            return TrackKind.allCases.filter { $0.alwaysVisible || used.contains($0) }
        }

        var timelineHeight: CGFloat {
            min(300, TimelineRulerView.height + 48 * CGFloat(visibleTracks.count) + 44)
        }

        // MARK: Lyrics

        func lyrics(_ id: UUID) -> LyricsLayer? { project.lyrics.first { $0.core.id == id } }
        func selectedLyricsLayer() -> LyricsLayer? { project.lyrics.first { selection.contains($0.core.id) } }

        func addLyrics() {
            guard let audio = selectedAudioLayer() ?? project.audios.first else {
                statusMessage = "Thêm nhạc trước, rồi thêm lời bài hát."
                return
            }
            var created: UUID?
            edit { created = TimelineEngine.addLyrics([], audioID: audio.core.id, to: &$0) }
            if let created { selection = [created]; lyricsEditorLayerID = created }
        }

        func lyricsBinding<T>(_ keyPath: WritableKeyPath<LyricsLayer, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedLyricsLayer()?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for i in project.lyrics.indices where ids.contains(project.lyrics[i].core.id) {
                            project.lyrics[i][keyPath: keyPath] = value
                        }
                    }
                }
            )
        }

        /// Change one lyrics layer. `checkpoint: false` while dragging (call `beginEdit()` first).
        func updateLyrics(_ id: UUID, checkpoint: Bool = true, _ change: (inout LyricsLayer) -> Void) {
            let apply: (inout VideoProject) -> Void = { project in
                guard let i = project.lyrics.firstIndex(where: { $0.core.id == id }), !project.lyrics[i].core.isLocked else { return }
                change(&project.lyrics[i])
            }
            if checkpoint { edit(apply) } else { mutate(apply) }
        }

        /// Source-file range the lyrics' linked audio plays (what plain lyrics are spread over).
        func lyricsSourceRange(_ layer: LyricsLayer) -> (start: Double, duration: Double) {
            if let id = layer.audioLayerID, let audio = project.audios.first(where: { $0.core.id == id }) {
                return (audio.sourceStart, max(0.5, min(audio.availableSource, audio.core.duration.seconds)))
            }
            return (0, max(0.5, layer.core.duration.seconds))
        }

        func distributePlainLyrics(_ text: String, into id: UUID) {
            guard let layer = lyrics(id) else { return }
            let range = lyricsSourceRange(layer)
            let lines = PlainLyrics.distribute(text, start: range.start, duration: range.duration)
            guard !lines.isEmpty else { statusMessage = "Chưa có lời để chia."; return }
            updateLyrics(id) { $0.lines = lines }
            statusMessage = nil
        }

        /// Imports `.lrc`, `.srt` or plain text.
        func importLyricsFile(_ url: URL, into id: UUID) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                statusMessage = "Không đọc được tệp lời."
                return
            }
            var lines: [LyricLine]
            switch url.pathExtension.lowercased() {
            case "srt": lines = SRTParser.parse(text)
            case "lrc": lines = LRCParser.parse(text)
            default:
                lines = LRCParser.parse(text)
                if lines.isEmpty { lines = SRTParser.parse(text) }
            }
            if lines.isEmpty { distributePlainLyrics(text, into: id); return }
            updateLyrics(id) { $0.lines = LyricsSynchronizer.normalized(lines) }
            statusMessage = nil
        }

        func shiftLyrics(_ id: UUID, by seconds: Double) {
            updateLyrics(id) { $0.lines = LyricsSynchronizer.shift($0.lines, by: seconds) }
        }

        /// Recognise the linked audio with `recognizer`, then either align the typed rows to it
        /// or, with no rows, use the recognised words as the lyrics.
        func recognizeLyrics(_ id: UUID, rows: [String], recognizer: LyricsRecognizer = SpeechLyricsRecognizer(),
                             locale: Locale = Locale(identifier: "vi-VN")) async {
            guard lyricsBusy.isEmpty, let layer = lyrics(id),
                  let audioID = layer.audioLayerID, let audio = project.audios.first(where: { $0.core.id == audioID }) else {
                statusMessage = "Lớp lời cần gắn với một clip nhạc."
                return
            }
            lyricsBusy = "Đang nhận diện bằng \(recognizer.name)…"
            defer { lyricsBusy = "" }
            let url = manager.mediaURL(projectID: project.id, file: audio.mediaFile)
            let range = lyricsSourceRange(layer)
            do {
                let words = try await recognizer.recognize(audioURL: url, from: range.start, to: range.start + range.duration, locale: locale)
                guard !words.isEmpty else { statusMessage = "Không nhận ra từ nào (nhạc quá lớn hoặc không có giọng)."; return }
                let lines = rows.isEmpty ? LyricsAligner.lines(from: words) : LyricsAligner.align(rows: rows, recognized: words)
                guard !lines.isEmpty else { statusMessage = "Không khớp được lời với giọng hát."; return }
                updateLyrics(id) { $0.lines = lines }
                statusMessage = "Đã nhận \(words.count) từ. Hãy tinh chỉnh mốc thời gian nếu cần."
            } catch {
                statusMessage = error.localizedDescription
            }
        }

        func exportLRC(_ id: UUID) -> URL? {
            guard let layer = lyrics(id), !layer.lines.isEmpty else { return nil }
            let url = MediaStorage.exportsDirectory.appendingPathComponent("\(project.name)-\(layer.core.name).lrc")
            do {
                try LRCWriter.string(layer.lines, title: project.name).write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                statusMessage = "Không ghi được tệp LRC."
                return nil
            }
        }

        // MARK: Visualizer + beats

        func selectedVisualizerLayer() -> VisualizerLayer? { project.visualizers.first { selection.contains($0.core.id) } }

        private func audioFile(for layer: VisualizerLayer) -> String? {
            layer.audioLayerID.flatMap { id in project.audios.first { $0.core.id == id }?.mediaFile }
        }

        /// The analysed spectrum for the layer's audio, once it has finished loading.
        func spectrum(for layer: VisualizerLayer) -> SpectrumData? {
            audioFile(for: layer).flatMap { spectra[$0] }
        }

        /// Starts the (one-off, cached) analysis of every audio file a visualizer uses.
        /// Audio files whose analysis something on the timeline needs (visualizers, beat effects).
        private func spectrumAudioFiles() -> [String] {
            var ids: [UUID] = project.visualizers.compactMap(\.audioLayerID)
            ids += project.effects.filter { $0.kind.needsAudio }.compactMap(\.audioLayerID)
            var files: [String] = []
            for id in ids {
                if let file = project.audios.first(where: { $0.core.id == id })?.mediaFile, !files.contains(file) { files.append(file) }
            }
            return files
        }

        func prepareSpectra() {
            for file in spectrumAudioFiles() {
                guard spectra[file] == nil, spectrumRequests.insert(file).inserted else { continue }
                let url = manager.mediaURL(projectID: project.id, file: file)
                Task { [weak self] in
                    let value = await SpectrumCache.shared.spectrum(for: url)
                    guard let self else { return }
                    self.spectrumRequests.remove(file)
                    if let value { self.spectra[file] = value; self.spectrumVersion += 1 }
                    else { self.statusMessage = "Không phân tích được âm thanh cho visualizer." }
                }
            }
        }

        /// Spectra of every visualizer's audio, awaiting analysis if needed (used by export).
        func loadSpectra() async -> [String: SpectrumData] {
            var result: [String: SpectrumData] = [:]
            for file in spectrumAudioFiles() {
                if let known = spectra[file] { result[file] = known; continue }
                if let value = await SpectrumCache.shared.spectrum(for: manager.mediaURL(projectID: project.id, file: file)) {
                    spectra[file] = value
                    result[file] = value
                }
            }
            return result
        }

        func spectrumByAudioID(for layer: VisualizerLayer, in loaded: [String: SpectrumData]) -> SpectrumData? {
            audioFile(for: layer).flatMap { loaded[$0] }
        }

        func addVisualizer() {
            guard let audio = selectedAudioLayer() ?? project.audios.first else {
                statusMessage = "Thêm nhạc trước, rồi thêm visualizer."
                return
            }
            var created: UUID?
            edit { created = TimelineEngine.addVisualizer(audioID: audio.core.id, to: &$0) }
            if let created { selection = [created] }
        }

        func visualizerBinding<T>(_ keyPath: WritableKeyPath<VisualizerLayer, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedVisualizerLayer()?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for i in project.visualizers.indices where ids.contains(project.visualizers[i].core.id) {
                            project.visualizers[i][keyPath: keyPath] = value
                        }
                    }
                }
            )
        }

        /// Re-times the photos so every `n`-th beat of the music starts a new photo.
        func cutPhotosOnBeats(every n: Int) async {
            guard let audio = selectedAudioLayer() ?? project.audios.first else { return }
            statusMessage = "Đang phân tích nhịp…"
            let url = manager.mediaURL(projectID: project.id, file: audio.mediaFile)
            guard let data = await SpectrumCache.shared.spectrum(for: url), !data.beats.isEmpty else {
                statusMessage = "Không tìm thấy nhịp rõ ràng trong bài này."
                return
            }
            let offset = audio.core.start.seconds - audio.sourceStart
            let cuts = BeatMath.cutTimes(beats: data.beats.map { $0 + offset }, every: n,
                                         from: audio.core.start.seconds, to: audio.core.end.seconds)
            guard cuts.count >= 2 else { statusMessage = nil; return }
            edit { TimelineEngine.fitPhotos(toCuts: cuts, in: &$0) }
            statusMessage = "Đã cắt ảnh theo \(cuts.count - 1) đoạn nhịp."
        }

        // MARK: Effects

        func selectedEffectLayer() -> EffectLayer? { project.effects.first { selection.contains($0.core.id) } }

        func addEffect(_ kind: EffectKind) {
            let audio = selectedAudioLayer() ?? project.audios.first
            if kind.needsAudio && audio == nil {
                statusMessage = "Hiệu ứng theo nhịp cần nhạc: thêm nhạc trước."
                return
            }
            var created: UUID?
            edit { created = TimelineEngine.addEffect(kind, audioID: audio?.core.id, to: &$0) }
            if let created { selection = [created] }
        }

        func effectBinding<T>(_ keyPath: WritableKeyPath<EffectLayer, T>, fallback: T) -> Binding<T> {
            Binding(
                get: { [weak self] in self?.selectedEffectLayer()?[keyPath: keyPath] ?? fallback },
                set: { [weak self] value in
                    guard let self else { return }
                    let ids = self.editableSelection
                    self.mutate { project in
                        for i in project.effects.indices where ids.contains(project.effects[i].core.id) {
                            project.effects[i][keyPath: keyPath] = value
                        }
                    }
                }
            )
        }

        /// Beats (project seconds) that drive a beat effect: the linked clip's beats, every n-th.
        func effectBeats(for layer: EffectLayer) -> [Double] {
            guard layer.kind.needsAudio, let id = layer.audioLayerID,
                  let audio = project.audios.first(where: { $0.core.id == id }),
                  let data = spectra[audio.mediaFile] else { return [] }
            return EffectMath.projectBeats(fileBeats: data.beats, offset: audio.core.start.seconds - audio.sourceStart,
                                           from: audio.core.start.seconds, to: audio.core.end.seconds, every: layer.everyBeats)
        }

        /// Shake / Beat Pulse motion for the pictures at `time` (shared by preview and export).
        func sceneMotion(items: [RenderItem], at time: ProjectTime) -> SceneMotion {
            let effects = items.compactMap { item -> EffectLayer? in
                if case .effect(let layer) = item { return layer }
                return nil
            }
            guard !effects.isEmpty else { return .identity }
            return EffectMath.sceneMotion(effects: effects, at: time, beats: { effectBeats(for: $0) })
        }

        // MARK: Persistence

        private func scheduleSave() {
            saveTask?.cancel()
            let snapshot = project
            let manager = self.manager
            saveTask = Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                try? manager.save(snapshot)
            }
        }

        func saveNow() {
            saveTask?.cancel()
            do {
                try manager.save(project)
                statusMessage = "Đã lưu \"\(project.name)\"."
            } catch {
                statusMessage = "Không lưu được: \(error.localizedDescription)"
            }
        }

        func newProject() {
            saveNow()
            playback.pause()
            history.clear()
            selection.removeAll()
            project = VideoProject()
            playback.configure(duration: project.duration, fps: project.fps)
            playback.seek(to: .zero)
            syncAudio()
            prepareSpectra()
            try? manager.save(project)
        }

        func open(_ id: UUID) {
            guard id != project.id, let loaded = try? manager.load(id) else { return }
            saveNow()
            playback.pause()
            history.clear()
            selection.removeAll()
            project = loaded
            playback.configure(duration: project.duration, fps: project.fps)
            playback.seek(to: .zero)
            syncAudio()
            prepareSpectra()
            statusMessage = nil
        }

        func recentProjects() -> [ProjectSummary] { manager.list() }
    }
}
