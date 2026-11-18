import Foundation

extension MusicVideoStudio {
    /// What the preview (and later the exporter) draws for one layer.
    enum RenderItem: Identifiable, Hashable {
        case photo(PhotoLayer)
        case text(TextLayer)

        var id: UUID { core.id }

        var core: LayerCore {
            switch self {
            case .photo(let layer): return layer.core
            case .text(let layer): return layer.core
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
