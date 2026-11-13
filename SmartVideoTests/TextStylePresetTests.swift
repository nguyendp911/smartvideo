import XCTest
import UIKit
@testable import SmartVideo

@MainActor
final class TextStylePresetTests: XCTestCase {
    func testEveryStyleProducesVisibleTextPixels() throws {
        XCTAssertGreaterThanOrEqual(TextTitlePreset.allCases.count, 16)
        for preset in TextTitlePreset.allCases {
            var title = TextOverlayClip()
            title.text = "ViePN 2026"
            preset.apply(to: &title)
            XCTAssertGreaterThan(title.fontSize, 0, preset.rawValue)
            XCTAssertGreaterThan(title.opacity, 0, preset.rawValue)
            // Media-fill presets have a color fallback when media is missing.
            guard let bitmap = TextMaskMedia.rasterizedGlyph(
                for: title, size: CGSize(width: 480, height: 180)
            ) else {
                XCTFail("No glyph bitmap for \(preset.rawValue)")
                continue
            }
            let width = bitmap.width, height = bitmap.height
            let bpr = width * 4
            var pixels = [UInt8](repeating: 0, count: bpr * height)
            let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: bpr,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(bitmap, in: CGRect(
                    x: 0, y: 0, width: width, height: height
                ))
                return true
            }
            XCTAssertTrue(ok)
            let visible = stride(from: 3, to: pixels.count, by: 4)
                .reduce(0) { $0 + (pixels[$1] > 20 ? 1 : 0) }
            XCTAssertGreaterThan(visible, 100, preset.rawValue)
        }
    }

    func testNeonAndMetalPresetsUseExportSupportedControls() {
        for preset in [TextTitlePreset.neonBlue, .neonPink, .fire, .ice,
                       .cyberpunk, .chrome, .royalGold, .saleFlash] {
            var text = TextOverlayClip()
            preset.apply(to: &text)
            XCTAssertEqual(text.fillMode, .gradient)
            XCTAssertGreaterThan(text.strokeWidth, 0)
            XCTAssertTrue(text.glowRadius > 0 || text.fauxDepth > 0)
            XCTAssertEqual(text.depthMode, .front)
        }
    }
}
