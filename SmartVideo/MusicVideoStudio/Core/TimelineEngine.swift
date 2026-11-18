import Foundation

extension MusicVideoStudio {
    /// What the preview (and later the exporter) draws for one layer.
    enum RenderItem: Identifiable, Hashable {
        case photo(PhotoLayer)
        case text(TextLayer)
        case vinyl(VinylLayer)
        case lyrics(LyricsLayer)
        case visualizer(VisualizerLayer)

        var id: UUID { core.id }

        var core: LayerCore {
            switch self {
            case .photo(let layer): return layer.core
            case .text(let layer): return layer.core
            case .vinyl(let layer): return layer.core
            case .lyrics(let layer): return layer.core
            case .visualizer(let layer): return layer.core
            }
        }
    }

    /// Pure timeline logic over a `VideoProject`. The preview and the exporter
    /// call the SAME functions, so both follow identical timing and z-order rules.
    enum TimelineEngine {
        static let defaultPhotoDuration = ProjectTime(seconds: 3)
        static let defaultTextDuration = ProjectTime(seconds: 3)

        /// Layers visible at `time`, bottom first (z-index, then creation order).
        static func renderItems(in project: VideoProject, at time: ProjectTime) -> [RenderItem] {
            var items: [(order: Int, item: RenderItem)] = []
            for (i, layer) in project.photos.enumerated() where layer.core.isActive(at: time) {
                items.append((i, .photo(layer)))
            }
            for (i, layer) in project.texts.enumerated() where layer.core.isActive(at: time) {
                items.append((project.photos.count + i, .text(layer)))
            }
            for (i, layer) in project.vinyls.enumerated() where layer.core.isActive(at: time) {
                items.append((project.photos.count + project.texts.count + i, .vinyl(layer)))
            }
            for (i, layer) in project.lyrics.enumerated() where layer.core.isActive(at: time) {
                items.append((project.photos.count + project.texts.count + project.vinyls.count + i, .lyrics(layer)))
            }
            for (i, layer) in project.visualizers.enumerated() where layer.core.isActive(at: time) {
                items.append((project.photos.count + project.texts.count + project.vinyls.count + project.lyrics.count + i, .visualizer(layer)))
            }
            return items.sorted {
                $0.item.core.zIndex != $1.item.core.zIndex
                    ? $0.item.core.zIndex < $1.item.core.zIndex
                    : $0.order < $1.order
            }.map(\.item)
        }

        static func activeLayerIDs(in project: VideoProject, at time: ProjectTime) -> [UUID] {
            renderItems(in: project, at: time).map(\.id)
        }

        /// Blocks for the timeline UI: grouped by track order, then by start.
        static func clips(in project: VideoProject) -> [TimelineClip] {
            let order = TrackKind.allCases
            func clip(_ core: LayerCore) -> TimelineClip {
                TimelineClip(id: core.id, track: core.track, title: core.name, range: core.range,
                             isVisible: core.isVisible, isLocked: core.isLocked)
            }
            return project.allCores.map(clip).sorted {
                let a = order.firstIndex(of: $0.track) ?? 0, b = order.firstIndex(of: $1.track) ?? 0
                return a != b ? a < b : $0.range.start < $1.range.start
            }
        }

        static func clips(in project: VideoProject, track: TrackKind) -> [TimelineClip] {
            clips(in: project).filter { $0.track == track }
        }

        // MARK: Editing

        struct ImportedPhoto: Equatable {
            var mediaFile: String
            var pixelWidth: Int
            var pixelHeight: Int
        }

        /// Appends photos back to back after the last photo (or at 0).
        @discardableResult
        static func appendPhotos(_ photos: [ImportedPhoto], to project: inout VideoProject,
                                 duration: ProjectTime = defaultPhotoDuration) -> [UUID] {
            var ids: [UUID] = []
            var cursor = project.photos.map(\.core.end).max() ?? .zero
            for photo in photos {
                guard project.layerCount < VideoProject.maxLayers else { break }
                let core = LayerCore(
                    name: "Ảnh \(project.photos.count + 1)", track: .photo,
                    start: cursor, duration: duration,
                    zIndex: project.nextZIndex(for: .photo)
                )
                project.photos.append(PhotoLayer(core: core, mediaFile: photo.mediaFile,
                                                 pixelWidth: photo.pixelWidth, pixelHeight: photo.pixelHeight))
                ids.append(core.id)
                cursor = cursor + duration
            }
            return ids
        }

