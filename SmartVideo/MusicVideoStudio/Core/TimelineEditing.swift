import Foundation

extension MusicVideoStudio {
    enum TrimEdge { case start, end }

    /// Pure timeline editing: moving, trimming, splitting, snapping, ripple
    /// delete and photo ordering. Locked layers are never touched. Every
    /// result is snapped to whole frames of the project frame rate.
    enum TimelineEditing {
        static let minimumDuration = LayerCore.minimumDuration

        // MARK: Snapping

        /// Times a dragged edge may snap to: zero, the playhead, the project
        /// end, every OTHER layer's start and end, plus caller-supplied points
        /// (beats, once audio exists).
        static func snapPoints(in project: VideoProject, excluding: Set<UUID>, playhead: ProjectTime,
                               extra: [ProjectTime] = []) -> [ProjectTime] {
            var points: [ProjectTime] = [.zero, playhead]
            for core in project.allCores where !excluding.contains(core.id) {
                points.append(core.start)
                points.append(core.end)
            }
            points.append(contentsOf: extra)
            return Array(Set(points)).sorted()
        }

        /// Nearest point within `threshold`, if any.
        static func nearest(to time: ProjectTime, in points: [ProjectTime], threshold: ProjectTime) -> ProjectTime? {
            var best: (ProjectTime, Int64)?
            for point in points {
                let distance = abs(point.ticks - time.ticks)
                if distance <= threshold.ticks, best == nil || distance < best!.1 { best = (point, distance) }
            }
            return best?.0
        }

        // MARK: Move

        /// Moves every origin range by `delta` as ONE group (relative offsets are kept),
        /// never before time zero. Returns the point the group snapped to, for the guide line.
        @discardableResult
        static func move(origins: [UUID: TimeRange], delta: ProjectTime, in project: inout VideoProject,
                         snapPoints points: [ProjectTime], threshold: ProjectTime) -> ProjectTime? {
            let editable = editableIDs(Set(origins.keys), in: project)
            let live = origins.filter { editable.contains($0.key) }
            guard !live.isEmpty else { return nil }
            let earliest = live.values.map(\.start).min() ?? .zero
            let base = max(delta, ProjectTime.zero - earliest)

            // Snap the group's leading or trailing edges, whichever is closest.
            var snappedTo: ProjectTime?
            var adjust = ProjectTime.zero
            var bestDistance = Int64.max
            for range in live.values {
                for edge in [range.start + base, range.end + base] {
                    if let point = nearest(to: edge, in: points, threshold: threshold) {
                        let distance = abs(point.ticks - edge.ticks)
                        if distance < bestDistance {
                            bestDistance = distance
                            snappedTo = point
                            adjust = point - edge
                        }
                    }
                }
            }
            let shift = max(base + adjust, ProjectTime.zero - earliest)
            let fps = project.fps
            for (id, range) in live {
                let start = (range.start + shift).quantized(fps: fps)
                project.updateCore(id) { $0.start = start }
            }
            return snappedTo
        }

        // MARK: Trim

        /// Trims one edge of a layer. Photos and text are stills, so trimming
        /// only changes the range (no source offset).
        @discardableResult
        static func trim(id: UUID, origin: TimeRange, edge: TrimEdge, delta: ProjectTime,
                         in project: inout VideoProject, snapPoints points: [ProjectTime],
                         threshold: ProjectTime) -> ProjectTime? {
            guard let core = project.core(for: id), !core.isLocked else { return nil }
            let fps = project.fps
            var snappedTo: ProjectTime?
            switch edge {
            case .start:
                var start = origin.start + delta
                if let point = nearest(to: start, in: points, threshold: threshold) { start = point; snappedTo = point }
                start = start.clamped(.zero, origin.end - minimumDuration).quantized(fps: fps)
                // Trimming the HEAD of audio keeps the music aligned: the trim
                // point inside the file moves by the same amount (never below 0).
                if let a = project.audios.firstIndex(where: { $0.core.id == id }) {
                    let shift = (start - core.start).seconds
                    let newSource = project.audios[a].sourceStart + shift
                    if newSource < 0 { start = start - ProjectTime(seconds: newSource); project.audios[a].sourceStart = 0 }
                    else { project.audios[a].sourceStart = newSource }
                }
                let duration = origin.end - start
                project.updateCore(id) { $0.start = start; $0.duration = duration }
            case .end:
                var end = origin.end + delta
                if let point = nearest(to: end, in: points, threshold: threshold) { end = point; snappedTo = point }
                end = max(end, origin.start + minimumDuration).quantized(fps: fps)
                let duration = max(minimumDuration, end - origin.start)
                project.updateCore(id) { $0.duration = duration }
            }
            return snappedTo
        }

