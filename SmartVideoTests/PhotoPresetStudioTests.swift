import XCTest
import CoreImage
import Foundation
@testable import SmartVideo

@MainActor
final class PhotoPresetStudioTests: XCTestCase {
    func testTwentyDistinctBuiltInPresetsAndTravelCategories() {
        let presets = PhotoPresetLibrary.all
        XCTAssertEqual(presets.count, 20)
        XCTAssertEqual(Set(presets.map(\.id)).count, 20)
        XCTAssertEqual(PhotoPresetLibrary.find("beach")?.name, "Đi biển")
        XCTAssertEqual(PhotoPresetLibrary.find("sunset")?.name, "Hoàng hôn")
        XCTAssertEqual(PhotoPresetLibrary.inCategory(.travel).count, 6)
    }

    func testClipPreservesPhotoPresetAfterSerialization() throws {
        var clip = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/picture.jpg"),
            duration: 3, originalDuration: 3
        )
        clip.photoPreset = PhotoPresetLibrary.find("beach")
        clip.photoPresetIntensity = 0.6
        let encoded = try JSONEncoder().encode(clip)
        let restored = try JSONDecoder().decode(
            TimelineClip.self, from: encoded)
        XCTAssertEqual(restored.photoPreset?.id, "beach")
        XCTAssertEqual(restored.photoPresetIntensity, 0.6, accuracy: 0.001)
    }

    func testLegacyProjectWithoutPhotoKeysRemainsValid() throws {
        let clip = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/picture.jpg"),
            duration: 3, originalDuration: 3
        )
        let serialized = try JSONEncoder().encode(clip)
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: serialized) as? [String: Any])
        json.removeValue(forKey: "photoPreset")
        json.removeValue(forKey: "photoPresetIntensity")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let restored = try JSONDecoder().decode(TimelineClip.self, from: legacy)
        XCTAssertNil(restored.photoPreset)
        XCTAssertEqual(restored.photoPresetIntensity, 0.75, accuracy: 0.001)
    }

    func testBatchApplyOnlyChangesStillPhotos() throws {
        let model = EditorViewModel()
        let image = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            duration: 3, originalDuration: 3
        )
        let movie = TimelineClip(
            kind: .video,
            fileURL: URL(fileURLWithPath: "/tmp/movie.mov"),
            duration: 5, originalDuration: 5
        )
        model.clips = [image, movie, image]
        let preset = try XCTUnwrap(PhotoPresetLibrary.find("sunset"))
        model.applyPhotoPreset(
            preset, to: image.id,
            intensity: 0.65, allPhotos: true)
        XCTAssertEqual(model.clips[0].photoPreset?.id, "sunset")
        XCTAssertEqual(model.clips[2].photoPreset?.id, "sunset")
        XCTAssertNil(model.clips[1].photoPreset)
        XCTAssertEqual(model.clips[0].photoPresetIntensity, 0.65)
    }

    func testPhotoProcessorPreservesBoundsAndZeroStrength() throws {
        let source = CIImage(
            color: CIColor(red: 0.3, green: 0.4, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let preset = try XCTUnwrap(PhotoPresetLibrary.find("beach"))
        let unmodified = PhotoPresetProcessor.apply(
            source, preset: preset, intensity: 0)
        let changed = PhotoPresetProcessor.apply(
            source, preset: preset, intensity: 0.85)
        XCTAssertEqual(unmodified.extent, source.extent)
        XCTAssertEqual(changed.extent, source.extent)
        XCTAssertNotNil(CIContext().createCGImage(
            changed, from: changed.extent))
    }
}
