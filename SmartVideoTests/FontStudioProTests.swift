import XCTest
import UIKit
@testable import SmartVideo

@MainActor
final class FontStudioProTests: XCTestCase {
    func testOldProjectDefaultsAndRoundTrip() throws {
        var title = TextOverlayClip()
        title.text = "Tiếng Việt: Trường học, Đắk Lắk"
        title.fontName = "AvenirNext-Bold"
        title.letterSpacing = 3
        title.curveAmount = 24
        title.gradientMidHex = "F0AA42"
        title.typewriterEnabled = true
        title.typewriterDuration = 2.4
        let restored = try JSONDecoder().decode(
            TextOverlayClip.self, from: JSONEncoder().encode(title))
        XCTAssertEqual(restored, title)
        let old = try JSONDecoder().decode(
            TextOverlayClip.self,
            from: Data("{\"text\":\"Xin chào\"}".utf8)
        )
        XCTAssertEqual(old.fontName, "")
        XCTAssertEqual(old.letterSpacing, 0)
        XCTAssertEqual(old.curveAmount, 0)
        XCTAssertFalse(old.typewriterEnabled)
        XCTAssertEqual(old.gradientMidHex, "")
    }

    func testVietnameseCurvedTextHasVisibleAlpha() throws {
        let title = TextOverlayClip()
        let bitmap = TextMaskMedia.glyphMask(
            text: "Trường học — Tiếng Việt ắ ệ ữ",
            size: CGSize(width: 700, height: 240),
            fontSize: 55, fontName: "AvenirNext-Bold",
            tracking: 1.5, curve: 35
        )
        XCTAssertNotNil(bitmap)
        guard let cg = bitmap else { return }
        let width = cg.width, height = cg.height
        let bpr = width * 4
        var pixels = [UInt8](repeating: 0, count: bpr * height)
        let created = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bpr,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(created)
        XCTAssertGreaterThan(
            stride(from: 3, to: pixels.count, by: 4)
                .reduce(0) { $0 + (pixels[$1] > 20 ? 1 : 0) }, 300
        )
    }
}
