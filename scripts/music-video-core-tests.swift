import Foundation
import CoreMedia

typealias MV = MusicVideoStudio

@main
struct MusicVideoCoreTests {
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6, _ note: String = "") {
        precondition(a.isFinite && abs(a - b) <= tolerance, "Expected \(b) got \(a) \(note)")
    }

    static func main() throws {
        time()
        project()
        timelineEngine()
        scale()
        undo()
        transport()
        try coding()
        editing()
        photoEffects()
        try photoCoding()
        audioMath()
        audioEditing()
        waveformAndVinyl()
        try audioCoding()
        print("music video core tests passed")
    }

    // MARK: ProjectTime

    static func time() {
        let t = MV.ProjectTime(seconds: 1.5)
        precondition(t.ticks == 90_000)
        near(t.seconds, 1.5)
        precondition(MV.ProjectTime(CMTime(value: 1, timescale: 30)).ticks == 2_000)
        precondition(MV.ProjectTime(CMTime(value: 7, timescale: 1)).ticks == 420_000)
        precondition(MV.ProjectTime(CMTime.invalid) == .zero && MV.ProjectTime(CMTime.indefinite) == .zero)
        precondition(MV.ProjectTime(seconds: .nan) == .zero && MV.ProjectTime(seconds: .infinity) == .zero)
        precondition(t.cmTime == CMTime(value: 90_000, timescale: 60_000))

        // One frame is an exact number of ticks at every supported rate.
        for fps in MV.ProjectTime.supportedFrameRates {
            precondition(Int64(MV.ProjectTime.timescale) % Int64(fps) == 0, "fps \(fps) not exact")
            precondition(MV.ProjectTime(seconds: 1).frameIndex(fps: fps) == fps)
            precondition(MV.ProjectTime.frame(fps, fps: fps) == MV.ProjectTime(seconds: 1))
        }
        precondition(MV.ProjectTime(ticks: 2_094).quantized(fps: 30).ticks == 2_000)
        precondition(MV.ProjectTime(ticks: 1_999).quantized(fps: 30).ticks == 0)
        precondition(MV.ProjectTime(ticks: -5).quantized(fps: 30) == .zero)

        precondition(MV.ProjectTime(seconds: 83.5).timecode(fps: 30) == "01:23:15")
        precondition(MV.ProjectTime.zero.timecode(fps: 30) == "00:00:00")
        precondition(MV.ProjectTime(seconds: 3_600).timecode(fps: 24) == "1:00:00:00")
        precondition(MV.ProjectTime(seconds: 59.999).timecode(fps: 60).hasPrefix("00:59:"))

        let a = MV.ProjectTime(seconds: 2), b = MV.ProjectTime(seconds: 0.5)
        precondition(a + b == MV.ProjectTime(seconds: 2.5) && a - b == MV.ProjectTime(seconds: 1.5))
        precondition(b < a && max(a, b) == a)
        precondition(MV.ProjectTime(seconds: 9).clamped(.zero, a) == a)
        precondition(MV.ProjectTime(seconds: -1).clamped(.zero, a) == .zero)
        precondition(a.clamped(b, .zero) == b, "inverted bounds fall back to the lower bound")
        precondition((a * 2.5).seconds == 5)

        let range = MV.TimeRange(start: a, duration: b)
        precondition(range.contains(a) && !range.contains(range.end) && !range.contains(.zero))
        precondition(!range.overlaps(MV.TimeRange(start: range.end, duration: a)), "adjacent ranges do not overlap")
        precondition(range.overlaps(MV.TimeRange(start: MV.ProjectTime(seconds: 2.4), duration: a)))
    }

    // MARK: Project

    static func photos(_ count: Int) -> [MV.TimelineEngine.ImportedPhoto] {
        (0..<count).map { MV.TimelineEngine.ImportedPhoto(mediaFile: "p\($0).jpg", pixelWidth: 4000, pixelHeight: 3000) }
    }

    static func project() {
        var p = MV.VideoProject()
        precondition(p.duration == MV.VideoProject.minimumDuration, "empty project has the minimum length")
        MV.TimelineEngine.appendPhotos(photos(4), to: &p)
        precondition(p.photos.map(\.core.start.seconds) == [0, 3, 6, 9])
        near(p.duration.seconds, 12)
        precondition(p.photos.map(\.core.zIndex) == [0, 1, 2, 3])
        precondition(p.photos[2].aspectRatio > 1.33 && p.photos[2].aspectRatio < 1.34)

        // Importing more continues after the last photo.
        let ids = MV.TimelineEngine.appendPhotos(photos(1), to: &p)
        precondition(ids.count == 1 && p.photos.last?.core.start.seconds == 12)

        // updateCore sanitises what it stores.
        let id = p.photos[0].core.id
        precondition(p.updateCore(id) { $0.transform.scale = 99; $0.transform.opacity = -3; $0.transform.x = .nan })
        precondition(p.photos[0].core.transform.scale == 4 && p.photos[0].core.transform.opacity == 0 && p.photos[0].core.transform.x == 0.5)
        precondition(!p.updateCore(UUID()) { _ in })

        // Layer cap.
        var big = MV.VideoProject()
        MV.TimelineEngine.appendPhotos(photos(450), to: &big)
        precondition(big.layerCount == MV.VideoProject.maxLayers)
        precondition(MV.TimelineEngine.addText("x", at: .zero, to: &big) == nil)

        // Aspect ratios.
        for (aspect, w, h) in [(MV.AspectRatio.portrait9x16, 1080, 1920), (.landscape16x9, 1920, 1080),
                               (.square, 1080, 1080), (.portrait4x5, 1080, 1350), (.portrait3x4, 1080, 1440)] {
            let size = aspect.pixelSize(shortSide: 1080)
            precondition(size.width == w && size.height == h, "\(aspect) -> \(size)")
            precondition(size.width % 2 == 0 && size.height % 2 == 0)
        }
    }

    // MARK: Timeline engine

    static func timelineEngine() {
        var p = MV.VideoProject()
        MV.TimelineEngine.appendPhotos(photos(3), to: &p)            // 0-3, 3-6, 6-9
        let textID = MV.TimelineEngine.addText("Hello", at: MV.ProjectTime(seconds: 2), to: &p)!

        func active(_ seconds: Double) -> [UUID] {
            MV.TimelineEngine.activeLayerIDs(in: p, at: MV.ProjectTime(seconds: seconds))
        }
        precondition(active(0) == [p.photos[0].core.id])
        precondition(active(2.999) == [p.photos[0].core.id, textID], "text sits above the photo")
        precondition(active(3) == [p.photos[1].core.id, textID], "half-open ranges: the next photo starts exactly at 3 s")
        precondition(active(5) == [p.photos[1].core.id])
        precondition(active(9).isEmpty)

        // Hidden layers do not render but stay on the timeline.
        p.updateCore(textID) { $0.isVisible = false }
        precondition(active(2.5) == [p.photos[0].core.id])
        precondition(MV.TimelineEngine.clips(in: p).contains { $0.id == textID && !$0.isVisible })

        // Z-order can be changed explicitly.
        p.updateCore(p.photos[0].core.id) { $0.zIndex = 99 }
        p.photos[1].core.start = .zero                                  // overlap photo 0 and 1
        precondition(active(1) == [p.photos[1].core.id, p.photos[0].core.id])

        // Clips are grouped by track order, then start time.
        let clips = MV.TimelineEngine.clips(in: p)
        precondition(clips.first?.track == .photo && clips.last?.track == .text)
        precondition(MV.TimelineEngine.clips(in: p, track: .photo).count == 3)

        // Duplicate / lock / reset / remove.
        var q = MV.VideoProject()
        MV.TimelineEngine.appendPhotos(photos(2), to: &q)
        let first = q.photos[0].core.id
        let copies = MV.TimelineEngine.duplicate([first], in: &q)
        precondition(copies.count == 1 && q.photos.count == 3)
        precondition(q.photos[2].core.start == q.photos[0].core.end, "copy starts where the original ends")
        precondition(q.photos[2].core.id != first && q.photos[2].core.zIndex > q.photos[1].core.zIndex)
        precondition(q.photos[2].mediaFile == q.photos[0].mediaFile)

        q.updateCore(first) { $0.transform.scale = 2; $0.transform.rotation = 30 }
        q.updateCore(q.photos[1].core.id) { $0.transform.scale = 2; $0.isLocked = true }
        MV.TimelineEngine.resetTransform([first, q.photos[1].core.id], in: &q)
        precondition(q.photos[0].core.transform == .identity)
        precondition(q.photos[1].core.transform.scale == 2, "locked layers are not reset")
        precondition(MV.TimelineEngine.editable([first, q.photos[1].core.id], in: q) == [first])

        q.removeLayers([first])
        precondition(q.photos.count == 2 && q.core(for: first) == nil)

        // Text defaults.
        var t = MV.VideoProject()
        let tid = MV.TimelineEngine.addText("Xin chào", at: MV.ProjectTime(seconds: 99), to: &t)!
        near(t.texts[0].core.start.seconds, 3, 1e-9, "start is clamped to the project length")
        precondition(t.texts[0].core.zIndex >= MV.TrackKind.text.baseZIndex && t.core(for: tid)?.track == .text)
        precondition(MV.HexColor.components("#FF8000")! == (1, Double(128) / 255, 0))
        precondition(MV.HexColor.string(r: 1, g: 0.5, b: 0) == "#FF8000")
        precondition(MV.HexColor.components("zzz") == nil && MV.HexColor.components("#12") == nil)
    }

    // MARK: Timeline scale

    static func scale() {
        var s = MV.TimelineScale(pixelsPerSecond: 100)
        near(s.x(for: MV.ProjectTime(seconds: 2.5)), 250)
        near(s.time(forX: 250).seconds, 2.5)
        precondition(s.time(forX: -40) == .zero)
        s.pixelsPerSecond = 9_999
        precondition(s.pixelsPerSecond == MV.TimelineScale.range.upperBound)
        s.pixelsPerSecond = 0.0001
        precondition(s.pixelsPerSecond == MV.TimelineScale.range.lowerBound)
        s.pixelsPerSecond = .nan
        precondition(s.pixelsPerSecond == 60)

        let fit = MV.TimelineScale.fitting(duration: MV.ProjectTime(seconds: 10), width: 640)
        near(fit.contentWidth(duration: MV.ProjectTime(seconds: 10)), 640, 1)

        // Tick spacing adapts to the zoom and majors are always >= 70 pt apart.
        for pps in [8.0, 20, 60, 120, 200, 400] {
            let scale = MV.TimelineScale(pixelsPerSecond: pps)
            precondition(scale.majorStep * pps >= 70 || scale.majorStep == 1800, "pps \(pps)")
            let ticks = scale.ticks(visible: 0...30)
            let firstLabel = scale.majorStep >= 1 ? "0:00" : "0.0"
            precondition(ticks.first?.time == .zero && ticks.first?.isMajor == true && ticks.first?.label == firstLabel)
            let majors = ticks.filter(\.isMajor)
            for (a, b) in zip(majors, majors.dropFirst()) {
                precondition((b.time.seconds - a.time.seconds) * pps >= 69.9, "majors too close at \(pps)")
            }
            precondition(majors.allSatisfy { $0.label != nil } && ticks.filter { !$0.isMajor }.allSatisfy { $0.label == nil })
        }
        precondition(MV.TimelineScale(pixelsPerSecond: 60).majorStep == 2)
        precondition(MV.TimelineScale(pixelsPerSecond: 200).majorStep == 0.5)
        precondition(MV.TimelineScale.label(for: 75, step: 5) == "1:15")
        precondition(MV.TimelineScale.label(for: 1.5, step: 0.5) == "1.5")
    }

    // MARK: Undo

    static func undo() {
        var history = MV.UndoHistory<Int>(limit: 3)
        precondition(!history.canUndo && !history.canRedo)
        var value = 0
        for next in 1...5 {
            history.checkpoint(value)
            value = next
        }
        precondition(history.undoStack == [2, 3, 4], "limit keeps the newest snapshots")
        precondition(history.undo(current: value) == 4 && history.canRedo)
        precondition(history.undo(current: 4) == 3)
        precondition(history.redo(current: 3) == 4)
        history.checkpoint(4)                                    // a new edit clears redo
        precondition(!history.canRedo)
        history.checkpoint(4)                                    // duplicate checkpoint is ignored
        precondition(history.undoStack.filter { $0 == 4 }.count == 1)
        history.clear()
        precondition(history.undo(current: 0) == nil && history.redo(current: 0) == nil)
    }

    // MARK: Transport

    static func transport() {
        var t = MV.TransportState()
        t.setDuration(MV.ProjectTime(seconds: 3), fps: 30)
        precondition(!t.advance(by: 1), "paused clock does not move")
        t.play()
        precondition(t.isPlaying && !t.advance(by: 1))
        near(t.time.seconds, 1)
        precondition(t.advance(by: 2.5), "reaching the end stops playback")
        precondition(t.time == t.duration && !t.isPlaying)
        t.play()                                                 // at the end: restarts from 0
        precondition(t.time == .zero && t.isPlaying)

        t.loops = true
        t.seek(to: MV.ProjectTime(seconds: 2.5))
        precondition(!t.advance(by: 1) && t.isPlaying)
        near(t.time.seconds, 0.5)

        t.loops = false
        t.rate = 2
        t.seek(to: .zero)
        t.advance(by: 0.5)
        near(t.time.seconds, 1, 1e-6, "rate 2x")
        t.rate = 1

        t.seek(to: MV.ProjectTime(seconds: 99))
        precondition(t.time == t.duration)
        t.seek(to: MV.ProjectTime(seconds: -4))
        precondition(t.time == .zero)

        t.seek(to: MV.ProjectTime(seconds: 1))
        t.play()
        t.step(frames: 1)
        precondition(!t.isPlaying && t.time.ticks == 62_000, "one frame at 30 fps = 2000 ticks")
        t.step(frames: -1000)
        precondition(t.time == .zero)
        t.step(frames: 1000)
        precondition(t.time == t.duration)

        // Rendered time is whole-frame quantised, identical for playback and export.
        t.seek(to: MV.ProjectTime(ticks: 62_999))
        precondition(t.frameTime.ticks == 62_000)

        // Shortening the project clamps the playhead and stops.
        t.seek(to: MV.ProjectTime(seconds: 2.9)); t.play()
        t.setDuration(MV.ProjectTime(seconds: 2), fps: 60)
        precondition(t.time == t.duration && !t.isPlaying && t.fps == 60)
        t.setDuration(MV.ProjectTime(seconds: 5), fps: 99)
        precondition(t.fps == 60, "unsupported frame rates are ignored")

        t.seek(to: .zero)
        near(t.progress, 0)
        t.seek(to: t.duration)
        near(t.progress, 1)
        precondition(!t.advance(by: .nan) && !t.advance(by: -1))
    }

    // MARK: Persistence format

    static func coding() throws {
        var p = MV.VideoProject()
        p.name = "Demo"
        p.aspect = .portrait4x5
        p.fps = 60
        MV.TimelineEngine.appendPhotos(photos(2), to: &p)
        MV.TimelineEngine.addText("Lời bài hát", at: MV.ProjectTime(seconds: 1), to: &p)
        p.texts[0].colorHex = "#FFCC00"
        p.texts[0].weight = .heavy

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(p)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(MV.VideoProject.self, from: data)
        precondition(back.id == p.id && back.photos == p.photos && back.texts == p.texts)
        precondition(back.aspect == .portrait4x5 && back.fps == 60 && back.duration == p.duration)

        // Tolerant: an empty or partial file still opens with defaults.
        let empty = try decoder.decode(MV.VideoProject.self, from: Data("{}".utf8))
        precondition(empty.aspect == .portrait9x16 && empty.fps == 30 && empty.photos.isEmpty)
        let oddFPS = try decoder.decode(MV.VideoProject.self, from: Data(#"{"fps":7,"name":"x"}"#.utf8))
        precondition(oddFPS.fps == 30 && oddFPS.name == "x")
    }

    // MARK: Phase 2 - timeline editing

    static func fourPhotos() -> MV.VideoProject {
        var p = MV.VideoProject()
        MV.TimelineEngine.appendPhotos(photos(4), to: &p)          // 0-3, 3-6, 6-9, 9-12
        return p
    }

    static func sec(_ s: Double) -> MV.ProjectTime { MV.ProjectTime(seconds: s) }

    static func editing() {
        let threshold = sec(0.1)

        // Snap points: zero, playhead and the other layers' edges, sorted and unique.
        var p = fourPhotos()
        let b = p.photos[1].core.id
        let points = MV.TimelineEditing.snapPoints(in: p, excluding: [b], playhead: sec(4.5))
        precondition(points == [0, 3, 4.5, 6, 9, 12].map(sec) || points == [0, 4.5, 3, 6, 9, 12].map(sec).sorted(), "\(points)")
        precondition(!points.contains(sec(6)) == false && points.first == .zero)
        precondition(MV.TimelineEditing.nearest(to: sec(5.95), in: points, threshold: threshold) == sec(6))
        precondition(MV.TimelineEditing.nearest(to: sec(5.5), in: points, threshold: threshold) == nil)

        // Move: free, snapped, clamped at zero, group, locked.
        let range = p.photos[1].core.range
        precondition(MV.TimelineEditing.move(origins: [b: range], delta: sec(1), in: &p, snapPoints: points, threshold: threshold) == nil)
        near(p.photos[1].core.start.seconds, 4)
        let snapped = MV.TimelineEditing.move(origins: [b: range], delta: sec(2.97), in: &p, snapPoints: points, threshold: threshold)
        precondition(snapped == sec(6) || snapped == sec(9))
        near(p.photos[1].core.start.seconds, 6, 1e-9, "snaps to the neighbouring edge")
        MV.TimelineEditing.move(origins: [b: range], delta: sec(-10), in: &p, snapPoints: [], threshold: threshold)
        precondition(p.photos[1].core.start == .zero, "never before time zero")

        p = fourPhotos()
        let a = p.photos[0].core.id, c = p.photos[2].core.id
        let group: [UUID: MV.TimeRange] = [a: p.photos[0].core.range, c: p.photos[2].core.range]
        MV.TimelineEditing.move(origins: group, delta: sec(-5), in: &p, snapPoints: [], threshold: threshold)
        precondition(p.photos[0].core.start == .zero && p.photos[2].core.start == sec(6), "the group stops together at zero")
        MV.TimelineEditing.move(origins: group, delta: sec(2), in: &p, snapPoints: [], threshold: threshold)
        near(p.photos[0].core.start.seconds, 2); near(p.photos[2].core.start.seconds, 8)

        p = fourPhotos()
        p.updateCore(a) { $0.isLocked = true }
        precondition(MV.TimelineEditing.move(origins: [a: p.photos[0].core.range], delta: sec(5), in: &p, snapPoints: [], threshold: threshold) == nil)
        precondition(p.photos[0].core.start == .zero, "locked layers do not move")

        // Trim.
        p = fourPhotos()
        let id1 = p.photos[1].core.id, r1 = p.photos[1].core.range
        MV.TimelineEditing.trim(id: id1, origin: r1, edge: .start, delta: sec(1), in: &p, snapPoints: [], threshold: threshold)
        near(p.photos[1].core.start.seconds, 4); near(p.photos[1].core.duration.seconds, 2)
        MV.TimelineEditing.trim(id: id1, origin: r1, edge: .start, delta: sec(99), in: &p, snapPoints: [], threshold: threshold)
        near(p.photos[1].core.duration.seconds, 0.1, 1e-6, "cannot trim past the minimum length")
        MV.TimelineEditing.trim(id: id1, origin: r1, edge: .start, delta: sec(-99), in: &p, snapPoints: [], threshold: threshold)
        precondition(p.photos[1].core.start == .zero && p.photos[1].core.end == r1.end, "start clamps at zero, end stays put")
        MV.TimelineEditing.trim(id: id1, origin: r1, edge: .end, delta: sec(-99), in: &p, snapPoints: [], threshold: threshold)
        near(p.photos[1].core.duration.seconds, 0.1)
        MV.TimelineEditing.trim(id: id1, origin: r1, edge: .end, delta: sec(2), in: &p, snapPoints: [], threshold: threshold)
        near(p.photos[1].core.duration.seconds, 5)
        let trimSnap = MV.TimelineEditing.trim(id: id1, origin: r1, edge: .end, delta: sec(0.04), in: &p,
                                               snapPoints: [sec(6)], threshold: threshold)
        precondition(trimSnap == sec(6)); near(p.photos[1].core.duration.seconds, 3)
        p.updateCore(id1) { $0.isLocked = true }
        precondition(MV.TimelineEditing.trim(id: id1, origin: r1, edge: .end, delta: sec(1), in: &p, snapPoints: [], threshold: threshold) == nil)

        // Split.
        p = fourPhotos()
        let tid = MV.TimelineEngine.addText("t", at: sec(3.5), to: &p)!      // 3.5-6.5
        let pid1 = p.photos[1].core.id
        let created = MV.TimelineEditing.split([pid1, tid], at: sec(4.5123), in: &p)
        precondition(created.count == 2 && p.photos.count == 5 && p.texts.count == 2)
        near(p.photos[1].core.end.seconds, 4.5, 1e-9, "cut is quantised to a frame")
        let right = p.photos.last!
        precondition(right.core.start.seconds == 4.5 && right.core.end == sec(6) && right.core.name.hasSuffix("(2)"))
        precondition(right.mediaFile == p.photos[1].mediaFile && right.transitionIn.kind == .none)
        precondition(MV.TimelineEditing.split([pid1], at: sec(3.05), in: &p).isEmpty, "too close to the edge")
        precondition(MV.TimelineEditing.split([UUID()], at: sec(4), in: &p).isEmpty)
        p = fourPhotos()
        let lockedID = p.photos[1].core.id
        p.updateCore(lockedID) { $0.isLocked = true }
        precondition(MV.TimelineEditing.split([lockedID], at: sec(4), in: &p).isEmpty && p.photos.count == 4)

        // Ripple delete closes the gap on the same track only.
        p = fourPhotos()
        let t2 = MV.TimelineEngine.addText("keep", at: sec(10), to: &p)!
        MV.TimelineEditing.rippleDelete([p.photos[1].core.id], in: &p)
        precondition(p.photos.map(\.core.start.seconds) == [0, 3, 6] && p.photos.count == 3)
        precondition(p.core(for: t2)?.start == sec(10), "other tracks are untouched")
        p = fourPhotos()
        p.updateCore(p.photos[3].core.id) { $0.isLocked = true }
        MV.TimelineEditing.rippleDelete([p.photos[0].core.id], in: &p)
        precondition(p.photos.last?.core.start == sec(9), "locked later layers stay in place")

        // Order + pack.
        p = fourPhotos()
        let ids = p.photos.map(\.core.id)
        precondition(MV.TimelineEditing.orderedPhotoIDs(in: p) == ids)
        precondition(MV.TimelineEditing.movePhoto(ids[0], by: 1, in: &p))
        precondition(MV.TimelineEditing.orderedPhotoIDs(in: p) == [ids[1], ids[0], ids[2], ids[3]])
        precondition(p.core(for: ids[1])?.start == .zero && p.core(for: ids[0])?.start == sec(3))
        precondition(!MV.TimelineEditing.movePhoto(ids[3], by: 1, in: &p), "cannot move past the end")
        precondition(!MV.TimelineEditing.movePhoto(UUID(), by: 1, in: &p))

        p = fourPhotos()
        p.photos[1].transitionIn = MV.PhotoTransition(kind: .crossfade, duration: 1.0)
        MV.TimelineEditing.packPhotos(in: &p)
        near(p.photos[1].core.start.seconds, 2, 1e-9, "a transition overlaps the previous photo")
        near(p.photos[2].core.start.seconds, 5); near(p.photos[3].core.start.seconds, 8)
        near(p.duration.seconds, 11)

        p = fourPhotos()
        p.photos[2].core.start = sec(20)                         // a gap and out of order
        MV.TimelineEditing.packPhotos(in: &p)
        precondition(p.photos.map(\.core.start.seconds) == [0, 3, 9, 6], "play order is by start time, then packed")

        MV.TimelineEditing.setAllPhotoDurations(sec(2), in: &p)
        precondition(p.photos.allSatisfy { $0.core.duration == sec(2) })
        precondition(Set(p.photos.map(\.core.start.seconds)) == [0, 2, 4, 6])
        MV.TimelineEditing.setAllPhotoDurations(sec(0.001), in: &p)
        precondition(p.photos.allSatisfy { $0.core.duration >= MV.LayerCore.minimumDuration })
    }

    // MARK: Phase 2 - Ken Burns and transitions

    static func photoEffects() {
        let k = MV.KenBurnsEffect.self
        let i = 0.2
        func motion(_ preset: MV.PhotoMotionPreset) -> MV.PhotoMotion { MV.PhotoMotion(preset: preset, intensity: i) }

        precondition(k.transform(motion(.none), progress: 0.5) == .identity)
        near(k.transform(motion(.zoomIn), progress: 0).scale, 1)
        near(k.transform(motion(.zoomIn), progress: 1).scale, 1.2)
        near(k.transform(motion(.zoomIn), progress: 0.5).scale, 1.1)
        near(k.transform(motion(.zoomOut), progress: 0).scale, 1.2)
        near(k.transform(motion(.zoomOut), progress: 1).scale, 1)
        let left0 = k.transform(motion(.panLeft), progress: 0), left1 = k.transform(motion(.panLeft), progress: 1)
        near(left0.offsetX, 0.1); near(left1.offsetX, -0.1); near(left0.scale, 1.2)
        let up0 = k.transform(motion(.panUp), progress: 0)
        near(up0.offsetY, 0.1); near(up0.offsetX, 0)
        near(k.transform(motion(.panDown), progress: 0).offsetY, -0.1)
        near(k.transform(motion(.panRight), progress: 1).offsetX, 0.1)
        let drift = k.transform(motion(.drift), progress: 0.5)
        precondition(drift.scale > 1.2 && drift.scale < 1.32)

        // Panning never reveals an edge: the picture is always bigger than the offset.
        for preset in MV.PhotoMotionPreset.allCases where preset != .none {
            for p in stride(from: 0.0, through: 1.0, by: 0.1) {
                let t = k.transform(motion(preset), progress: p)
                precondition(t.scale >= 1 - 1e-9)
                precondition(abs(t.offsetX) <= (t.scale - 1) / 2 + 1e-9 && abs(t.offsetY) <= (t.scale - 1) / 2 + 1e-9, "\(preset) \(p)")
            }
        }
        // Robust to bad input.
        near(k.transform(motion(.zoomIn), progress: .nan).scale, 1)
        near(k.transform(motion(.zoomIn), progress: -3).scale, 1)
        near(k.transform(motion(.zoomIn), progress: 9).scale, 1.2)
        near(k.transform(MV.PhotoMotion(preset: .zoomIn, intensity: 9), progress: 1).scale, 1.5)
        near(k.transform(MV.PhotoMotion(preset: .zoomIn, intensity: 0), progress: 1).scale, 1.03)
        near(k.progress(start: sec(3), duration: sec(3), at: sec(4.5)), 0.5)
        near(k.progress(start: sec(3), duration: sec(3), at: sec(1)), 0)
        near(k.progress(start: sec(3), duration: sec(3), at: sec(8)), 1)
        near(k.progress(start: sec(3), duration: .zero, at: sec(4)), 0)

        // Transitions.
        let e = MV.PhotoTransitionEngine.self
        precondition(e.effect(.none, progress: 0.3) == .identity)
        near(e.effect(.crossfade, progress: 0).opacity, 0)
        near(e.effect(.crossfade, progress: 1).opacity, 1)
        near(e.effect(.crossfade, progress: 0.5).opacity, 0.5)
        near(e.effect(.slideLeft, progress: 0).offsetX, 1); near(e.effect(.slideLeft, progress: 1).offsetX, 0)
        near(e.effect(.slideRight, progress: 0).offsetX, -1)
        near(e.effect(.slideUp, progress: 0).offsetY, 1)
        near(e.effect(.zoom, progress: 0).scale, 1.35); near(e.effect(.zoom, progress: 0).opacity, 0)
        near(e.effect(.zoom, progress: 1).scale, 1); near(e.effect(.zoom, progress: 1).opacity, 1)
        for kind in MV.PhotoTransitionKind.allCases {
            var last = -1.0
            for p in stride(from: 0.0, through: 1.0, by: 0.05) {
                let o = e.effect(kind, progress: p).opacity
                precondition(o >= last - 1e-9 && o >= 0 && o <= 1, "opacity is monotonic")
                last = o
            }
        }

        let fade = MV.PhotoTransition(kind: .crossfade, duration: 1.0)
        precondition(e.progress(fade, start: sec(3), duration: sec(3), at: sec(2.9)) == nil)
        near(e.progress(fade, start: sec(3), duration: sec(3), at: sec(3))!, 0)
        near(e.progress(fade, start: sec(3), duration: sec(3), at: sec(3.5))!, 0.5)
        precondition(e.progress(fade, start: sec(3), duration: sec(3), at: sec(4)) == nil, "half-open: over at exactly 1 s")
        precondition(e.progress(MV.PhotoTransition(), start: sec(3), duration: sec(3), at: sec(3.1)) == nil)
        near(e.effectiveDuration(MV.PhotoTransition(kind: .crossfade, duration: 3), layerDuration: sec(1)).seconds, 0.9)
        near(e.effectiveDuration(MV.PhotoTransition(kind: .crossfade, duration: 0), layerDuration: sec(5)).seconds, 0.2)

        var core = MV.LayerCore(name: "x", track: .photo, start: sec(3), duration: sec(3), zIndex: 0)
        core.transform = MV.LayerTransform()
        var layer = MV.PhotoLayer(core: core, mediaFile: "a.jpg", pixelWidth: 10, pixelHeight: 10)
        precondition(e.effect(for: layer, at: sec(3.1)) == .identity)
        layer.transitionIn = fade
        near(e.effect(for: layer, at: sec(3.5)).opacity, 0.5)
        near(e.effect(for: layer, at: sec(5)).opacity, 1)
    }

    static func photoCoding() throws {
        // A phase-1 project (no motion / transition keys) still opens.
        var p = MV.VideoProject()
        MV.TimelineEngine.appendPhotos(photos(1), to: &p)
        let data = try JSONEncoder().encode(p)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var photosJSON = json["photos"] as! [[String: Any]]
        photosJSON[0].removeValue(forKey: "motion")
        photosJSON[0].removeValue(forKey: "transitionIn")
        photosJSON[0].removeValue(forKey: "fit")
        json["photos"] = photosJSON
        let old = try JSONDecoder().decode(MV.VideoProject.self, from: JSONSerialization.data(withJSONObject: json))
        precondition(old.photos[0].motion == MV.PhotoMotion() && old.photos[0].transitionIn == MV.PhotoTransition())
        precondition(old.photos[0].fit == .fill && old.photos[0].mediaFile == "p0.jpg")

        p.photos[0].motion = MV.PhotoMotion(preset: .panLeft, intensity: 0.3)
        p.photos[0].transitionIn = MV.PhotoTransition(kind: .slideUp, duration: 1.5)
        let back = try JSONDecoder().decode(MV.VideoProject.self, from: JSONEncoder().encode(p))
        precondition(back.photos == p.photos)
    }

    // MARK: Phase 3/4 - audio

    static func audioLayer(start: Double = 2, duration: Double = 6, sourceStart: Double = 1, sourceDuration: Double = 11,
                           loops: Bool = false) -> MV.AudioLayer {
        let core = MV.LayerCore(name: "song", track: .audio, start: sec(start), duration: sec(duration), zIndex: 0)
        return MV.AudioLayer(core: core, mediaFile: "song.m4a", originalName: "song", sourceDuration: sourceDuration,
                             sourceStart: sourceStart, loops: loops)
    }

    static func audioMath() {
        let e = MV.AudioEnvelope.self
        near(e.fade(local: 0, duration: 10, fadeIn: 2, fadeOut: 2), 0)
        near(e.fade(local: 1, duration: 10, fadeIn: 2, fadeOut: 2), 0.5)
        near(e.fade(local: 2, duration: 10, fadeIn: 2, fadeOut: 2), 1)
        near(e.fade(local: 5, duration: 10, fadeIn: 2, fadeOut: 2), 1)
        near(e.fade(local: 9, duration: 10, fadeIn: 2, fadeOut: 2), 0.5)
        near(e.fade(local: 10, duration: 10, fadeIn: 2, fadeOut: 2), 0)
        near(e.fade(local: 2.5, duration: 10, fadeIn: 8, fadeOut: 8), 0.5, 1e-9, "oversized fades are scaled to fit")
        near(e.fade(local: -1, duration: 10, fadeIn: 0, fadeOut: 0), 0)
        near(e.fade(local: 11, duration: 10, fadeIn: 0, fadeOut: 0), 0)
        near(e.fade(local: .nan, duration: 10, fadeIn: 0, fadeOut: 0), 0)
        near(e.fade(local: 5, duration: 10, fadeIn: .nan, fadeOut: -3), 1)

        var layer = audioLayer()
        layer.volume = 0.5; layer.fadeIn = 2
        near(e.gain(layer, at: sec(3)), 0.25, 1e-9, "1 s into a 2 s fade at volume 0.5")
        near(e.gain(layer, at: sec(5)), 0.5)
        near(e.gain(layer, at: sec(1)), 0); near(e.gain(layer, at: sec(8)), 0)
        layer.core.isVisible = false
        near(e.gain(layer, at: sec(5)), 0, 1e-9, "the eye toggle mutes")
        layer.core.isVisible = true; layer.volume = 9
        near(e.gain(layer, at: sec(5)), MV.AudioLayer.volumeRange.upperBound)
        layer.volume = .nan
        near(e.gain(layer, at: sec(5)), 1)

        // Scheduling (1 kHz "sample rate" keeps the numbers readable).
        let s = MV.AudioScheduling.self
        var a = audioLayer()                                     // clip 2-8 s, file 1-11 s
        var segs = s.segments(layer: a, from: .zero, sampleRate: 1000, fileFrames: 11_000)
        precondition(segs == [MV.AudioSegment(delay: 2, startFrame: 1000, frameCount: 6000)], "\(segs)")
        segs = s.segments(layer: a, from: sec(4), sampleRate: 1000, fileFrames: 11_000)
        precondition(segs == [MV.AudioSegment(delay: 0, startFrame: 3000, frameCount: 4000)], "\(segs)")
        precondition(s.segments(layer: a, from: sec(8), sampleRate: 1000, fileFrames: 11_000).isEmpty)
        precondition(s.segments(layer: a, from: sec(99), sampleRate: 1000, fileFrames: 11_000).isEmpty)
        precondition(s.segments(layer: a, from: .zero, sampleRate: 0, fileFrames: 11_000).isEmpty)

        a = audioLayer(duration: 6, sourceDuration: 3)           // only 2 s of music after the trim
        segs = s.segments(layer: a, from: .zero, sampleRate: 1000, fileFrames: 3000)
        precondition(segs == [MV.AudioSegment(delay: 2, startFrame: 1000, frameCount: 2000)], "no looping: silence after the file")
        precondition(s.segments(layer: a, from: sec(6), sampleRate: 1000, fileFrames: 3000).isEmpty, "already past the music")

        a = audioLayer(duration: 25, loops: true)
        segs = s.segments(layer: a, from: .zero, sampleRate: 1000, fileFrames: 11_000)
        precondition(segs == [MV.AudioSegment(delay: 2, startFrame: 1000, frameCount: 10_000),
                              MV.AudioSegment(delay: 0, startFrame: 1000, frameCount: 10_000),
                              MV.AudioSegment(delay: 0, startFrame: 1000, frameCount: 5000)], "\(segs)")
        segs = s.segments(layer: a, from: sec(14), sampleRate: 1000, fileFrames: 11_000)       // 12 s into the clip
        precondition(segs == [MV.AudioSegment(delay: 0, startFrame: 3000, frameCount: 8000),
                              MV.AudioSegment(delay: 0, startFrame: 1000, frameCount: 5000)], "\(segs)")
        let tiny = audioLayer(start: 0, duration: 1000, sourceStart: 0, sourceDuration: 0.01, loops: true)
        precondition(s.segments(layer: tiny, from: .zero, sampleRate: 1000, fileFrames: 10).count <= MV.AudioScheduling.maxSegments + 0,
                     "looping a tiny file stays bounded")
        precondition(s.segments(layer: a, from: .zero, sampleRate: 1000, fileFrames: 500).allSatisfy { $0.startFrame + $0.frameCount <= 500 },
                     "never reads past the end of the file")

        let plain = audioLayer()
        near(s.sourcePosition(layer: plain, at: sec(3))!, 2)
        precondition(s.sourcePosition(layer: plain, at: sec(1)) == nil && s.sourcePosition(layer: plain, at: sec(8)) == nil)
        let loopy = audioLayer(duration: 25, loops: true)
        near(s.sourcePosition(layer: loopy, at: sec(15))!, 4)                                  // local 13 -> 13 mod 10 = 3 -> 1 + 3
    }

    static func audioEditing() {
        // Project plumbing for the new layer kinds.
        var p = MV.VideoProject()
        precondition(p.audios.isEmpty && p.vinyls.isEmpty)
        let imported = MV.ProjectManager.ImportedAudio(mediaFile: "a.m4a", originalName: "Song", duration: 30)
        let audioID = MV.TimelineEngine.addAudio(imported, at: sec(1.013), to: &p)!
        precondition(p.audios.count == 1 && p.layerCount == 1)
        near(p.duration.seconds, 31, 0.05, "the music defines the project length")
        precondition(p.core(for: audioID)?.track == .audio && p.audios[0].sourceDuration == 30)
        let vinylID = MV.TimelineEngine.addVinyl(at: .zero, coverFile: "c.jpg", to: &p)!
        precondition(p.vinyls[0].coverFile == "c.jpg" && p.core(for: vinylID)?.end == p.duration || p.vinyls[0].core.duration.seconds >= 3)
        precondition(p.updateCore(audioID) { $0.isLocked = true } && p.audios[0].core.isLocked)
        p.removeLayers([audioID, vinylID])
        precondition(p.layerCount == 0)
        precondition(MV.TrackKind.allCases.allSatisfy(\.isAvailable))
        precondition(Set(MV.TrackKind.allCases.filter(\.alwaysVisible)) == [.photo, .audio, .text])
        precondition(MV.TimelineEngine.renderItems(in: p, at: .zero).isEmpty)

        // Vinyl is a render item, audio is not.
        var q = MV.VideoProject()
        MV.TimelineEngine.appendPhotos(photos(1), to: &q)
        MV.TimelineEngine.addAudio(imported, at: .zero, to: &q)
        MV.TimelineEngine.addVinyl(at: .zero, coverFile: nil, to: &q)
        let items = MV.TimelineEngine.renderItems(in: q, at: sec(1))
        precondition(items.count == 2, "photo + vinyl; audio has no picture")
        if case .vinyl = items.last! { } else { preconditionFailure("vinyl draws above photos") }
        let clips = MV.TimelineEngine.clips(in: q)
        precondition(clips.map(\.track) == [.photo, .audio, .vinyl], "\(clips.map(\.track))")

        // Fit photos to the music.
        var f = MV.VideoProject()
        MV.TimelineEngine.appendPhotos(photos(3), to: &f)
        MV.TimelineEngine.fitPhotos(toDuration: 12, in: &f)
        precondition(f.photos.map(\.core.start.seconds) == [0, 4, 8] && f.photos.allSatisfy { $0.core.duration == sec(4) })

        // Trimming the head of audio moves the trim point so the music stays aligned.
        var a = MV.VideoProject()
        let id = MV.TimelineEngine.addAudio(.init(mediaFile: "a", originalName: "a", duration: 20), at: .zero, to: &a)!
        let origin = a.audios[0].core.range
        MV.TimelineEditing.trim(id: id, origin: origin, edge: .start, delta: sec(2), in: &a, snapPoints: [], threshold: sec(0.1))
        near(a.audios[0].core.start.seconds, 2); near(a.audios[0].sourceStart, 2); near(a.audios[0].core.duration.seconds, 18)
        MV.TimelineEditing.trim(id: id, origin: origin, edge: .start, delta: sec(-3), in: &a, snapPoints: [], threshold: sec(0.1))
        near(a.audios[0].core.start.seconds, 0); near(a.audios[0].sourceStart, 0, 1e-9, "back to the file's beginning")
        // A clip starting at 5 that already skips 1 s cannot reveal music before the file's start.
        var b = MV.VideoProject()
        let bid = MV.TimelineEngine.addAudio(.init(mediaFile: "b", originalName: "b", duration: 20), at: sec(5), to: &b)!
        b.audios[0].sourceStart = 1; b.audios[0].core.duration = sec(10)
        MV.TimelineEditing.trim(id: bid, origin: b.audios[0].core.range, edge: .start, delta: sec(-4), in: &b, snapPoints: [], threshold: .zero)
        near(b.audios[0].sourceStart, 0); near(b.audios[0].core.start.seconds, 4, 1e-6)
        near(b.audios[0].core.end.seconds, 15, 1e-6)

        // Split continues the music where the first half stops.
        var s = MV.VideoProject()
        let sid = MV.TimelineEngine.addAudio(.init(mediaFile: "s", originalName: "s", duration: 10), at: .zero, to: &s)!
        s.audios[0].sourceStart = 1; s.audios[0].core.duration = sec(9); s.audios[0].fadeIn = 1; s.audios[0].fadeOut = 2
        let created = MV.TimelineEditing.split([sid], at: sec(4), in: &s)
        precondition(created.count == 1 && s.audios.count == 2)
        near(s.audios[0].core.duration.seconds, 4); near(s.audios[1].core.start.seconds, 4)
        near(s.audios[1].sourceStart, 5, 1e-9, "second half continues at 1 + 4 s")
        precondition(s.audios[1].fadeIn == 0 && s.audios[0].fadeOut == 0 && s.audios[1].fadeOut == 2 && s.audios[0].fadeIn == 1)

        // Explicit trim from the trimmer handles.
        var t = MV.VideoProject()
        let tid = MV.TimelineEngine.addAudio(.init(mediaFile: "t", originalName: "t", duration: 20), at: sec(3), to: &t)!
        precondition(MV.TimelineEditing.setAudioTrim(tid, sourceStart: 2, sourceEnd: 7, in: &t))
        near(t.audios[0].sourceStart, 2); near(t.audios[0].core.duration.seconds, 5); near(t.audios[0].core.start.seconds, 3)
        MV.TimelineEditing.setAudioTrim(tid, sourceStart: 19.99, sourceEnd: 5, in: &t)
        precondition(t.audios[0].core.duration >= MV.LayerCore.minimumDuration && t.audios[0].sourceStart <= 20 - 0.1 + 1e-9)
        t.audios[0].loops = true
        let keep = t.audios[0].core.duration
        MV.TimelineEditing.setAudioTrim(tid, sourceStart: 1, sourceEnd: 4, in: &t)
        precondition(t.audios[0].core.duration == keep, "a looping clip keeps its length")
        t.audios[0].core.isLocked = true
        precondition(!MV.TimelineEditing.setAudioTrim(tid, sourceStart: 0, sourceEnd: 1, in: &t))
        precondition(!MV.TimelineEditing.setAudioTrim(UUID(), sourceStart: 0, sourceEnd: 1, in: &t))

        // Duplicate keeps the music settings.
        var d = MV.VideoProject()
        let did = MV.TimelineEngine.addAudio(.init(mediaFile: "d", originalName: "d", duration: 5), at: .zero, to: &d)!
        d.audios[0].volume = 0.4
        let copies = MV.TimelineEngine.duplicate([did], in: &d)
        precondition(copies.count == 1 && d.audios.count == 2 && d.audios[1].volume == 0.4 && d.audios[1].core.start == d.audios[0].core.end)
    }

    static func waveformAndVinyl() {
        // Peaks of real samples.
        var samples = [Float](repeating: 0, count: 2000)
        for i in 0..<1000 { samples[i] = 0.5 * sinf(Float(i) * 0.3) }                // 1 s of tone then 1 s of silence
        let peaks = MV.WaveformMath.peaks(samples: samples, sampleRate: 1000, bucketsPerSecond: 10)
        precondition(peaks.count == 20)
        precondition(peaks[0..<10].allSatisfy { $0 > 0.45 && $0 <= 0.5 + 1e-6 })
        precondition(peaks[10...].allSatisfy { $0 == 0 })
        precondition(MV.WaveformMath.peaks(samples: [], sampleRate: 1000, bucketsPerSecond: 10).isEmpty)
        precondition(MV.WaveformMath.peaks(samples: [5, -9], sampleRate: 2, bucketsPerSecond: 1) == [1], "peaks are clamped to 1")

        let wave = MV.Waveform(bucketsPerSecond: 10, peaks: (0..<100).map { Float($0 / 10 + 1) / 10 })     // second s -> (s+1)/10
        near(Double(MV.WaveformMath.peak(wave, from: 3, to: 3.9)), 0.4, 0.11)
        precondition(MV.WaveformMath.peak(wave, from: 50, to: 60) == 0 && MV.WaveformMath.peak(wave, from: 5, to: 4) == 0)
        near(wave.duration, 10)
        let trimmed = MV.WaveformMath.clipColumns(wave, sourceStart: 2, sourceDuration: 10, clipDuration: 4, loops: false, count: 4)
        precondition(trimmed.count == 4 && trimmed[0] > 0.29 && trimmed[0] < 0.45, "\(trimmed)")
        precondition(trimmed == trimmed.sorted(), "the drawing follows the music forward in time")
        let tail = MV.WaveformMath.clipColumns(wave, sourceStart: 8, sourceDuration: 10, clipDuration: 6, loops: false, count: 6)
        precondition(tail[0] > 0.8 && tail[2...].allSatisfy { $0 == 0 }, "silence after the file ends: \(tail)")
        let looped = MV.WaveformMath.clipColumns(wave, sourceStart: 8, sourceDuration: 10, clipDuration: 6, loops: true, count: 6)
        precondition(looped.allSatisfy { $0 > 0.8 }, "looping repeats the trimmed part: \(looped)")
        precondition(MV.WaveformMath.clipColumns(wave, sourceStart: 0, sourceDuration: 10, clipDuration: 0, loops: false, count: 4).isEmpty)

        // Vinyl angle is a function of time.
        let v = MV.VinylMath.self
        near(v.angle(rpm: 60, localSeconds: 0.5), 180)
        near(v.angle(rpm: 60, localSeconds: 1), 0)
        near(v.angle(rpm: 60, localSeconds: -0.25), 270)
        near(v.angle(rpm: 60, localSeconds: 0.25, phase: 0.25), 180)
        near(v.angle(rpm: 33.33, localSeconds: 1.8), 359.964, 0.01)
        near(v.angle(rpm: 0, localSeconds: 99), 0)
        near(v.angle(rpm: .nan, localSeconds: 1), 0)
        precondition((0...40).allSatisfy { let a = v.angle(rpm: 45, localSeconds: Double($0) * 0.37); return a >= 0 && a < 360 })
        // Same time -> same angle, whatever happened in between (seek / pause).
        precondition(v.angle(rpm: 33.33, localSeconds: 7.25) == v.angle(rpm: 33.33, localSeconds: 7.25))
        near(v.localSeconds(layerStart: sec(3), at: sec(2)), 0); near(v.localSeconds(layerStart: sec(3), at: sec(4.5)), 1.5)
        near(Double(v.diameter(canvas: CGSize(width: 400, height: 800), size: 0.5)), 200)
        near(Double(v.diameter(canvas: CGSize(width: 400, height: 800), size: 9)), 400 * 1.4)

        // A split keeps the record spinning seamlessly.
        var p = MV.VideoProject()
        let id = MV.TimelineEngine.addVinyl(at: .zero, duration: sec(10), coverFile: nil, to: &p)!
        let created = MV.TimelineEditing.split([id], at: sec(4), in: &p)
        precondition(created.count == 1)
        let left = p.vinyls[0], right = p.vinyls[1]
        near(right.phase, 4)
        near(v.angle(rpm: left.rpm, localSeconds: 4), v.angle(rpm: right.rpm, localSeconds: 0, phase: right.phase), 1e-9)
    }

    static func audioCoding() throws {
        var p = MV.VideoProject()
        MV.TimelineEngine.addAudio(.init(mediaFile: "a.m4a", originalName: "Bài hát", duration: 12), at: sec(1), to: &p)
        p.audios[0].volume = 0.7; p.audios[0].fadeIn = 1.5; p.audios[0].loops = true; p.audios[0].sourceStart = 2
        MV.TimelineEngine.addVinyl(at: .zero, coverFile: "cover.png", to: &p)
        p.vinyls[0].rpm = 45; p.vinyls[0].glowColorHex = "#FF00FF"; p.vinyls[0].phase = 3
        let back = try JSONDecoder().decode(MV.VideoProject.self, from: JSONEncoder().encode(p))
        precondition(back.audios == p.audios && back.vinyls == p.vinyls)

        // Older files: no audios / vinyls keys, and minimal layer JSON.
        let empty = try JSONDecoder().decode(MV.VideoProject.self, from: Data(#"{"name":"x"}"#.utf8))
        precondition(empty.audios.isEmpty && empty.vinyls.isEmpty)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        var audios = json["audios"] as! [[String: Any]]
        for key in ["originalName", "sourceStart", "volume", "fadeIn", "fadeOut", "loops"] { audios[0].removeValue(forKey: key) }
        json["audios"] = audios
        var vinyls = json["vinyls"] as! [[String: Any]]
        for key in ["rpm", "size", "phase", "glowColorHex"] { vinyls[0].removeValue(forKey: key) }
        json["vinyls"] = vinyls
        let old = try JSONDecoder().decode(MV.VideoProject.self, from: JSONSerialization.data(withJSONObject: json))
        precondition(old.audios[0].volume == 1 && old.audios[0].sourceStart == 0 && !old.audios[0].loops)
        precondition(old.vinyls[0].rpm == 33.33 && old.vinyls[0].size == 0.55 && old.vinyls[0].phase == 0 && old.vinyls[0].glowColorHex == "#4DD0E1")
    }
}
