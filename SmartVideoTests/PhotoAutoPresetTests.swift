import Foundation
import XCTest
@testable import SmartVideo

@MainActor
final class PhotoAutoPresetTests: XCTestCase {
    private func photo(_ name: String) -> TimelineClip {
        TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/" + name + ".jpg"),
            duration: 3, originalDuration: 3
        )
    }

    func testBatchReviewAppliesOnlySelectedAndPreservesExistingLooks()
        throws {
        let editor = EditorViewModel()
        let first = photo("beach")
        var second = photo("portrait")
        second.photoPreset = PhotoPresetLibrary.find("korean_soft")
        let third = photo("sunset")
        let movie = TimelineClip(
            kind: .video,
            fileURL: URL(fileURLWithPath: "/tmp/movie.mp4"),
            duration: 8, originalDuration: 8
        )
        editor.clips = [first, second, third, movie]
        editor.photoAutoPresetPlan = [
            PhotoAutoPresetProposal(
                clipID: first.id, fileURL: first.fileURL,
                filename: "beach", presetID: "beach",
                reason: "Biển", isSelected: true),
            PhotoAutoPresetProposal(
                clipID: second.id, fileURL: second.fileURL,
                filename: "portrait", presetID: "natural_skin",
                reason: "Chân dung", isSelected: true),
            PhotoAutoPresetProposal(
                clipID: third.id, fileURL: third.fileURL,
                filename: "sunset", presetID: "sunset",
                reason: "Hoàng hôn", isSelected: false)
        ]
        editor.applyPhotoAutoPresetPlan(
            intensity: 0.7, protectExisting: true
        )
        XCTAssertEqual(editor.clips[0].photoPreset?.id, "beach")
        XCTAssertEqual(editor.clips[1].photoPreset?.id, "korean_soft")
        XCTAssertNil(editor.clips[2].photoPreset)
        XCTAssertNil(editor.clips[3].photoPreset)
        XCTAssertEqual(editor.clips[0].photoPresetIntensity,
                       0.7, accuracy: 0.001)
        XCTAssertTrue(editor.photoAutoPresetPlan.isEmpty)
        editor.undoEdit()
        XCTAssertNil(editor.clips[0].photoPreset)
        XCTAssertEqual(editor.clips[1].photoPreset?.id, "korean_soft")
    }

    func testBatchReviewRejectsStaleSourceAndAllowsManualOverride() {
        let editor = EditorViewModel()
        let p = photo("original")
        editor.clips = [p]
        editor.photoAutoPresetPlan = [
            PhotoAutoPresetProposal(
                clipID: p.id,
                fileURL: URL(fileURLWithPath: "/tmp/replaced.jpg"),
                filename: "replaced",
                presetID: "beach",
                reason: "Biển")
        ]
        editor.setPhotoAutoPreset(clipID: p.id, presetID: "sunset")
        XCTAssertEqual(editor.photoAutoPresetPlan[0].presetID, "sunset")
        editor.setPhotoAutoPresetSelected(
            clipID: p.id, selected: true)
        editor.applyPhotoAutoPresetPlan(
            intensity: 0.9, protectExisting: false
        )
        XCTAssertNil(editor.clips[0].photoPreset)
        XCTAssertFalse(editor.photoAutoPresetStatus.isEmpty)
    }
}
