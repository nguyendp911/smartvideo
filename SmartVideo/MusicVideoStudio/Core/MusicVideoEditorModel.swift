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

        let playback = PlaybackEngine()
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
            project = next
            playback.configure(duration: project.duration, fps: project.fps)
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
            statusMessage = nil
        }

        func recentProjects() -> [ProjectSummary] { manager.list() }
    }
}
