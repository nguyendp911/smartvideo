import Foundation
import XCTest
@testable import SmartVideo

@MainActor
final class HookAndAutoEnhanceTests: XCTestCase {
    func testAutoEnhanceIsOffForLegacyClips() throws {
        let clip = TimelineClip(
            kind: .video, fileURL: URL(fileURLWithPath: "/tmp/clip.mp4"),
            duration: 10, originalDuration: 10
        )
        let encoded = try JSONEncoder().encode(clip)
        let restored = try JSONDecoder().decode(TimelineClip.self, from: encoded)
        XCTAssertFalse(restored.autoEnhance.enabled)
        XCTAssertEqual(restored.autoEnhance, .off)
    }

    func testAutoEnhanceRoundTripAndTuningClamps() throws {
        let selected = AutoEnhanceSettings.tuned(
            averageLuma: 0.05, lumaDeviation: 0.1, strength: 1.0)
        XCTAssertTrue(selected.enabled)
        XCTAssertLessThanOrEqual(selected.exposureEV, 0.55)
        XCTAssertGreaterThan(selected.sharpness, 0)
        let restored = try JSONDecoder().decode(
            AutoEnhanceSettings.self,
            from: JSONEncoder().encode(selected)
        )
        XCTAssertEqual(restored, selected)
    }

    func testHookPrependsExactlyThreeSecondsAndShiftsTimedSubtitles() {
        let model = EditorViewModel()
        let clip = TimelineClip(
            kind: .video, fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            duration: 15, originalDuration: 15
        )
        model.clips = [clip]
        model.subtitles = [SubtitleCue(
            start: 1, end: 2, text: "Lời gốc",
            words: [SubtitleWord(start: 1.2, end: 1.6, text: "Lời")]
        )]
        let chosen = Hook3sSuggestion(
            start: 6, duration: 3, score: 0.9,
            reason: "Chuyển động")
        model.hook3sSourceClipID = clip.id
        model.hook3sSuggestions = [chosen]
        let newID = model.insertHook3s(
            clipID: clip.id, suggestion: chosen, title: "Hook hấp dẫn"
        )
        XCTAssertNotNil(newID)
        XCTAssertEqual(model.clips.count, 2)
        XCTAssertEqual(model.clips[0].duration, 3, accuracy: 0.001)
        XCTAssertEqual(model.clips[0].startTime, 6, accuracy: 0.001)
        XCTAssertEqual(model.clips[1].id, clip.id)
        XCTAssertEqual(model.subtitles[0].start, 4, accuracy: 0.001)
        XCTAssertEqual(model.subtitles[0].words[0].start, 4.2, accuracy: 0.001)
        XCTAssertEqual(model.textOverlays[0].duration, 3)
        model.undoHook3s()
        XCTAssertEqual(model.clips.count, 1)
        XCTAssertEqual(model.subtitles[0].start, 1, accuracy: 0.001)
        XCTAssertTrue(model.textOverlays.isEmpty)
    }
}
