import XCTest
import UIKit
import ImageIO
@testable import SmartVideo

@MainActor
final class PhotoExportTests: XCTestCase {
    private func imageData() throws -> Data {
        let bitmap = UIGraphicsImageRenderer(size: CGSize(
            width: 256, height: 192)).pngData { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 256, height: 192))
            UIColor.systemRed.setFill()
            renderer.fill(CGRect(x: 30, y: 40, width: 100, height: 85))
        }
        return bitmap
    }

    func testHighResolutionSizingKeepsAspectRatioAndCapsMegaPixels()
        throws {
        let source = CGSize(width: 2400, height: 1600)
        var setting = PhotoExportSettings()
        setting.resolution = .fourK
        let size = try setting.outputSize(for: source)
        XCTAssertEqual(Int(size.width), 4096)
        XCTAssertEqual(Int(size.height), 2731)
        setting.resolution = .original
        let original = try setting.outputSize(for: source)
        XCTAssertEqual(Int(original.width), 2400)
        XCTAssertEqual(Int(original.height), 1600)
        setting.resolution = .custom
        setting.customWidth = 800
        setting.customHeight = 600
        let custom = try setting.outputSize(for: source)
        XCTAssertEqual(Int(custom.width), 800)
        XCTAssertEqual(Int(custom.height), 533)
        setting.resolution = .eightK
        setting.upscaleFactor = 4
        XCTAssertThrowsError(try setting.outputSize(for: source))
    }

    func testRealJPEGAndPNGExportDimensionsAndImageType() throws {
        let data = try imageData()
        let input = try MediaStorage.storeImage(data: data)
        defer { try? FileManager.default.removeItem(at: input) }
        let clip = TimelineClip(
            kind: .image, fileURL: input,
            duration: 3, originalDuration: 3
        )
        for format in [PhotoExportFormat.jpeg, .png] {
            var settings = PhotoExportSettings()
            settings.format = format
            settings.resolution = .twoK
            let url = try PhotoExporter.export(
                clip: clip, settings: settings)
            defer { try? FileManager.default.removeItem(at: url) }
            let source = try XCTUnwrap(
                CGImageSourceCreateWithURL(url as CFURL, nil))
            let properties = try XCTUnwrap(
                CGImageSourceCopyPropertiesAtIndex(
                    source, 0, nil) as? [CFString: Any])
            XCTAssertEqual(
                (properties[kCGImagePropertyPixelWidth] as? Int), 2048)
            XCTAssertEqual(
                (properties[kCGImagePropertyPixelHeight] as? Int), 1536)
            XCTAssertEqual(url.pathExtension, format.fileExtension)
        }
    }

    func testKeepsOriginalLosslessPNGBytesWhenImporting() throws {
        let raw = try imageData()
        let copied = try MediaStorage.storeImage(data: raw)
        defer { try? FileManager.default.removeItem(at: copied) }
        XCTAssertEqual(copied.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: copied), raw)
    }

    func testPhotoBatchZIPProducesValidSignatures() throws {
        let raw = try imageData()
        let file = try MediaStorage.storeImage(data: raw)
        defer { try? FileManager.default.removeItem(at: file) }
        let zip = try PhotoBatchZIP.create(files: [file, file])
        defer { try? FileManager.default.removeItem(at: zip) }
        let bytes = try Data(contentsOf: zip)
        XCTAssertGreaterThan(bytes.count, raw.count * 2)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertEqual(Array(bytes.suffix(22).prefix(4)),
                       [0x50, 0x4b, 0x05, 0x06])
    }

    func testPhotoExportRejectsVideo() throws {
        let movie = TimelineClip(
            kind: .video,
            fileURL: URL(fileURLWithPath: "/tmp/movie.mp4"),
            duration: 4, originalDuration: 4
        )
        XCTAssertThrowsError(
            try PhotoExporter.export(
                clip: movie, settings: PhotoExportSettings()))
    }
}
