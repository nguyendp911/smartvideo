import XCTest
import SwiftUI
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
}
