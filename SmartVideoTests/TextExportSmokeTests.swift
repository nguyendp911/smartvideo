import XCTest
import AVFoundation
import CoreImage
import UIKit
@testable import SmartVideo

/// Regression test for the real user-reported bug: v5.5 could compile an
/// IPA but export a video with completely invisible title text.
/// Check the rendered pixels, not just the storyboard or Codable schema.
@MainActor
final class TextExportSmokeTests: XCTestCase {
    private let canvas = CGSize(width: 320, height: 480)

    private func brightPixelCount(
        _ image: CGImage, threshold: UInt8 = 30
    ) -> Int {
        let bpr = image.width * 4
        var bytes = [UInt8](
            repeating: 0, count: bpr * image.height
        )
        let success = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: bpr,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(
                x: 0, y: 0, width: image.width,
                height: image.height
            ))
            return true
        }
        guard success else { return 0 }
        var count = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            if bytes[index + 3] > 20 &&
                (bytes[index] > threshold ||
                 bytes[index + 1] > threshold ||
                 bytes[index + 2] > threshold) {
                count += 1
            }
        }
        return count
    }

    func testGlyphRasterHasVisiblePixelsForEveryFill() throws {
        let size = CGSize(width: 360, height: 120)
        var title = TextOverlayClip()
        title.text = "VIEPN"
        title.fontSize = 64
        title.colorHex = "FFD635"

        for fill in [TextFillMode.solid, .gradient, .image,
                     .video] {
            title.fillMode = fill
            let frame: CGImage? = fill == .video ?
                UIGraphicsImageRenderer(
                    size: CGSize(width: 64, height: 64)
                ).image { _ in
                    UIColor.cyan.setFill()
                    UIRectFill(CGRect(
                        x: 0, y: 0, width: 64, height: 64
                    ))
                }.cgImage : nil
            let pixels = TextMaskMedia.rasterizedGlyph(
                for: title, size: size, videoFrame: frame
            )
            XCTAssertNotNil(pixels, "\(fill.rawValue) has no bitmap")
            if let pixels {
                XCTAssertGreaterThan(
                    brightPixelCount(pixels), 500,
                    "\(fill.rawValue) has no visible glyph pixels"
                )
            }
        }
        title.strokeWidth = 3
        title.strokeHex = "FE4020"
        let outline = TextMaskMedia.outlineImage(
            for: title, size: size
        )
        XCTAssertNotNil(outline)
        if let outline {
            XCTAssertGreaterThan(
                brightPixelCount(outline), 50
            )
        }
    }

    func testBehindPersonCompositingIsNotTransparent() throws {
        let rect = CGRect(x: 0, y: 0, width: 320,
                          height: 480)
        let original = CIImage(
            color: CIColor(red: 0, green: 0,
                           blue: 0, alpha: 1)
        ).cropped(to: rect)
        var title = TextOverlayClip()
        title.text = "TEST"
        title.fontSize = 64
        title.useBackground = false
        title.colorHex = "FFFFFF"
        title.depthMode = .behindPerson
        title.start = 0
        title.duration = 2

        let emptyPerson = CIImage(
            color: CIColor(red: 0, green: 0,
                           blue: 0, alpha: 1)
        ).cropped(to: rect)
        let rendered = try TextBehindPersonRenderer.apply(
            to: original, items: [title],
            projectTime: 1,
            maskOverride: emptyPerson
        )
        let context = CIContext()
        guard let bitmap = context.createCGImage(
            rendered, from: rect
        ) else {
            XCTFail("Could not rasterize behind-person title")
            return
        }
        XCTAssertGreaterThan(
            brightPixelCount(bitmap), 500,
            "Text behind the person is invisible in CoreImage output"
        )
    }

    func testFrontTitleIsVisibleInActualExportedMP4() async throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString,
                                    isDirectory: true)
        try FileManager.default.createDirectory(
            at: temp, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temp) }

        let source = temp.appendingPathComponent("black.mov")
        try await makeBlackVideo(at: source)
        var title = TextOverlayClip()
        title.text = "VISIBLE"
        title.fontSize = 68
        title.colorHex = "FFFFFF"
        title.useBackground = false
        title.start = 0
        title.duration = 1.5
        title.depthMode = .front

        let output = temp.appendingPathComponent(
            "title-visible.mp4"
        )
        try await exportWithTitle(
            source: source, output: output,
            title: title
        )
        let result = AVAssetImageGenerator(
            asset: AVURLAsset(url: output)
        )
        result.appliesPreferredTrackTransform = true
        let bitmap = try result.copyCGImage(
            at: CMTime(seconds: 0.65,
                       preferredTimescale: 600),
            actualTime: nil
        )
        XCTAssertGreaterThan(
            brightPixelCount(bitmap), 500,
            "MP4 rendered but title content is completely missing"
        )
    }

    private func makeBlackVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(
            outputURL: url, fileType: .mov
        )
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(canvas.width),
                AVVideoHeightKey: Int(canvas.height)
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String:
                    Int(canvas.width),
                kCVPixelBufferHeightKey as String:
                    Int(canvas.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool
        else { throw NSError(
            domain: "TextSmoke", code: 1
        ) }
        for index in 0..<45 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(
                    nanoseconds: 5_000_000
                )
            }
            var next: CVPixelBuffer?
            let code = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault, pool, &next
            )
            guard code == kCVReturnSuccess,
                  let next else {
                throw NSError(domain: "TextSmoke",
                              code: 2)
            }
            CVPixelBufferLockBaseAddress(next, [])
            if let ptr = CVPixelBufferGetBaseAddress(next) {
                memset(ptr, 0,
                       CVPixelBufferGetDataSize(next))
            }
            CVPixelBufferUnlockBaseAddress(next, [])
            let ok = adaptor.append(
                next, withPresentationTime: CMTime(
                    value: Int64(index), timescale: 30
                )
            )
            XCTAssertTrue(ok)
        }
        input.markAsFinished()
        await withCheckedContinuation {
            (finish: CheckedContinuation<Void, Never>) in
            writer.finishWriting { finish.resume() }
        }
        XCTAssertEqual(writer.status, .completed)
    }

    private func exportWithTitle(
        source: URL, output: URL,
        title: TextOverlayClip
    ) async throws {
        let asset = AVURLAsset(url: source)
        guard let sourceTrack = try await asset.loadTracks(
            withMediaType: .video
        ).first else {
            throw NSError(domain: "TextSmoke", code: 3)
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "TextSmoke", code: 4)
        }
        let length = CMTime(seconds: 1.5,
                            preferredTimescale: 600)
        try track.insertTimeRange(
            CMTimeRange(start: .zero, duration: length),
            of: sourceTrack, at: .zero
        )
        let videoMix = AVMutableVideoComposition()
        videoMix.renderSize = canvas
        videoMix.frameDuration = CMTime(
            value: 1, timescale: 30
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero, duration: length
        )
        instruction.layerInstructions = [
            AVMutableVideoCompositionLayerInstruction(
                assetTrack: track
            )
        ]
        videoMix.instructions = [instruction]
        SubtitleOverlay.attach(
            to: videoMix, size: canvas,
            cues: [], appearance: SubtitleAppearance(),
            imageOverlays: [],
            textOverlays: [title],
            positionX: 0.5, positionY: 0.5,
            vfxPresets: [], vfxIntensity: 0,
            duration: 1.5,
            effectBounds: CGRect(
                origin: .zero, size: canvas
            ), vfxStartTime: 0, vfxEndTime: 1.5
        )
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "TextSmoke", code: 5)
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoMix
        await withCheckedContinuation {
            (finish: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously {
                finish.resume()
            }
        }
        XCTAssertEqual(
            exporter.status, .completed,
            exporter.error?.localizedDescription ?? ""
        )
        if exporter.status != .completed {
            throw NSError(domain: "TextSmoke", code: 6,
                          userInfo: [NSLocalizedDescriptionKey:
                           exporter.error?.localizedDescription ??
                           "MP4 export failed"])
        }
    }
}