        @discardableResult
        static func addText(_ text: String, at time: ProjectTime, to project: inout VideoProject) -> UUID? {
            guard project.layerCount < VideoProject.maxLayers else { return nil }
            var core = LayerCore(
                name: "Chữ \(project.texts.count + 1)", track: .text,
                start: time.clamped(.zero, project.duration), duration: defaultTextDuration,
                zIndex: project.nextZIndex(for: .text)
            )
            core.transform.y = 0.5
            project.texts.append(TextLayer(core: core, text: text))
            return core.id
        }

        static let maxAudioSeconds = 3_600.0

        /// Adds an audio clip at `time` covering the whole file (capped at an hour).
        @discardableResult
        static func addAudio(_ audio: ProjectManager.ImportedAudio, at time: ProjectTime, to project: inout VideoProject) -> UUID? {
            guard project.layerCount < VideoProject.maxLayers else { return nil }
            let length = min(audio.duration, maxAudioSeconds)
            let core = LayerCore(name: audio.originalName, track: .audio,
                                 start: max(.zero, time).quantized(fps: project.fps),
                                 duration: ProjectTime(seconds: length), zIndex: 0)
            project.audios.append(AudioLayer(core: core, mediaFile: audio.mediaFile,
                                             originalName: audio.originalName, sourceDuration: audio.duration))
            return core.id
        }

        /// A record in the middle of the canvas for `duration` (the project length when nil).
        @discardableResult
        static func addVinyl(at time: ProjectTime, duration: ProjectTime? = nil, coverFile: String?,
                             to project: inout VideoProject) -> UUID? {
            guard project.layerCount < VideoProject.maxLayers else { return nil }
            let start = max(.zero, time).quantized(fps: project.fps)
            let length = duration ?? max(defaultTextDuration, project.duration - start)
            let core = LayerCore(name: "Đĩa than \(project.vinyls.count + 1)", track: .vinyl,
                                 start: start, duration: length, zIndex: project.nextZIndex(for: .vinyl))
            project.vinyls.append(VinylLayer(core: core, coverFile: coverFile))
            return core.id
        }

        /// A lyrics layer covering `audioID`'s clip (or the whole project). `lines` are in the audio FILE's time.
        @discardableResult
        static func addLyrics(_ lines: [LyricLine], audioID: UUID?, to project: inout VideoProject) -> UUID? {
            guard project.layerCount < VideoProject.maxLayers else { return nil }
            let audio = audioID.flatMap { id in project.audios.first { $0.core.id == id } }
            var core = LayerCore(name: "Lời \(project.lyrics.count + 1)", track: .lyrics,
                                 start: audio?.core.start ?? .zero,
                                 duration: audio?.core.duration ?? max(defaultTextDuration, project.duration),
                                 zIndex: project.nextZIndex(for: .lyrics))
            core.transform.y = 0.78                           // lower third, like subtitles
            project.lyrics.append(LyricsLayer(core: core, lines: lines, audioLayerID: audio?.core.id))
            return core.id
        }

        /// A visualizer for `audioID`'s clip, centred in the lower half of the canvas.
        @discardableResult
        static func addVisualizer(audioID: UUID?, to project: inout VideoProject) -> UUID? {
            guard project.layerCount < VideoProject.maxLayers else { return nil }
            let audio = audioID.flatMap { id in project.audios.first { $0.core.id == id } }
            var core = LayerCore(name: "Visualizer \(project.visualizers.count + 1)", track: .visualizer,
                                 start: audio?.core.start ?? .zero,
                                 duration: audio?.core.duration ?? max(defaultTextDuration, project.duration),
                                 zIndex: project.nextZIndex(for: .visualizer))
            core.transform.y = 0.72
            project.visualizers.append(VisualizerLayer(core: core, audioLayerID: audio?.core.id))
            return core.id
        }

