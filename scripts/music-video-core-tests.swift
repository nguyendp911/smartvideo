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
}
