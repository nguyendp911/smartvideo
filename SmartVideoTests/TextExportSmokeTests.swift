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

    func testMockupTextureAndRealCoreImageBlendPixels() throws {
        XCTAssertEqual(MockupAssetLibrary.all.count, 42)
        let rect = CGRect(
            x: 0, y: 0, width: 320, height: 480
        )
        let black = CIImage(color: .black).cropped(
            to: rect
        )
        let white = CIImage(color: .white).cropped(
            to: rect
        )
        let context = CIContext()
        guard let flare = MockupAssetLibrary.asset("flare-golden"),
              let shadow = MockupAssetLibrary.asset("window-hard") else {
            XCTFail("Built-in mockup library is missing")
            return
        }
        let flareTexture = MockupOverlayRenderer.texture(
            for: flare
        )
        XCTAssertNotNil(flareTexture.cgImage)
        if let bitmap = flareTexture.cgImage {
            XCTAssertGreaterThan(
                brightPixelCount(bitmap), 100
            )
        }

        var light = MockupAssetLibrary.makeClip(
            flare, at: 0, duration: 2
        )
        light.opacity = 1
        light.blurRadius = 0
        let bright = try MockupOverlayRenderer.apply(
            black, overlays: [light], second: 0.7,
            depth: .front
        )
        guard let lightBitmap = context.createCGImage(
            bright, from: rect
        ) else {
            XCTFail("Could not render light into Core Image frame")
            return
        }
        XCTAssertGreaterThan(
            brightPixelCount(lightBitmap), 100,
            "Flare must appear in actual exported pixel pipeline"
        )

        var dark = MockupAssetLibrary.makeClip(
            shadow, at: 0, duration: 2
        )
        dark.opacity = 1
        dark.blurRadius = 0
        let shaded = try MockupOverlayRenderer.apply(
            white, overlays: [dark], second: 0.7,
            depth: .front
        )
        guard let shadedBitmap = context.createCGImage(
            shaded, from: rect
        ) else {
            XCTFail("Could not render window shadow")
            return
        }
        XCTAssertNotEqual(
            brightPixelCount(shadedBitmap, threshold: 230),
            Int(rect.width * rect.height),
            "Window shadow must darken real pixels"
        )
    }

    func testMockupBehindPersonLeavesForegroundUnchanged()
        throws {
        let rect = CGRect(x: 0, y: 0,
                          width: 320, height: 480)
        let black = CIImage(color: .black).cropped(to: rect)
        let person = CIImage(color: .white).cropped(
            to: CGRect(x: 110, y: 0, width: 100,
                       height: 480)
        )
        let empty = CIImage(color: .black).cropped(to: rect)
        let mask = person.composited(over: empty)
        var light = MockupAssetLibrary.makeClip(
            MockupAssetLibrary.asset("flare-golden")!,
            at: 0, duration: 3
        )
        light.blurRadius = 0
        light.opacity = 1
        light.depthMode = .behindPerson
        let visible = try MockupOverlayRenderer.apply(
            black, overlays: [light], second: 1,
            depth: .behindPerson, personMask: empty
        )
        let occluded = try MockupOverlayRenderer.apply(
            black, overlays: [light], second: 1,
            depth: .behindPerson, personMask: mask
        )
        let context = CIContext()
        guard let visiblePixels = context.createCGImage(
            visible, from: rect
        ), let occludedPixels = context.createCGImage(
            occluded, from: rect
        ) else {
            XCTFail("Could not composite person-depth mockups")
            return
        }
        XCTAssertGreaterThan(
            brightPixelCount(visiblePixels), 100
        )
        XCTAssertLessThan(
            brightPixelCount(occludedPixels),
            brightPixelCount(visiblePixels),
            "Person matte should occlude the light"
        )
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

    func testBehindPersonTextAcrossTrimmedClipsAndActualOcclusion()
        throws {
        let rect = CGRect(
            x: 0, y: 0, width: 320, height: 480
        )
        let background = CIImage(color: .black).cropped(
            to: rect
        )
        // Simulate a person occupying a full-height central stripe.
        // Lettering needs to appear around the person's body, but
        // remain occluded in the area occupied by the subject.
        let clear = CIImage(color: .black).cropped(to: rect)
        let person = CIImage(color: .white).cropped(
            to: CGRect(x: 113, y: 0, width: 94,
                       height: 480)
        )
        let personMask = person.composited(
            over: clear
        )
        var title = TextOverlayClip()
        title.depthMode = .behindPerson
        title.text = "VIEPN SMART"
        title.fontSize = 34
        title.useBackground = false
        title.colorHex = "FFFFFF"
        title.behindVisibilityAssist = true
        title.start = 7.1
        title.duration = 2
        // In the real pipeline source footage has already been
        // rebased from an original timestamp such as 13.5s to 0s.
        let t = TextTitleRenderTime.projectSecond(
            clipStart: 7,
            trimmedCompositionSecond: 0.5,
            playbackSpeed: 2
        )
        XCTAssertEqual(t, 7.25, accuracy: 0.001)
        let rendered = try TextBehindPersonRenderer.apply(
            to: background, items: [title],
            projectTime: t, maskOverride: personMask
        )
        let context = CIContext()
        guard let bitmap = context.createCGImage(
            rendered, from: rect
        ) else {
            XCTFail("Failed to render person mask title")
            return
        }
        XCTAssertGreaterThan(
            brightPixelCount(bitmap), 200,
            "Person occupying center erased every letter"
        )
        // Project time BEFORE the title must remain unchanged.
        let early = try TextBehindPersonRenderer.apply(
            to: background, items: [title],
            projectTime: 6, maskOverride: personMask
        )
        if let earlyBitmap = context.createCGImage(
            early, from: rect
        ) {
            XCTAssertEqual(
                brightPixelCount(earlyBitmap), 0
            )
        }
    }

    func testFrontTitleLayersHaveVisiblePixels() throws {
        let surface = CALayer()
        surface.frame = CGRect(origin: .zero, size: canvas)
        var title = TextOverlayClip()
        title.text = "VISIBLE"
        title.fontSize = 68
        title.colorHex = "FFFFFF"
        title.useBackground = false
        title.start = 0
        title.duration = 1.5
        TextOverlayRenderer.attach(
            [title], to: surface, canvas: canvas,
            duration: 1.5
        )
        XCTAssertEqual(surface.sublayers?.count, 1)
        guard let gate = surface.sublayers?.first,
              let outer = gate.sublayers?.first else {
            XCTFail("Title composition did not create overlay layers")
            return
        }
        // .render(in:) evaluates model layer values rather than animations;
        // make the gate opaque to check the actual unanimated title content.
        gate.opacity = 1
        XCTAssertTrue(outer.sublayers?.contains {
            $0 is CATextLayer
        } ?? false, "Legacy solid text must use CATextLayer")
        let snapshot = UIGraphicsImageRenderer(
            size: canvas
        ).image { context in
            surface.render(in: context.cgContext)
        }
        guard let bitmap = snapshot.cgImage else {
            XCTFail("Layer tree cannot rasterize text")
            return
        }
        XCTAssertGreaterThan(
            brightPixelCount(bitmap), 500,
            "Plain title pixels disappeared in actual layer tree"
        )

        title.fillMode = .gradient
        let gradientSurface = CALayer()
        gradientSurface.frame = CGRect(
            origin: .zero, size: canvas
        )
        TextOverlayRenderer.attach(
            [title], to: gradientSurface,
            canvas: canvas, duration: 1.5
        )
        guard let gradientGate = gradientSurface.sublayers?.first
        else {
            XCTFail("Gradient text layer is missing")
            return
        }
        gradientGate.opacity = 1
        let gradientImage = UIGraphicsImageRenderer(
            size: canvas
        ).image { context in
            gradientSurface.render(in: context.cgContext)
        }
        if let bitmap = gradientImage.cgImage {
            XCTAssertGreaterThan(
                brightPixelCount(bitmap), 500,
                "Gradient glyph layer is invisible"
            )
        }
    }

    /// Requires a physical device with a supported H.264 encoder. On the
    /// GitHub iOS Simulator, VideoToolbox returned -12900 and terminated
    /// the XCTest runner before the resulting MP4 could be inspected.
    func testFrontTitleIsVisibleInActualExportedMP4() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip(
            "MP4 hardware encoding is unavailable on this Simulator; title layer pixels and Vision/CoreImage depth are tested separately"
        )
        #endif
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
        guard writer.startWriting() else {
            throw NSError(
                domain: "TextSmoke", code: 7,
                userInfo: [NSLocalizedDescriptionKey:
                    writer.error?.localizedDescription ??
                    "AVAssetWriter cannot start on this simulator"]
            )
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool
        else { throw NSError(
            domain: "TextSmoke", code: 1
        ) }
        for index in 0..<45 {
            var attempts = 0
            while !input.isReadyForMoreMediaData {
                attempts += 1
                guard writer.status == .writing,
                      attempts < 2_000 else {
                    throw NSError(
                        domain: "TextSmoke", code: 8,
                        userInfo: [NSLocalizedDescriptionKey:
                            "Video writer did not accept frames within 10 seconds"]
                    )
                }
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
