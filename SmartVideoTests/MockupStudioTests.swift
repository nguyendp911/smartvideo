import XCTest
import CoreImage
import ImageIO
import UIKit
@testable import SmartVideo

/// Real files, real Core Image renders: nothing here is mocked.
final class MockupStudioTests: XCTestCase {
    private let context = CIContext()
    private let canvas = CGRect(x: 0, y: 0, width: 400, height: 300)

    // MARK: Helpers

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
        CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: canvas)
    }

    /// RGBA of one pixel at normalised (x, y), origin top-left.
    private func pixel(_ image: CIImage, _ nx: Double, _ ny: Double) -> (r: Double, g: Double, b: Double, a: Double) {
        let e = image.extent
        let x = min(e.maxX - 1, max(e.minX, e.minX + floor(nx * e.width)))
        let y = min(e.maxY - 1, max(e.minY, e.minY + floor((1 - ny) * e.height)))
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255, Double(bytes[3]) / 255)
    }

    private func luma(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Double {
        0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
    }

    private func meanLuma(_ image: CIImage) -> Double {
        let averaged = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        return luma(pixel(averaged.cropped(to: CGRect(x: image.extent.minX, y: image.extent.minY, width: 1, height: 1)), 0, 0))
    }

    private func layer(_ id: String, opacity: Double? = nil) -> MockupOverlayClip {
        let asset = MockupStudioCatalog.asset(id)!
        var clip = MockupStudioSession.makeLayer(asset, start: 0, duration: 10)
        if let opacity { clip.opacity = opacity }
        return clip
    }

    private func render(_ source: CIImage, _ layers: [MockupOverlayClip]) throws -> CIImage {
        try MockupOverlayRenderer.apply(
            try MockupOverlayRenderer.apply(source, overlays: layers, second: 1, depth: .behindPerson),
            overlays: layers, second: 1, depth: .front
        )
    }

    // MARK: Shipped files

    func testEveryAssetShipsRealDecodableImagesWithAlphaWhereNeeded() throws {
        for asset in MockupStudioCatalog.allAssets {
            let url = try XCTUnwrap(asset.imageURL, "missing image for \(asset.id)")
            let thumb = try XCTUnwrap(asset.thumbnailURL, "missing thumbnail for \(asset.id)")
            XCTAssertEqual(url.pathExtension, "webp", asset.id)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), asset.id)
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), asset.id)
            XCTAssertEqual(image.width, asset.pixelWidth, asset.id)
            XCTAssertEqual(image.height, asset.pixelHeight, asset.id)
            let small = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
                try XCTUnwrap(CGImageSourceCreateWithURL(thumb as CFURL, nil)), 0, nil), asset.id)
            XCTAssertEqual(small.width, 256, "thumbnail \(asset.id)")

            // Sample the artwork on a small RGBA grid.
            let w = 64, h = 64
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            let alphas = stride(from: 3, to: px.count, by: 4).map { Int(px[$0]) }
            XCTAssertGreaterThan(alphas.max() ?? 0, 0, "\(asset.id) is fully transparent")
            switch asset.kind {
            case .overlay:
                break
            case .background:
                XCTAssertEqual(alphas.min(), 255, "\(asset.id) background must be opaque")
            case .scene:
                let slot = try XCTUnwrap(asset.slot)
                let col = Int((slot.x + slot.width / 2) * Double(w)), row = Int((slot.y + slot.height / 2) * Double(h))
                XCTAssertLessThan(Int(px[(row * w + col) * 4 + 3]), 12, "\(asset.id) window must be transparent")
                XCTAssertEqual(px[3], 255, "\(asset.id) frame area must be opaque")
            }
        }
    }

    func testBlendModesMapToRealCoreImageFilters() {
        for mode in MockupBlendMode.allCases {
            XCTAssertNotNil(CIFilter(name: MockupOverlayRenderer.blendFilterName(mode)), "\(mode)")
        }
    }

    // MARK: Rendering

    func testMultiplyShadowDarkensAndZeroOpacityChangesNothing() throws {
        let source = solid(0.6, 0.6, 0.6)
        let shadowed = try render(source, [layer("window-shadow")])
        XCTAssertLessThan(meanLuma(shadowed), meanLuma(source) - 0.03)

        let invisible = try render(source, [layer("window-shadow", opacity: 0)])
        XCTAssertEqual(meanLuma(invisible), meanLuma(source), accuracy: 0.004)
    }

    func testSaturationAndNewBlendModesChangeThePixels() throws {
        let source = solid(0.7, 0.3, 0.2)
        var tint = layer("duotone", opacity: 1)
        tint.blendMode = .difference
        let diff = try render(source, [tint])
        XCTAssertNotEqual(pixel(diff, 0.5, 0.5).r, pixel(source, 0.5, 0.5).r, accuracy: 0.02)

        var dodge = layer("light-leak", opacity: 1)
        dodge.blendMode = .colorDodge
        XCTAssertGreaterThan(meanLuma(try render(source, [dodge])), meanLuma(source))

        var grey = layer("duotone", opacity: 1)
        grey.blendMode = .normal
        let coloured = try render(source, [grey])
        grey.saturation = 0
        let desaturated = try render(source, [grey])
        let c = pixel(coloured, 0.5, 0.5), d = pixel(desaturated, 0.5, 0.5)
        XCTAssertGreaterThan(max(c.r, c.g, c.b) - min(c.r, c.g, c.b), 0.1)
        XCTAssertLessThan(max(d.r, d.g, d.b) - min(d.r, d.g, d.b), 0.03)
    }

    func testMaskHidesTheMaskedSideOnly() throws {
        let source = solid(0.4, 0.4, 0.4)
        var leak = layer("light-leak", opacity: 1)
        let open = try render(source, [leak])
        XCTAssertGreaterThan(luma(pixel(open, 0.02, 0.5)), luma(pixel(source, 0.02, 0.5)) + 0.05)

        leak.mask = MockupMask(kind: .fadeLeft, size: 1, feather: 0.1)
        let masked = try render(source, [leak])
        XCTAssertEqual(luma(pixel(masked, 0.02, 0.5)), luma(pixel(source, 0.02, 0.5)), accuracy: 0.02)
        // The unmasked side is untouched by the mask.
        XCTAssertEqual(luma(pixel(masked, 0.98, 0.9)), luma(pixel(open, 0.98, 0.9)), accuracy: 0.03)
    }

    func testSceneFitsThePhotoIntoItsWindow() throws {
        let red = solid(1, 0, 0)
        let framed = try render(red, [layer("photo-frame")])
        let inside = pixel(framed, 0.5, 0.5)
        XCTAssertGreaterThan(inside.r, 0.9); XCTAssertLessThan(inside.g, 0.12)
        let wall = pixel(framed, 0.02, 0.02)
        XCTAssertFalse(wall.r > 0.9 && wall.g < 0.2, "the frame/wall must cover the photo outside the window")
        XCTAssertGreaterThan(wall.g, 0.4)
    }

    func testBackgroundMakesAnInsetPhotoCard() throws {
        let red = solid(1, 0, 0)
        let carded = try render(red, [layer("beige-background")])
        let centre = pixel(carded, 0.5, 0.5)
        XCTAssertGreaterThan(centre.r, 0.9); XCTAssertLessThan(centre.g, 0.12)
        let corner = pixel(carded, 0.01, 0.01)
        XCTAssertGreaterThan(corner.g, 0.5, "corner shows the beige backdrop")
    }

    func testLayersInDifferentOrderGiveDifferentResults() throws {
        let source = solid(0.5, 0.5, 0.5)
        var a = layer("sunlight-rays", opacity: 1); a.blendMode = .screen
        var b = layer("vignette", opacity: 1); b.blendMode = .multiply
        let ab = try render(source, [a, b]), ba = try render(source, [b, a])
        XCTAssertNotEqual(luma(pixel(ab, 0.05, 0.05)), luma(pixel(ba, 0.05, 0.05)), accuracy: 0.001)
    }

    func testOldProceduralLayersStillRender() throws {
        let asset = try XCTUnwrap(MockupAssetLibrary.asset("window-soft"))
        let old = MockupAssetLibrary.makeClip(asset, at: 0, duration: 5)
        let source = solid(0.6, 0.6, 0.6)
        XCTAssertLessThan(meanLuma(try render(source, [old])), meanLuma(source))
    }

    // MARK: Export

    func testStillExportKeepsFullResolutionAndWritesPNGAndJPEG() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mockup-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let photo = dir.appendingPathComponent("photo.png")
        let cg = try XCTUnwrap(context.createCGImage(solid(0.5, 0.6, 0.7), from: CGRect(x: 0, y: 0, width: 640, height: 480)))
        try XCTUnwrap(UIImage(cgImage: cg).pngData()).write(to: photo)
        let clip = TimelineClip(kind: .image, fileURL: photo, duration: 3, originalDuration: 3)
        let layers = [layer("vignette")]

        for format in MockupStudioRenderer.ExportFormat.allCases {
            let url = try await MockupStudioRenderer.export(clip: clip, local: 0.5, layers: layers, second: 0.5, format: format)
            defer { try? FileManager.default.removeItem(at: url) }
            XCTAssertEqual(url.pathExtension, format.fileExtension)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 640)
            XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 480)
        }
    }

    // MARK: Session: add / replace / undo / favourites

    @MainActor
    func testSessionAddsReplacesAndUndoes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mockup-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let photo = dir.appendingPathComponent("photo.png")
        let cg = try XCTUnwrap(context.createCGImage(solid(0.2, 0.4, 0.6), from: CGRect(x: 0, y: 0, width: 80, height: 60)))
        try XCTUnwrap(UIImage(cgImage: cg).pngData()).write(to: photo)

        let model = EditorViewModel()
        model.clips = [TimelineClip(kind: .image, fileURL: photo, duration: 4, originalDuration: 4)]
        model.timelineSecond = 1
        let session = MockupStudioSession(model: model)

        session.add(try XCTUnwrap(MockupStudioCatalog.asset("rain")))
        session.add(try XCTUnwrap(MockupStudioCatalog.asset("snow")))
        XCTAssertEqual(model.mockupOverlays.count, 2)
        XCTAssertEqual(model.mockupOverlays[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(model.mockupOverlays[0].duration, 4, accuracy: 0.001)
        XCTAssertEqual(session.selectedLayer?.assetID, "snow")

        // Only one frame per photo: the second replaces the first.
        session.add(try XCTUnwrap(MockupStudioCatalog.asset("polaroid-frame")))
        session.add(try XCTUnwrap(MockupStudioCatalog.asset("photo-frame")))
        let frames = model.mockupOverlays.filter { MockupStudioCatalog.asset($0.assetID)?.kind == .scene }
        XCTAssertEqual(frames.map(\.assetID), ["photo-frame"])

        session.duplicateSelected()
        XCTAssertEqual(model.mockupOverlays.filter { $0.assetID == "photo-frame" }.count, 2)
        session.undo()
        XCTAssertEqual(model.mockupOverlays.filter { $0.assetID == "photo-frame" }.count, 1)
        session.redo()
        XCTAssertEqual(model.mockupOverlays.filter { $0.assetID == "photo-frame" }.count, 2)

        session.selectedID = model.mockupOverlays.last { $0.assetID == "photo-frame" }?.id      // undo cleared the selection
        let beforeDelete = model.mockupOverlays.count
        session.deleteSelected()
        XCTAssertEqual(model.mockupOverlays.count, beforeDelete - 1)
        session.undo()
        XCTAssertEqual(model.mockupOverlays.count, beforeDelete)

        // Layer cap.
        for asset in MockupStudioCatalog.allAssets.filter({ $0.kind == .overlay }).prefix(20) { session.add(asset) }
        XCTAssertLessThanOrEqual(model.mockupOverlays.count, MockupStudioSession.maxLayers)

        // Recents + favourites are recorded.
        XCTAssertFalse(session.usage.recents.isEmpty)
        XCTAssertTrue(session.usage.recents.contains("photo-frame") || session.usage.recents.count == MockupStudioUsage.maxRecents)
        XCTAssertLessThanOrEqual(session.usage.recents.count, MockupStudioUsage.maxRecents)
        let first = try XCTUnwrap(MockupStudioCatalog.asset("rain"))
        let before = session.isFavorite(first)
        session.toggleFavorite(first)
        XCTAssertNotEqual(session.isFavorite(first), before)
        session.toggleFavorite(first)
    }

    @MainActor
    func testSessionRefusesWithoutAPhoto() {
        let model = EditorViewModel()
        let session = MockupStudioSession(model: model)
        session.add(MockupStudioCatalog.allAssets[0])
        XCTAssertTrue(model.mockupOverlays.isEmpty)
        XCTAssertFalse(session.message.isEmpty)
    }
}