        /// Puts the unlocked photos, in timeline order, between consecutive cut times (project
        /// seconds). Extra photos continue after the last cut; a last photo stretches to the final cut.
        static func fitPhotos(toCuts cuts: [Double], in project: inout VideoProject) {
            let order = TimelineEditing.orderedPhotoIDs(in: project).compactMap { id in
                project.photos.firstIndex { $0.core.id == id && !$0.core.isLocked }
            }
            guard cuts.count >= 2, !order.isEmpty else { return }
            let fps = project.fps
            let intervals = cuts.count - 1
            var tail = ProjectTime(seconds: cuts[cuts.count - 1]).quantized(fps: fps)
            for (slot, index) in order.enumerated() {
                if slot < intervals {
                    let start = ProjectTime(seconds: cuts[slot]).quantized(fps: fps)
                    let endSeconds = slot == order.count - 1 ? cuts[cuts.count - 1] : cuts[slot + 1]
                    let end = ProjectTime(seconds: endSeconds).quantized(fps: fps)
                    project.photos[index].core.start = start
                    project.photos[index].core.duration = max(LayerCore.minimumDuration, end - start)
                } else {
                    project.photos[index].core.start = tail
                    tail = tail + project.photos[index].core.duration
                }
            }
        }

        /// Spreads the photos evenly across the music (`seconds`) and packs them.
        static func fitPhotos(toDuration seconds: Double, in project: inout VideoProject) {
            let count = max(1, project.photos.filter { !$0.core.isLocked }.count)
            let each = max(LayerCore.minimumDuration.seconds, seconds / Double(count))
            TimelineEditing.setAllPhotoDurations(ProjectTime(seconds: each), in: &project)
        }

        /// Copies are placed right after the original on the same track.
        @discardableResult
        static func duplicate(_ ids: Set<UUID>, in project: inout VideoProject) -> [UUID] {
            var created: [UUID] = []
            for layer in project.photos where ids.contains(layer.core.id) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var copy = layer
                copy.core.id = UUID()
                copy.core.name = layer.core.name + " (bản sao)"
                copy.core.start = layer.core.end
                copy.core.isLocked = false
                copy.core.zIndex = project.nextZIndex(for: .photo)
                project.photos.append(copy)
                created.append(copy.core.id)
            }
            for layer in project.texts where ids.contains(layer.core.id) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var copy = layer
                copy.core.id = UUID()
                copy.core.name = layer.core.name + " (bản sao)"
                copy.core.start = layer.core.end
                copy.core.isLocked = false
                copy.core.zIndex = project.nextZIndex(for: .text)
                project.texts.append(copy)
                created.append(copy.core.id)
            }
            for layer in project.audios where ids.contains(layer.core.id) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var copy = layer
                copy.core.id = UUID()
                copy.core.name = layer.core.name + " (bản sao)"
                copy.core.start = layer.core.end
                copy.core.isLocked = false
                project.audios.append(copy)
                created.append(copy.core.id)
            }
            for layer in project.visualizers where ids.contains(layer.core.id) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var copy = layer
                copy.core.id = UUID()
                copy.core.name = layer.core.name + " (bản sao)"
                copy.core.isLocked = false
                copy.core.zIndex = project.nextZIndex(for: .visualizer)
                project.visualizers.append(copy)
                created.append(copy.core.id)
            }
            for layer in project.lyrics where ids.contains(layer.core.id) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var copy = layer
                copy.core.id = UUID()
                copy.core.name = layer.core.name + " (bản sao)"
                copy.core.isLocked = false
                copy.core.zIndex = project.nextZIndex(for: .lyrics)
                project.lyrics.append(copy)
                created.append(copy.core.id)
            }
            for layer in project.vinyls where ids.contains(layer.core.id) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var copy = layer
                copy.core.id = UUID()
                copy.core.name = layer.core.name + " (bản sao)"
                copy.core.start = layer.core.end
                copy.core.isLocked = false
                copy.core.zIndex = project.nextZIndex(for: .vinyl)
                project.vinyls.append(copy)
                created.append(copy.core.id)
            }
            return created
        }

        static func resetTransform(_ ids: Set<UUID>, in project: inout VideoProject) {
            for id in ids {
                project.updateCore(id) { if !$0.isLocked { $0.transform = .identity } }
            }
        }

        /// Layers that can be edited right now (exist and are unlocked).
        static func editable(_ ids: Set<UUID>, in project: VideoProject) -> Set<UUID> {
            Set(project.allCores.filter { ids.contains($0.id) && !$0.isLocked }.map(\.id))
        }
    }
}
