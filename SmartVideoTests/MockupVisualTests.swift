import XCTest
import CoreImage
import UIKit
@testable import SmartVideo

@MainActor
final class MockupVisualTests: XCTestCase {
    private let rect = CGRect(
        x: 0, y: 0, width: 200, height: 300
    )
    private let context = CIContext()

    private func rgbEnergy(_ frame: CIImage) -> Double {
        guard let bitmap = context.createCGImage(
            frame, from: rect
        ) else { return 0 }
        let width = bitmap.width, height = bitmap.height
        var bytes = [UInt8](
            repeating: 0, count: width * height * 4
        )
        let ok = bytes.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(
                data: ptr.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(
                bitmap, in: CGRect(
                    x: 0, y: 0,
                    width: width, height: height
                )
            )
            return true
        }
        guard ok else { return 0 }
        var energy = 0.0
        for n in stride(from: 0, to: bytes.count, by: 4) {
            energy += Double(bytes[n]) +
                Double(bytes[n + 1]) +
                Double(bytes[n + 2])
        }
        return energy / Double(width * height * 3)
    }

    func testAll42TexturesContainVisibleAlpha() throws {
        for preset in MockupAssetLibrary.all {
            guard let art = MockupProceduralTexture.artwork(
                id: preset.id
            ), let cg = art.cgImage else {
                XCTFail("Missing procedural asset \(preset.id)")
                continue
            }
            XCTAssertEqual(cg.width, 480)
            XCTAssertEqual(cg.height, 720)
            guard let data = cg.dataProvider?.data as Data? else {
                XCTFail("No bitmap bytes for \(preset.id)")
                continue
            }
            XCTAssertGreaterThan(
                data.count, 1000,
                "Texture is empty: \(preset.id)"
            )
        }
    }

    func testSunFlarePaintsActualCoreImagePixels() throws {
        let background = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0)
        ).cropped(to: rect)
        guard let definition = MockupAssetLibrary.find(
            "flare-golden"
        ) else { return XCTFail("No flare preset") }
        let title = definition.makeClip(start: 0, duration: 2)
        let frame = try MockupFrameRenderer.apply(
            to: background, items: [title],
            projectTime: 1
        )
        XCTAssertGreaterThan(
            rgbEnergy(frame), rgbEnergy(background) + 0.5,
            "Flare must affect actual exported CoreImage pixels"
        )
    }

    func testAllBlendModesRenderWithoutDroppingPixels() throws {
        let base = CIImage(
            color: CIColor(red: 0.45, green: 0.45,
                           blue: 0.45)
        ).cropped(to: rect)
        var clip = MockupAssetLibrary.find("win-grid")!
            .makeClip(start: 0, duration: 3)
        for blend in MockupBlendMode.allCases {
            clip.blendMode = blend
            let output = try MockupFrameRenderer.apply(
                to: base, items: [clip], projectTime: 1
            )
            XCTAssertTrue(
                output.extent.equalTo(rect),
                "Blend \(blend.rawValue) changed canvas extent"
            )
            XCTAssertGreaterThan(
                rgbEnergy(output), 0,
                "Blend \(blend.rawValue) did not render"
            )
        }
    }

    func testBehindPersonPreservesForegroundAndShowsBackground() throws {
        let base = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0)
        ).cropped(to: rect)
        let none = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0)
        ).cropped(to: rect)
        let full = CIImage(
            color: CIColor(red: 1, green: 1, blue: 1)
        ).cropped(to: rect)
        var item = MockupAssetLibrary.find("flare-golden")!
            .makeClip(start: 0, duration: 3)
        item.depthMode = .behindPerson
        let hidden = try MockupFrameRenderer.apply(
            to: base, items: [item],
            projectTime: 1, cachedPersonMask: full
        )
        let visible = try MockupFrameRenderer.apply(
            to: base, items: [item],
            projectTime: 1, cachedPersonMask: none
        )
        XCTAssertLessThan(
            abs(rgbEnergy(hidden) - rgbEnergy(base)), 1,
            "Person foreground must completely occlude mockup"
        )
        XCTAssertGreaterThan(
            rgbEnergy(visible), rgbEnergy(hidden) + 0.5,
            "Mockup must be visible outside the person"
        )
    }

    func testAnimatedEffectChangesPositionAcrossFrames() throws {
        let source = CIImage(
            color: CIColor(red: 0.08, green: 0.08,
                           blue: 0.08)
        ).cropped(to: rect)
        let item = MockupAssetLibrary.find("motion-sweep")!
            .makeClip(start: 0, duration: 4)
        let first = MockupAnimationSampler.sample(
            item, atProjectTime: 0.3
        )
        let later = MockupAnimationSampler.sample(
            item, atProjectTime: 1.3
        )
        XCTAssertNotEqual(first.x, later.x)
        let output = try MockupFrameRenderer.apply(
            to: source, items: [item],
            projectTime: 0.6
        )
        XCTAssertGreaterThan(rgbEnergy(output), 0)
    }
}
