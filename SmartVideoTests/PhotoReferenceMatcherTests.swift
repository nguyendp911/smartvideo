import XCTest
import UIKit
import Foundation
@testable import SmartVideo

@MainActor
final class PhotoReferenceMatcherTests: XCTestCase {
    private func png(_ color: UIColor) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 36, height: 36))
            .image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 36, height: 36))
            }
        return try XCTUnwrap(image.pngData())
    }

    func testReferencePhotoCanGenerateConservativeReusableRecipe() async throws {
        let originalData = try png(UIColor(
            red: 0.25, green: 0.25, blue: 0.20, alpha: 1))
        let sampleData = try png(UIColor(
            red: 0.88, green: 0.67, blue: 0.40, alpha: 1))
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoMatcher-" + UUID().uuidString + ".png")
        try originalData.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let preset = try await PhotoReferenceMatcher.createPreset(
            fromReferenceData: sampleData, forSourceURL: file,
            name: "Ảnh mẫu hoàng hôn"
        )
        XCTAssertTrue(preset.id.hasPrefix("reference-"))
        XCTAssertGreaterThan(preset.exposureEV, 0)
        XCTAssertGreaterThan(preset.warmth, 0)
        XCTAssertLessThanOrEqual(preset.exposureEV, 0.45)
        XCTAssertLessThanOrEqual(preset.warmth, 0.30)
        let saved = try JSONEncoder().encode(preset)
        let loaded = try JSONDecoder().decode(
            PhotoPreset.self, from: saved)
        XCTAssertEqual(loaded, preset)
    }

    func testReferenceImageSizeLimitFailsBeforeDecoding() async throws {
        let original = try png(.white)
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ColorMatch-" + UUID().uuidString + ".png")
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            _ = try await PhotoReferenceMatcher.createPreset(
                fromReferenceData: Data(repeating: 1, count: 25_000_001),
                forSourceURL: file,
                name: "Too large"
            )
            XCTFail("Should reject reference data exceeding 25 MB")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testImportedPresetValuesAreBoundedAndIDsAreUnique() throws {
        var unsafe = try XCTUnwrap(PhotoPresetLibrary.find("sunset"))
        unsafe.exposureEV = 999
        unsafe.contrast = -45
        unsafe.saturation = 400
        unsafe.sharpness = 99
        unsafe.vignette = -20
        let imported = PhotoPresetTransferDocument.sanitized(
            Array(repeating: unsafe, count: 45)
        )
        XCTAssertEqual(imported.count, 40)
        XCTAssertEqual(Set(imported.map(\.id)).count, 40)
        XCTAssertEqual(imported[0].exposureEV, 0.8, accuracy: 0.001)
        XCTAssertEqual(imported[0].contrast, 0.75, accuracy: 0.001)
        XCTAssertEqual(imported[0].saturation, 1.4, accuracy: 0.001)
        XCTAssertEqual(imported[0].sharpness, 0.75, accuracy: 0.001)
        XCTAssertEqual(imported[0].vignette, 0, accuracy: 0.001)
    }

    func testSelectedBatchChangesOnlyChosenPhotosAndCanUndo() throws {
        let model = EditorViewModel()
        let first = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/one.jpg"),
            duration: 3, originalDuration: 3
        )
        let second = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/two.jpg"),
            duration: 3, originalDuration: 3
        )
        let video = TimelineClip(
            kind: .video,
            fileURL: URL(fileURLWithPath: "/tmp/movie.mp4"),
            duration: 5, originalDuration: 5
        )
        model.clips = [first, second, video]
        let preset = try XCTUnwrap(PhotoPresetLibrary.find("sunset"))
        model.applyPhotoPresetToSelection(
            preset, ids: [first.id, video.id], intensity: 0.45
        )
        XCTAssertEqual(model.clips[0].photoPreset?.id, "sunset")
        XCTAssertEqual(model.clips[0].photoPresetIntensity, 0.45)
        XCTAssertNil(model.clips[1].photoPreset)
        XCTAssertNil(model.clips[2].photoPreset)
        model.undoEdit()
        XCTAssertNil(model.clips[0].photoPreset)
    }
}
