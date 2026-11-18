import XCTest
import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
@testable import SmartVideo

typealias MV = MusicVideoStudio

/// Real files, a real display link and a real SwiftUI render of the preview.
final class MusicVideoStudioTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mv-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    private func solidPNG(_ color: UIColor, size: CGSize = CGSize(width: 200, height: 100)) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func jpegWithOrientation(_ orientation: Int, size: CGSize) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        let cg = try XCTUnwrap(image.cgImage)
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func pixel(_ image: UIImage, _ nx: Double, _ ny: Double) throws -> (r: Int, g: Int, b: Int) {
        let cg = try XCTUnwrap(image.cgImage)
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let x = Int(nx * Double(cg.width)), y = Int(ny * Double(cg.height))
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return (Int(px[0]), Int(px[1]), Int(px[2]))
    }

    // MARK: Project files

    func testProjectSaveLoadAndMediaKeepOriginalBytes() throws {
        let manager = MV.ProjectManager(root: root)
        var project = MV.VideoProject()
        project.name = "Saved"
        let png = try solidPNG(.red)
        let stored = try manager.storeImage(data: png, projectID: project.id)
        XCTAssertTrue(stored.mediaFile.hasSuffix(".png"))
        XCTAssertEqual(stored.pixelWidth, 200); XCTAssertEqual(stored.pixelHeight, 100)
        XCTAssertEqual(try Data(contentsOf: manager.mediaURL(projectID: project.id, file: stored.mediaFile)), png,
                       "the ORIGINAL bytes are kept")
        MV.TimelineEngine.appendPhotos([stored], to: &project)
        try manager.save(project)

        let loaded = try manager.load(project.id)
        XCTAssertEqual(loaded.photos, project.photos)
        XCTAssertEqual(manager.list().map(\.name), ["Saved"])
        XCTAssertEqual(manager.latestProjectID(), project.id)

        // A file name can never point outside the project's media folder.
        let evil = manager.mediaURL(projectID: project.id, file: "../../../secret.png")
        XCTAssertEqual(evil.deletingLastPathComponent().path, manager.mediaDirectory(for: project.id).path)

        XCTAssertThrowsError(try manager.storeImage(data: Data("not an image".utf8), projectID: project.id))
        try manager.delete(project.id)
        XCTAssertTrue(manager.list().isEmpty)
    }

    func testRotatedPhotosReportTheirDisplayedSize() throws {
        let manager = MV.ProjectManager(root: root)
        let id = UUID()
        // Stored 200x100 but flagged "rotate 90 degrees": it is displayed 100x200.
        let rotated = try manager.storeImage(data: try jpegWithOrientation(6, size: CGSize(width: 200, height: 100)), projectID: id)
        XCTAssertEqual(rotated.pixelWidth, 100); XCTAssertEqual(rotated.pixelHeight, 200)
        let upright = try manager.storeImage(data: try jpegWithOrientation(1, size: CGSize(width: 200, height: 100)), projectID: id)
        XCTAssertEqual(upright.pixelWidth, 200)
    }

    func testPhotoCacheDownsamplesInsteadOfLoadingFullSize() async throws {
        let url = root.appendingPathComponent("big.png")
        try solidPNG(.green, size: CGSize(width: 3000, height: 2000)).write(to: url)
        let loaded = await MV.PhotoImageCache.shared.load(url, maxPixel: 512)
        let image = try XCTUnwrap(loaded)
        XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 512.5)
        XCTAssertNotNil(MV.PhotoImageCache.shared.cached(url, maxPixel: 512))
        XCTAssertEqual(MV.PhotoImageCache.bucket(300), 512)
        XCTAssertEqual(MV.PhotoImageCache.bucket(0), 256)
        XCTAssertEqual(MV.PhotoImageCache.bucket(.nan), 1024)
    }

    // MARK: Master clock (real CADisplayLink)

    func testPlaybackEngineAdvancesWithRealTimeAndStops() {
        let engine = MV.PlaybackEngine()
        engine.configure(duration: MV.ProjectTime(seconds: 5), fps: 30)
        XCTAssertFalse(engine.isPlaying)
        engine.play()
        XCTAssertTrue(engine.isPlaying)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let moved = engine.time.seconds
        XCTAssertGreaterThan(moved, 0.25, "the display link must drive the clock")
        XCTAssertLessThan(moved, 1.6, "and not run faster than real time")

        engine.pause()
        let frozen = engine.time
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(engine.time, frozen, "a paused clock does not move")

        engine.seek(to: MV.ProjectTime(seconds: 4.9))
        engine.play()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertFalse(engine.isPlaying, "playback stops at the end")
        XCTAssertEqual(engine.time, MV.ProjectTime(seconds: 5))
    }

    // MARK: Editor model

    @MainActor
    func testEditorModelUndoRedoLockingAndPersistence() throws {
        let manager = MV.ProjectManager(root: root)
        let model = MV.MusicVideoEditorModel(manager: manager, project: MV.VideoProject())
        let png = try solidPNG(.red)
        let photo = try manager.storeImage(data: png, projectID: model.project.id)
        model.edit { _ = MV.TimelineEngine.appendPhotos([photo, photo], to: &$0) }
        XCTAssertEqual(model.project.photos.count, 2)
        XCTAssertEqual(model.playback.state.duration, MV.ProjectTime(seconds: 6))

        model.addText()
        XCTAssertEqual(model.project.texts.count, 1)
        XCTAssertEqual(model.selection, [model.project.texts[0].core.id])

        // Undo / redo restore both the project and the playback length.
        model.undo()
        XCTAssertTrue(model.project.texts.isEmpty)
        XCTAssertTrue(model.selection.isEmpty, "selection drops layers that no longer exist")
        model.redo()
        XCTAssertEqual(model.project.texts.count, 1)

        // Inspector bindings write to every EDITABLE selected layer.
        let a = model.project.photos[0].core.id, b = model.project.photos[1].core.id
        model.selection = [a, b]
        model.flagBinding(\.isLocked).wrappedValue = true
        XCTAssertTrue(model.project.photos.allSatisfy(\.core.isLocked))
        model.coreBinding(\.transform.scale, fallback: 1).wrappedValue = 2
        XCTAssertEqual(model.project.photos[0].core.transform.scale, 1, "locked layers ignore edits")
        model.selection = [a]
        model.flagBinding(\.isLocked).wrappedValue = false
        model.coreBinding(\.transform.scale, fallback: 1).wrappedValue = 2.5
        XCTAssertEqual(model.project.photos[0].core.transform.scale, 2.5)
        XCTAssertEqual(model.project.photos[1].core.transform.scale, 1)

        // Start/duration snap to whole frames and respect the minimum.
        model.timeBinding(\.duration, minimum: 0.1).wrappedValue = 0.01
        XCTAssertGreaterThanOrEqual(model.project.photos[0].core.duration.seconds, 0.1 - 1e-9)
        model.timeBinding(\.start, minimum: 0).wrappedValue = 1.0123
        XCTAssertEqual(model.project.photos[0].core.start.ticks % MV.ProjectTime.ticksPerFrame(fps: 30), 0)

        model.duplicateSelection()
        XCTAssertEqual(model.project.photos.count, 3)
        model.deleteSelection()
        XCTAssertEqual(model.project.photos.count, 2)

        model.setAspect(.landscape16x9); model.setFPS(60)
        XCTAssertEqual(model.project.aspect, .landscape16x9); XCTAssertEqual(model.playback.state.fps, 60)
        model.setFPS(7)
        XCTAssertEqual(model.project.fps, 60, "unsupported frame rates are ignored")

        // Save, start something else, come back.
        model.rename("Roundtrip")
        model.saveNow()
        let savedID = model.project.id
        model.newProject()
        XCTAssertNotEqual(model.project.id, savedID)
        XCTAssertTrue(model.project.photos.isEmpty)
        model.open(savedID)
        XCTAssertEqual(model.project.name, "Roundtrip")
        XCTAssertEqual(model.project.photos.count, 2)
        XCTAssertFalse(model.canUndo, "history is per opened project")
    }

    @MainActor
    func testTimelineZoomAndFit() {
        let model = MV.MusicVideoEditorModel(manager: MV.ProjectManager(root: root), project: MV.VideoProject())
        model.zoom(by: 2)
        XCTAssertEqual(model.scale.pixelsPerSecond, 120, accuracy: 0.001)
        model.zoom(by: 1000)
        XCTAssertEqual(model.scale.pixelsPerSecond, MV.TimelineScale.range.upperBound)
        model.fitTimeline(width: 640)
        XCTAssertEqual(model.scale.contentWidth(duration: model.project.duration), 640, accuracy: 1)
    }

    // MARK: Preview rendering (real SwiftUI render)

    @MainActor
    private func render(_ model: MV.MusicVideoEditorModel, at seconds: Double) throws -> UIImage {
        model.playback.seek(to: MV.ProjectTime(seconds: seconds))
        let view = MV.VideoPreviewView(model: model, playback: model.playback).frame(width: 400, height: 300)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    @MainActor
    func testPreviewShowsTheRightLayerAtTheRightTime() async throws {
        let manager = MV.ProjectManager(root: root)
        var project = MV.VideoProject()
        project.aspect = .landscape16x9
        let red = try manager.storeImage(data: try solidPNG(.red), projectID: project.id)
        let blue = try manager.storeImage(data: try solidPNG(.blue), projectID: project.id)
        MV.TimelineEngine.appendPhotos([red, blue], to: &project)            // red 0-3 s, blue 3-6 s
        let model = MV.MusicVideoEditorModel(manager: manager, project: project)

        // The preview reads decoded photos from the cache; warm it like playback prefetch does.
        let canvas = MV.VideoPreviewView.fitted(ratio: project.aspect.ratio, in: CGSize(width: 400, height: 300))
        let maxPixel = MV.PhotoImageCache.bucket(max(canvas.width, canvas.height) * UIScreen.main.scale)
        for layer in project.photos {
            _ = await MV.PhotoImageCache.shared.load(model.mediaURL(for: layer), maxPixel: maxPixel)
        }

        let first = try render(model, at: 1.0)
        let c1 = try pixel(first, 0.5, 0.5)
        XCTAssertGreaterThan(c1.r, 200); XCTAssertLessThan(c1.b, 60, "red photo at 1 s")

        let second = try render(model, at: 3.0)
        let c2 = try pixel(second, 0.5, 0.5)
        XCTAssertGreaterThan(c2.b, 200); XCTAssertLessThan(c2.r, 60, "blue photo starts exactly at 3 s")

        // At the very end (exclusive) nothing is drawn: black.
        let end = try render(model, at: 6.0)
        let ce = try pixel(end, 0.5, 0.5)
        XCTAssertLessThan(ce.r + ce.g + ce.b, 60, "ranges are half-open: nothing is active at exactly the end")
        model.mutate { $0.photos[1].core.isVisible = false }
        let hidden = try render(model, at: 4.0)
        let ch = try pixel(hidden, 0.5, 0.5)
        XCTAssertLessThan(ch.r + ch.g + ch.b, 60, "hidden layers are not drawn")

        // Letterbox: a 16:9 canvas inside 4:3 leaves black bars above and below.
        let bar = try pixel(first, 0.5, 0.02)
        XCTAssertLessThan(bar.r + bar.g + bar.b, 90, "outside the video frame is dark")

        // Transform: moving the red photo off to the side reveals black behind it.
        model.mutate { $0.photos[1].core.isVisible = true; $0.photos[0].core.transform.x = 1.4 }
        let moved = try render(model, at: 1.0)
        let cm = try pixel(moved, 0.5, 0.5)
        XCTAssertLessThan(cm.r, 80, "the photo moved away from the centre")
    }

    @MainActor
    func testPreviewDrawsTextOnTop() async throws {
        let manager = MV.ProjectManager(root: root)
        var project = MV.VideoProject()
        project.aspect = .landscape16x9
        let model = MV.MusicVideoEditorModel(manager: manager, project: project)
        model.mutate { _ = MV.TimelineEngine.addText("WWWWWWWW", at: .zero, to: &$0) }
        model.mutate { $0.texts[0].fontSize = 0.3; $0.texts[0].colorHex = "#FFFFFF"; $0.texts[0].hasShadow = false }
        let image = try render(model, at: 0.5)
        var bright = 0
        for ny in stride(from: 0.30, through: 0.70, by: 0.04) {
            for nx in stride(from: 0.25, through: 0.75, by: 0.02) {
                let p = try pixel(image, nx, ny)
                if p.r > 200 && p.g > 200 && p.b > 200 { bright += 1 }
            }
        }
        XCTAssertGreaterThan(bright, 15, "white text pixels near the centre")
    }

    // MARK: Phase 2 - timeline editing through the model

    @MainActor
    private func modelWithPhotos(_ count: Int) throws -> MV.MusicVideoEditorModel {
        let manager = MV.ProjectManager(root: root)
        let model = MV.MusicVideoEditorModel(manager: manager, project: MV.VideoProject())
        let png = try solidPNG(.red)
        let photo = try manager.storeImage(data: png, projectID: model.project.id)
        model.edit { _ = MV.TimelineEngine.appendPhotos(Array(repeating: photo, count: count), to: &$0) }
        model.selection = []
        return model
    }

    @MainActor
    func testDraggingAClipIsOneUndoStepAndSnapsWithAGuide() throws {
        let model = try modelWithPhotos(3)                       // 0-3, 3-6, 6-9
        let id = model.project.photos[1].core.id
        let session = try XCTUnwrap(model.beginClipEdit(id))
        XCTAssertEqual(model.selection, [id], "beginning a drag selects the clip")

        model.moveClips(session, deltaSeconds: 0.5)
        model.moveClips(session, deltaSeconds: 1.0)              // origin-based: not 1.5
        XCTAssertEqual(model.project.photos[1].core.start.seconds, 4, accuracy: 1e-9)
        XCTAssertNil(model.snapGuide, "nothing near, nothing to snap to")

        // Close to the end of the next clip (9 s): the edge snaps and a guide appears.
        model.moveClips(session, deltaSeconds: 2.97)
        XCTAssertEqual(model.project.photos[1].core.start.seconds, 6, accuracy: 1e-9)
        XCTAssertNotNil(model.snapGuide)
        model.endClipEdit()
        XCTAssertNil(model.snapGuide)

        model.undo()
        XCTAssertEqual(model.project.photos[1].core.start.seconds, 3, accuracy: 1e-9,
                       "the whole drag was ONE undo step")
        model.redo()
        XCTAssertEqual(model.project.photos[1].core.start.seconds, 6, accuracy: 1e-9)
    }

    @MainActor
    func testLockedClipsCannotBeDraggedOrTrimmed() throws {
        let model = try modelWithPhotos(2)
        let id = model.project.photos[0].core.id
        model.selection = [id]
        model.flagBinding(\.isLocked).wrappedValue = true
        XCTAssertNil(model.beginClipEdit(id))
        model.rippleDeleteSelection()
        XCTAssertEqual(model.project.photos.count, 2, "locked layers survive a ripple delete")
    }

    @MainActor
    func testTrimSplitRippleAndReorder() throws {
        let model = try modelWithPhotos(4)                       // 0-3, 3-6, 6-9, 9-12
        let ids = model.project.photos.map(\.core.id)

        // Trim the end of the second photo by one second.
        let session = try XCTUnwrap(model.beginClipEdit(ids[1]))
        model.trimClip(session, edge: .end, deltaSeconds: -1)
        model.endClipEdit()
        XCTAssertEqual(model.project.photos[1].core.duration.seconds, 2, accuracy: 1e-9)
        XCTAssertEqual(model.project.photos[1].core.start.seconds, 3, accuracy: 1e-9)

        // Split at the playhead.
        model.selection = [ids[2]]
        model.playback.seek(to: MV.ProjectTime(seconds: 7.5))
        model.splitAtPlayhead()
        XCTAssertEqual(model.project.photos.count, 5)
        XCTAssertEqual(model.project.photos[2].core.end.seconds, 7.5, accuracy: 1e-9)
        XCTAssertEqual(model.selection.count, 1, "the new second half is selected")
        model.undo()
        XCTAssertEqual(model.project.photos.count, 4)

        // A split that cannot happen records nothing and says why.
        model.selection = []
        model.playback.seek(to: MV.ProjectTime(seconds: 50))
        let undoBefore = model.canUndo
        model.splitAtPlayhead()
        XCTAssertNotNil(model.statusMessage)
        XCTAssertEqual(model.canUndo, undoBefore)

        // Ripple delete closes the gap; Pack lays the rest out back to back.
        model.selection = [ids[0]]
        model.rippleDeleteSelection()
        XCTAssertEqual(model.project.photos.count, 3)
        XCTAssertEqual(model.project.photos.first?.core.start.seconds ?? -1, 0, accuracy: 1e-9)
        model.packPhotos()
        let starts = model.project.photos.map(\.core.start.seconds)
        XCTAssertEqual(starts, [0, 2, 5])                        // 2 s, 3 s, 3 s photos

        // Reorder the last photo to the front.
        model.selection = [ids[3]]
        model.movePhotoInOrder(-1)
        model.movePhotoInOrder(-1)
        XCTAssertEqual(MV.TimelineEditing.orderedPhotoIDs(in: model.project).first, ids[3])

        model.setAllPhotoDurations(1.5)
        XCTAssertTrue(model.project.photos.allSatisfy { abs($0.core.duration.seconds - 1.5) < 1e-9 })
        model.selectAll()
        XCTAssertEqual(model.selection.count, 3)
    }

    @MainActor
    func testPreviewCrossfadesBetweenOverlappingPhotos() async throws {
        let manager = MV.ProjectManager(root: root)
        var project = MV.VideoProject()
        project.aspect = .landscape16x9
        let red = try manager.storeImage(data: try solidPNG(.red), projectID: project.id)
        let blue = try manager.storeImage(data: try solidPNG(.blue), projectID: project.id)
        MV.TimelineEngine.appendPhotos([red, blue], to: &project)
        project.photos[1].transitionIn = MV.PhotoTransition(kind: .crossfade, duration: 1.0)
        MV.TimelineEditing.packPhotos(in: &project)             // blue now starts at 2 s and overlaps red
        let model = MV.MusicVideoEditorModel(manager: manager, project: project)
        XCTAssertEqual(model.project.photos[1].core.start.seconds, 2, accuracy: 1e-9)

        let canvas = MV.VideoPreviewView.fitted(ratio: project.aspect.ratio, in: CGSize(width: 400, height: 300))
        let maxPixel = MV.PhotoImageCache.bucket(max(canvas.width, canvas.height) * UIScreen.main.scale)
        for layer in project.photos { _ = await MV.PhotoImageCache.shared.load(model.mediaURL(for: layer), maxPixel: maxPixel) }

        let before = try pixel(try render(model, at: 1.9), 0.5, 0.5)
        XCTAssertGreaterThan(before.r, 200); XCTAssertLessThan(before.b, 60, "only red before the transition")

        let mid = try pixel(try render(model, at: 2.5), 0.5, 0.5)
        XCTAssertGreaterThan(mid.r, 70); XCTAssertGreaterThan(mid.b, 70)
        XCTAssertLessThan(mid.r, 190); XCTAssertLessThan(mid.b, 190)
        XCTAssertEqual(Double(mid.r + mid.b), 255, accuracy: 60, "halfway the two photos mix")

        let after = try pixel(try render(model, at: 3.2), 0.5, 0.5)
        XCTAssertGreaterThan(after.b, 200); XCTAssertLessThan(after.r, 60)
    }

    @MainActor
    func testKenBurnsZoomsThePictureOverTheClip() async throws {
        let manager = MV.ProjectManager(root: root)
        var project = MV.VideoProject()
        project.aspect = .landscape16x9
        // White square in the middle of a black photo: zooming in makes it cover more pixels.
        let size = CGSize(width: 400, height: 225)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill(); ctx.fill(CGRect(x: 150, y: 62, width: 100, height: 100))
        }.pngData())
        let photo = try manager.storeImage(data: data, projectID: project.id)
        MV.TimelineEngine.appendPhotos([photo], to: &project)
        project.photos[0].motion = MV.PhotoMotion(preset: .zoomIn, intensity: 0.5)
        let model = MV.MusicVideoEditorModel(manager: manager, project: project)
        let canvas = MV.VideoPreviewView.fitted(ratio: project.aspect.ratio, in: CGSize(width: 400, height: 300))
        let maxPixel = MV.PhotoImageCache.bucket(max(canvas.width, canvas.height) * UIScreen.main.scale)
        _ = await MV.PhotoImageCache.shared.load(model.mediaURL(for: project.photos[0]), maxPixel: maxPixel)

        func whiteCount(_ image: UIImage) throws -> Int {
            var count = 0
            for ny in stride(from: 0.2, through: 0.8, by: 0.04) {
                for nx in stride(from: 0.2, through: 0.8, by: 0.04) {
                    if try pixel(image, nx, ny).r > 200 { count += 1 }
                }
            }
            return count
        }
        let start = try whiteCount(try render(model, at: 0.0))
        let end = try whiteCount(try render(model, at: 2.9))
        XCTAssertGreaterThan(end, start + 20, "the white square grows as the zoom-in plays")
    }

    // MARK: Phase 3 - real audio files

    /// A mono 44.1 kHz 16-bit sine written with AVAudioFile.
    private func writeSine(_ name: String, seconds: Double, frequency: Double = 440, amplitude: Float = 0.5) throws -> URL {
        let url = root.appendingPathComponent(name)
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false))
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        for i in 0..<Int(frames) { data[i] = amplitude * sinf(Float(2 * Double.pi * frequency * Double(i) / 44_100)) }
        try file.write(from: buffer)
        return url
    }

    /// RMS of the left channel between two times of a rendered file.
    private func rms(_ url: URL, from: Double, to: Double) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        let start = AVAudioFramePosition(from * rate)
        let count = AVAudioFrameCount(max(1, (to - from) * rate))
        file.framePosition = min(start, file.length - 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count))
        try file.read(into: buffer, frameCount: count)
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        var sum = 0.0
        for i in 0..<Int(buffer.frameLength) { sum += Double(samples[i] * samples[i]) }
        return (sum / Double(max(1, buffer.frameLength))).squareRoot()
    }

    func testWaveformFromRealSamples() async throws {
        let tone = try writeSine("tone.wav", seconds: 2)
        let wave = try await MV.WaveformGenerator.generate(url: tone, bucketsPerSecond: 100)
        XCTAssertEqual(wave.duration, 2, accuracy: 0.1)
        let mid = wave.peaks[20..<180]
        XCTAssertGreaterThan(mid.min() ?? 0, 0.3)
        XCTAssertLessThanOrEqual(mid.max() ?? 2, 0.56, "a 0.5-amplitude sine peaks at about 0.5")

        let silence = try writeSine("silence.wav", seconds: 1, amplitude: 0)
        let flat = try await MV.WaveformGenerator.generate(url: silence)
        XCTAssertLessThan(flat.peaks.max() ?? 1, 0.01)

        // The cache returns the same data from memory and from disk.
        let cache = MV.WaveformCache(directory: root.appendingPathComponent("wf"))
        let first = await cache.waveform(for: tone)
        XCTAssertEqual(first, wave)
        XCTAssertNotNil(cache.cached(for: tone))
        let fresh = MV.WaveformCache(directory: root.appendingPathComponent("wf"))
        XCTAssertEqual(fresh.cached(for: tone), wave, "persisted on disk")

        let notAudio = root.appendingPathComponent("x.txt")
        try Data("hello".utf8).write(to: notAudio)
        do { _ = try await MV.WaveformGenerator.generate(url: notAudio); XCTFail("must throw") } catch {}
    }

    func testStoreAudioValidatesAndCopies() async throws {
        let manager = MV.ProjectManager(root: root.appendingPathComponent("projects"))
        let id = UUID()
        let tone = try writeSine("song.wav", seconds: 1.5)
        let imported = try await manager.storeAudio(from: tone, projectID: id)
        XCTAssertEqual(imported.duration, 1.5, accuracy: 0.05)
        XCTAssertEqual(imported.originalName, "song")
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.mediaDirectory(for: id).appendingPathComponent(imported.mediaFile).path))

        let bad = root.appendingPathComponent("bad.mp3")
        try Data("this is not audio".utf8).write(to: bad)
        do {
            _ = try await manager.storeAudio(from: bad, projectID: id)
            XCTFail("must reject non-audio")
        } catch {
            XCTAssertEqual((try FileManager.default.contentsOfDirectory(atPath: manager.mediaDirectory(for: id).path)).count, 1,
                           "a rejected file is not left behind")
        }
    }

    // MARK: Phase 3 - offline mixdown (the export path)

    @MainActor
    private func mixProject(_ tone: URL, start: Double, duration: Double, fileSeconds: Double,
                            volume: Double = 1, fadeIn: Double = 0, loops: Bool = false,
                            projectSeconds: Double = 5) throws -> (MV.VideoProject, MV.ProjectManager) {
        let manager = MV.ProjectManager(root: root.appendingPathComponent("mix-\(UUID().uuidString)"))
        var project = MV.VideoProject()
        let name = "tone.wav"
        try FileManager.default.createDirectory(at: manager.mediaDirectory(for: project.id), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: tone, to: manager.mediaURL(projectID: project.id, file: name))
        MV.TimelineEngine.addAudio(.init(mediaFile: name, originalName: "tone", duration: fileSeconds),
                                   at: MV.ProjectTime(seconds: start), to: &project)
        project.audios[0].core.duration = MV.ProjectTime(seconds: duration)
        project.audios[0].volume = volume; project.audios[0].fadeIn = fadeIn; project.audios[0].loops = loops
        project.photos = []
        project.texts = []
        // Make the project exactly `projectSeconds` long with a silent text marker.
        MV.TimelineEngine.addText(".", at: MV.ProjectTime(seconds: projectSeconds - 3), to: &project)
        project.texts[0].core.duration = MV.ProjectTime(seconds: 3)
        return (project, manager)
    }

    @MainActor
    func testMixdownPlacesFadesAndLoopsAudioSampleAccurately() throws {
        let tone = try writeSine("mix.wav", seconds: 3)
        let (project, manager) = try mixProject(tone, start: 1, duration: 2, fileSeconds: 3, fadeIn: 1)
        let out = root.appendingPathComponent("mix.caf")
        XCTAssertTrue(try MV.AudioMixdown.render(project: project,
                      mediaURL: { manager.mediaURL(projectID: project.id, file: $0.mediaFile) }, to: out))
        XCTAssertEqual(Double(try AVAudioFile(forReading: out).length) / 44_100, 5, accuracy: 0.05, "as long as the project")

        XCTAssertLessThan(try rms(out, from: 0.1, to: 0.9), 0.005, "silence before the clip starts")
        let early = try rms(out, from: 1.05, to: 1.35)          // inside the fade-in
        let full = try rms(out, from: 1.8, to: 2.4)             // fully faded in
        XCTAssertGreaterThan(full, 0.1, "the tone is audible")
        XCTAssertLessThan(early, full * 0.75, "fade-in ramps the level up")
        XCTAssertLessThan(try rms(out, from: 3.2, to: 4.8), 0.005, "silence after the clip ends")
    }

    @MainActor
    func testMixdownVolumeAndLoopAndMute() throws {
        let tone = try writeSine("mix2.wav", seconds: 1)
        func render(_ project: MV.VideoProject, _ manager: MV.ProjectManager, _ name: String) throws -> URL? {
            let out = root.appendingPathComponent(name)
            return try MV.AudioMixdown.render(project: project,
                mediaURL: { manager.mediaURL(projectID: project.id, file: $0.mediaFile) }, to: out) ? out : nil
        }
        let (loud, m1) = try mixProject(tone, start: 0, duration: 4, fileSeconds: 1, volume: 1)
        let (quiet, m2) = try mixProject(tone, start: 0, duration: 4, fileSeconds: 1, volume: 0.5)
        let loudOut = try XCTUnwrap(try render(loud, m1, "loud.caf")), quietOut = try XCTUnwrap(try render(quiet, m2, "quiet.caf"))
        XCTAssertEqual(try rms(quietOut, from: 0.2, to: 0.8) / try rms(loudOut, from: 0.2, to: 0.8), 0.5, accuracy: 0.05, "volume scales the signal")
        XCTAssertLessThan(try rms(loudOut, from: 2.0, to: 3.0), 0.005, "a 1 s file does not loop unless asked to")

        let (loops, m3) = try mixProject(tone, start: 0, duration: 4, fileSeconds: 1, loops: true)
        let loopOut = try XCTUnwrap(try render(loops, m3, "loop.caf"))
        XCTAssertGreaterThan(try rms(loopOut, from: 2.1, to: 2.9), 0.1, "looping keeps the music going")
        XCTAssertGreaterThan(try rms(loopOut, from: 3.1, to: 3.8), 0.1)

        var muted = loud
        muted.audios[0].core.isVisible = false
        XCTAssertNil(try render(muted, m1, "muted.caf"), "a muted project writes nothing")
        var none = loud
        none.audios = []
        XCTAssertNil(try render(none, m1, "none.caf"))
    }

    // MARK: Transport observer (the audio engine's contract with the master clock)

    private final class RecordingObserver: MV.TransportObserver {
        var events: [String] = []
        var master: MV.ProjectTime?
        func transportDidStart(at time: MV.ProjectTime) { events.append("start") }
        func transportDidStop() { events.append("stop") }
        func transportDidSeek(to time: MV.ProjectTime, isPlaying: Bool) { events.append("seek:\(isPlaying)") }
        func transportTick(at time: MV.ProjectTime) { if events.last != "tick" { events.append("tick") } }
        func masterTime() -> MV.ProjectTime? { master }
    }

    func testMasterClockNotifiesObserversAndFollowsTheAudioClock() {
        let engine = MV.PlaybackEngine()
        let observer = RecordingObserver()
        engine.observer = observer
        engine.configure(duration: MV.ProjectTime(seconds: 10), fps: 30)
        engine.seek(to: MV.ProjectTime(seconds: 2))
        engine.play()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        engine.seek(to: MV.ProjectTime(seconds: 5))
        engine.pause()
        XCTAssertEqual(Array(observer.events.prefix(3)), ["seek:false", "start", "tick"])
        XCTAssertTrue(observer.events.contains("seek:true"), "seeking while playing reschedules the audio")
        XCTAssertEqual(observer.events.last, "stop")

        // When the audio hardware reports a time, the picture follows it.
        engine.seek(to: .zero)
        observer.master = MV.ProjectTime(seconds: 7)
        engine.play()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(engine.time.seconds, 7, accuracy: 1e-6)
        engine.pause()

        // The end of the project stops observers too.
        observer.master = nil
        observer.events.removeAll()
        engine.seek(to: MV.ProjectTime(seconds: 9.95))
        engine.play()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertFalse(engine.isPlaying)
        XCTAssertTrue(observer.events.contains("stop"))
    }

    // MARK: Phase 4 - vinyl in the real preview

    @MainActor
    func testVinylSpinsWithTimeAndStandsStillWhenTimeStands() async throws {
        let manager = MV.ProjectManager(root: root)
        var project = MV.VideoProject()
        project.aspect = .square
        // Cover: left half blue, right half red.
        let size = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let png = try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            UIColor.red.setFill(); ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 200))
        }.pngData())
        let cover = try manager.storeImage(data: png, projectID: project.id)
        MV.TimelineEngine.addVinyl(at: .zero, duration: MV.ProjectTime(seconds: 4), coverFile: cover.mediaFile, to: &project)
        project.vinyls[0].rpm = 60
        project.vinyls[0].reflection = 0
        project.vinyls[0].shadow = 0
        project.vinyls[0].glow = 0
        project.vinyls[0].labelScale = 0.5
        let model = MV.MusicVideoEditorModel(manager: manager, project: project)
        _ = await MV.PhotoImageCache.shared.load(model.manager.mediaURL(projectID: project.id, file: cover.mediaFile), maxPixel: 512)

        // Label spans the middle half of the record; probe a point right of the centre.
        func right(_ seconds: Double) throws -> (r: Int, g: Int, b: Int) {
            try pixel(try render(model, at: seconds), 0.5 + 0.06, 0.5)
        }
        let a = try right(0.0)
        XCTAssertGreaterThan(a.r, 150); XCTAssertLessThan(a.b, 100, "right half of the cover is red at angle 0")
        let half = try right(0.5)                                  // 180 degrees at 60 rpm
        XCTAssertGreaterThan(half.b, 150); XCTAssertLessThan(half.r, 100, "after half a turn the blue half is on the right")
        let full = try right(1.0)                                  // 360 degrees
        XCTAssertGreaterThan(full.r, 150); XCTAssertLessThan(full.b, 100, "a full turn is back to the start")
        // Same time, same picture: the angle is a function of the clock.
        let again = try right(0.5)
        XCTAssertEqual(again.r, half.r); XCTAssertEqual(again.b, half.b)
    }

    @MainActor
    func testToolbarActionsAddAudioAndVinylToTheProject() async throws {
        let manager = MV.ProjectManager(root: root.appendingPathComponent("p"))
        let model = MV.MusicVideoEditorModel(manager: manager, project: MV.VideoProject())
        await model.importAudio(from: try writeSine("a.wav", seconds: 2))
        XCTAssertEqual(model.project.audios.count, 1)
        XCTAssertEqual(model.project.duration.seconds, 3, accuracy: 0.01, "the 2 s song fits inside the minimum")
        XCTAssertEqual(model.selection, [model.project.audios[0].core.id])
        XCTAssertTrue(model.visibleTracks.contains(.audio))

        model.addVinyl()
        XCTAssertEqual(model.project.vinyls.count, 1)
        XCTAssertTrue(model.visibleTracks.contains(.vinyl))
        XCTAssertGreaterThan(model.timelineHeight, MV.TimelineRulerView.height + 48 * 3)

        // Undo removes the vinyl; the audio engine follows the project.
        model.undo()
        XCTAssertTrue(model.project.vinyls.isEmpty)
        model.undo()
        XCTAssertTrue(model.project.audios.isEmpty)

        await model.importAudio(from: root.appendingPathComponent("missing.wav"))
        XCTAssertNotNil(model.statusMessage, "a bad file is reported, not ignored")
    }

    // MARK: Phase 5 - karaoke lyrics

    @MainActor
    func testLyricsNeedMusicAndThenFollowTheSong() async throws {
        let manager = MV.ProjectManager(root: root.appendingPathComponent("p"))
        let model = MV.MusicVideoEditorModel(manager: manager, project: MV.VideoProject())
        model.addLyrics()
        XCTAssertTrue(model.project.lyrics.isEmpty, "no music, no lyrics layer")
        XCTAssertNotNil(model.statusMessage)

        await model.importAudio(from: try writeSine("song.wav", seconds: 4))
        model.addLyrics()
        let layer = try XCTUnwrap(model.project.lyrics.first)
        XCTAssertEqual(layer.audioLayerID, model.project.audios[0].core.id)
        XCTAssertEqual(model.lyricsEditorLayerID, layer.core.id, "the editor opens for the new layer")
        XCTAssertEqual(layer.core.start, model.project.audios[0].core.start)

        model.distributePlainLyrics("xin chào\ncác bạn", into: layer.core.id)
        let spread = try XCTUnwrap(model.lyrics(layer.core.id))
        XCTAssertEqual(spread.lines.count, 2)
        XCTAssertEqual(spread.lines[0].start, model.project.audios[0].sourceStart, accuracy: 1e-9, "spread over the audio's range")
        model.undo()
        XCTAssertTrue(try XCTUnwrap(model.lyrics(layer.core.id)).lines.isEmpty, "importing lyrics is one undo step")

        model.shiftLyrics(layer.core.id, by: 1)          // no lines: harmless
        XCTAssertTrue(try XCTUnwrap(model.lyrics(layer.core.id)).lines.isEmpty)
    }

    @MainActor
    func testImportLRCSRTAndExportRoundTrip() async throws {
        let manager = MV.ProjectManager(root: root.appendingPathComponent("p"))
        let model = MV.MusicVideoEditorModel(manager: manager, project: MV.VideoProject())
        await model.importAudio(from: try writeSine("song.wav", seconds: 6))
        model.addLyrics()
        let id = try XCTUnwrap(model.project.lyrics.first).core.id

        let lrc = root.appendingPathComponent("a.lrc")
        try "[00:01.00]Hello world\n[00:03.00]Second line\n".write(to: lrc, atomically: true, encoding: .utf8)
        model.importLyricsFile(lrc, into: id)
        XCTAssertEqual(try XCTUnwrap(model.lyrics(id)).lines.map(\.text), ["Hello world", "Second line"])

        let srt = root.appendingPathComponent("a.srt")
        try "1\n00:00:00,500 --> 00:00:02,000\nFrom srt\n".write(to: srt, atomically: true, encoding: .utf8)
        model.importLyricsFile(srt, into: id)
        XCTAssertEqual(try XCTUnwrap(model.lyrics(id)).lines.map(\.text), ["From srt"])

        let txt = root.appendingPathComponent("a.txt")
        try "just\nplain words".write(to: txt, atomically: true, encoding: .utf8)
        model.importLyricsFile(txt, into: id)
        XCTAssertEqual(try XCTUnwrap(model.lyrics(id)).lines.count, 2, "untimed text is spread over the song")

        let out = try XCTUnwrap(model.exportLRC(id))
        let written = try String(contentsOf: out, encoding: .utf8)
        XCTAssertTrue(written.contains("just") && written.contains("<"), "enhanced LRC with word tags")
        XCTAssertEqual(MV.LRCParser.parse(written).map(\.text), ["just", "plain words"])

        model.importLyricsFile(root.appendingPathComponent("missing.lrc"), into: id)
        XCTAssertNotNil(model.statusMessage, "a bad file is reported")
    }

    /// A recogniser from another provider plugs in without touching the lyrics engine.
    private struct FakeRecognizer: MV.LyricsRecognizer {
        var name: String { "fake" }
        var words: [MV.RecognizedWord]
        func recognize(audioURL: URL, from: Double, to: Double, locale: Locale) async throws -> [MV.RecognizedWord] { words }
    }

    @MainActor
    func testRecognizerResultsAlignTheTypedLyrics() async throws {
        let manager = MV.ProjectManager(root: root.appendingPathComponent("p"))
        let model = MV.MusicVideoEditorModel(manager: manager, project: MV.VideoProject())
        await model.importAudio(from: try writeSine("song.wav", seconds: 5))
        model.addLyrics()
        let id = try XCTUnwrap(model.project.lyrics.first).core.id
        let fake = FakeRecognizer(words: [.init(text: "xin", start: 0.5, end: 0.9), .init(text: "chao", start: 1.0, end: 1.4),
                                          .init(text: "ban", start: 2.0, end: 2.5)])
        await model.recognizeLyrics(id, rows: ["Xin chào", "bạn"], recognizer: fake)
        let lines = try XCTUnwrap(model.lyrics(id)).lines
        XCTAssertEqual(lines.map(\.text), ["Xin chào", "bạn"])
        XCTAssertEqual(lines[0].words[0].start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(lines[1].words[0].start, 2.0, accuracy: 1e-9)
        XCTAssertEqual(model.lyricsBusy, "")

        // With no typed rows the recognised words become the lyrics.
        await model.recognizeLyrics(id, rows: [], recognizer: fake)
        XCTAssertEqual(try XCTUnwrap(model.lyrics(id)).wordCount, 3)

        await model.recognizeLyrics(id, rows: ["a"], recognizer: FakeRecognizer(words: []))
        XCTAssertNotNil(model.statusMessage, "no recognised words is reported")
        XCTAssertEqual(try XCTUnwrap(model.lyrics(id)).wordCount, 3, "and the lyrics are left alone")
    }

    @MainActor
    func testKaraokeFillsTheWordAsTimePasses() async throws {
        let manager = MV.ProjectManager(root: root)
        var project = MV.VideoProject()
        project.aspect = .landscape16x9
        let model = MV.MusicVideoEditorModel(manager: manager, project: project)
        let line = MV.LyricLine(words: [MV.LyricWord(text: "WWWW", start: 0, end: 2)])
        model.mutate { _ = MV.TimelineEngine.addLyrics([line], audioID: nil, to: &$0) }
        model.mutate {
            $0.lyrics[0].fontSize = 0.3; $0.lyrics[0].showNextLine = false; $0.lyrics[0].hasShadow = false
            $0.lyrics[0].highlightColorHex = "#FFD54F"; $0.lyrics[0].normalColorHex = "#FFFFFF"
        }

        func counts(at seconds: Double) throws -> (yellow: Int, white: Int) {
            let image = try render(model, at: seconds)
            var yellow = 0, white = 0
            for ny in stride(from: 0.55, through: 0.95, by: 0.02) {
                for nx in stride(from: 0.05, through: 0.95, by: 0.01) {
                    let p = try pixel(image, nx, ny)
                    if p.r > 200 && p.g > 150 && p.b < 140 { yellow += 1 }
                    if p.r > 220 && p.g > 220 && p.b > 220 { white += 1 }
                }
            }
            return (yellow, white)
        }
        let start = try counts(at: 0.02), middle = try counts(at: 1.0), end = try counts(at: 1.98)
        XCTAssertEqual(start.yellow, 0, "nothing sung yet")
        XCTAssertGreaterThan(start.white, 10, "the word is visible before it is sung")
        XCTAssertGreaterThan(middle.yellow, 5); XCTAssertGreaterThan(middle.white, 5, "half sung: both colours")
        XCTAssertGreaterThan(end.yellow, middle.yellow); XCTAssertLessThan(end.white, middle.white)
        let again = try counts(at: 1.0)
        XCTAssertEqual(again.yellow, middle.yellow); XCTAssertEqual(again.white, middle.white, "same time, same picture")
    }
}