        // MARK: Audio trim (source range)

        /// Sets which part of the FILE plays (`sourceStart`...`sourceEnd`, seconds).
        /// A non-looping clip's length follows; a looping clip keeps its length.
        @discardableResult
        static func setAudioTrim(_ id: UUID, sourceStart: Double, sourceEnd: Double, in project: inout VideoProject) -> Bool {
            guard let i = project.audios.firstIndex(where: { $0.core.id == id }), !project.audios[i].core.isLocked else { return false }
            let total = project.audios[i].sourceDuration
            let start = min(max(0, sourceStart.isFinite ? sourceStart : 0), max(0, total - minimumDuration.seconds))
            let end = min(total, max(start + minimumDuration.seconds, sourceEnd.isFinite ? sourceEnd : total))
            project.audios[i].sourceStart = start
            if !project.audios[i].loops {
                project.audios[i].core.duration = ProjectTime(seconds: end - start).quantized(fps: project.fps)
            }
            return true
        }

        // MARK: Split

        /// Cuts every editable layer that is active at `time` (with at least the
        /// minimum duration on both sides) in two. Returns the new second halves.
        @discardableResult
        static func split(_ ids: Set<UUID>, at time: ProjectTime, in project: inout VideoProject) -> [UUID] {
            let cut = time.quantized(fps: project.fps)
            let editable = editableIDs(ids, in: project)
            var created: [UUID] = []

            func canSplit(_ core: LayerCore) -> Bool {
                editable.contains(core.id) && cut >= core.start + minimumDuration && cut <= core.end - minimumDuration
            }
            for i in project.photos.indices where canSplit(project.photos[i].core) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var right = project.photos[i]
                let end = right.core.end
                project.photos[i].core.duration = cut - project.photos[i].core.start
                right.core.id = UUID()
                right.core.name = project.photos[i].core.name + " (2)"
                right.core.start = cut
                right.core.duration = end - cut
                right.transitionIn = PhotoTransition()           // a cut is a hard cut
                project.photos.append(right)
                created.append(right.core.id)
            }
            for i in project.audios.indices where canSplit(project.audios[i].core) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var right = project.audios[i]
                let end = right.core.end
                let leftLength = cut - project.audios[i].core.start
                project.audios[i].core.duration = leftLength
                right.core.id = UUID()
                right.core.name = project.audios[i].core.name + " (2)"
                right.core.start = cut
                right.core.duration = end - cut
                right.sourceStart = project.audios[i].sourceStart + leftLength.seconds     // continues where the left half stops
                right.fadeIn = 0
                project.audios[i].fadeOut = 0
                project.audios.append(right)
                created.append(right.core.id)
            }
            for i in project.vinyls.indices where canSplit(project.vinyls[i].core) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var right = project.vinyls[i]
                let end = right.core.end
                right.phase = project.vinyls[i].phase + (cut - project.vinyls[i].core.start).seconds
                project.vinyls[i].core.duration = cut - project.vinyls[i].core.start
                right.core.id = UUID()
                right.core.name = project.vinyls[i].core.name + " (2)"
                right.core.start = cut
                right.core.duration = end - cut
                project.vinyls.append(right)
                created.append(right.core.id)
            }
            for i in project.lyrics.indices where canSplit(project.lyrics[i].core) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var right = project.lyrics[i]
                let end = right.core.end
                project.lyrics[i].core.duration = cut - project.lyrics[i].core.start
                right.core.id = UUID()
                right.core.name = project.lyrics[i].core.name + " (2)"
                right.core.start = cut
                right.core.duration = end - cut
                project.lyrics.append(right)
                created.append(right.core.id)
            }
            for i in project.texts.indices where canSplit(project.texts[i].core) {
                guard project.layerCount < VideoProject.maxLayers else { break }
                var right = project.texts[i]
                let end = right.core.end
                project.texts[i].core.duration = cut - project.texts[i].core.start
                right.core.id = UUID()
                right.core.name = project.texts[i].core.name + " (2)"
                right.core.start = cut
                right.core.duration = end - cut
                project.texts.append(right)
                created.append(right.core.id)
            }
            return created
        }

        // MARK: Delete / ripple

        /// Removes the layers and closes the gap on their track: every unlocked
        /// layer of the same track that started at or after the removed one's end
        /// moves left by its length.
        static func rippleDelete(_ ids: Set<UUID>, in project: inout VideoProject) {
            let doomed = project.allCores.filter { editableIDs(ids, in: project).contains($0.id) }
                .sorted { $0.start > $1.start }
            for removed in doomed {
                project.removeLayers([removed.id])
                let shift = removed.duration
                func close(_ core: inout LayerCore) {
                    if core.track == removed.track, !core.isLocked, core.start >= removed.end {
                        core.start = max(.zero, core.start - shift)
                    }
                }
                for i in project.photos.indices { close(&project.photos[i].core) }
                for i in project.texts.indices { close(&project.texts[i].core) }
            }
        }

        // MARK: Photo order and layout

        /// Photos in play order: by start, then by creation order.
        static func orderedPhotoIDs(in project: VideoProject) -> [UUID] {
            project.photos.enumerated()
                .sorted { $0.element.core.start != $1.element.core.start
                    ? $0.element.core.start < $1.element.core.start : $0.offset < $1.offset }
                .map(\.element.core.id)
        }

        /// Lays unlocked photos out back to back in their current order. A photo
        /// with a transition overlaps the previous one by the transition length,
        /// so the incoming picture really crosses over the outgoing one.
        static func packPhotos(in project: inout VideoProject, startingAt origin: ProjectTime = .zero) {
            let order = orderedPhotoIDs(in: project).filter { id in
                project.photos.first { $0.core.id == id }?.core.isLocked == false
            }
            var cursor = origin
            var previousDuration: ProjectTime?
            let fps = project.fps
            for id in order {
                guard let i = project.photos.firstIndex(where: { $0.core.id == id }) else { continue }
                var start = cursor
                if let previousDuration, project.photos[i].transitionIn.isActive {
                    let overlap = PhotoTransitionEngine.effectiveDuration(project.photos[i].transitionIn,
                                                                         layerDuration: project.photos[i].core.duration)
                    start = cursor - min(overlap, previousDuration * 0.9)
                }
                start = max(.zero, start).quantized(fps: fps)
                project.photos[i].core.start = start
                cursor = start + project.photos[i].core.duration
                previousDuration = project.photos[i].core.duration
            }
        }

        /// Swaps a photo with its neighbour in play order, then re-packs.
        @discardableResult
        static func movePhoto(_ id: UUID, by offset: Int, in project: inout VideoProject) -> Bool {
            var order = orderedPhotoIDs(in: project)
            guard let index = order.firstIndex(of: id),
                  project.photos.first(where: { $0.core.id == id })?.core.isLocked == false else { return false }
            let target = index + offset
            guard order.indices.contains(target) else { return false }
            order.swapAt(index, target)
            // Re-assign start times in the new order using the old slots' positions.
            var slot = ProjectTime.zero
            for photoID in order {
                guard let i = project.photos.firstIndex(where: { $0.core.id == photoID }) else { continue }
                if project.photos[i].core.isLocked { continue }
                project.photos[i].core.start = slot
                slot = slot + project.photos[i].core.duration
            }
            packPhotos(in: &project)
            return true
        }

        /// Gives every unlocked photo the same length and re-packs.
        static func setAllPhotoDurations(_ duration: ProjectTime, in project: inout VideoProject) {
            let value = max(minimumDuration, duration).quantized(fps: project.fps)
            for i in project.photos.indices where !project.photos[i].core.isLocked {
                project.photos[i].core.duration = value
            }
            packPhotos(in: &project)
        }

        // MARK: Helpers

        static func editableIDs(_ ids: Set<UUID>, in project: VideoProject) -> Set<UUID> {
            TimelineEngine.editable(ids, in: project)
        }
    }
}
