import Foundation
import XCTest
@testable import SmartVideo

@MainActor
final class AIAutoVideoCreatorTests: XCTestCase {
    func testMaterializedEditsKeepOriginalsAndChooseColorAndHighlights() throws {
        let image = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/beach.jpg"),
            duration: 3, originalDuration: 3
        )
        let video = TimelineClip(
            kind: .video,
            fileURL: URL(fileURLWithPath: "/tmp/long-video.mov"),
            duration: 20, startTime: 5, originalDuration: 40
        )
        let plan = AIAutoCreationPlan(
            sourceIDs: [image.id, video.id],
            decisions: [
                AIAutoCreationDecision(
                    id: image.id, sourceURL: image.fileURL,
                    kind: .image, photoPresetID: "beach",
                    autoEnhance: .off,
                    offsetSeconds: 0, duration: 2.5,
                    description: "Biển"),
                AIAutoCreationDecision(
                    id: video.id, sourceURL: video.fileURL,
                    kind: .video, photoPresetID: nil,
                    autoEnhance: AutoEnhanceSettings.tuned(
                        averageLuma: 0.27, lumaDeviation: 0.12,
                        strength: 0.6
                    ),
                    offsetSeconds: 7, duration: 5,
                    description: "Chuyển động")
            ],
            style: .reels,
            title: "Khoảnh khắc ở biển",
            description: "Video du lịch."
        )
        let materialized = try AIAutoCreationAnalyzer.materialize(
            plan: plan, sourceClips: [image, video]
        )
        XCTAssertEqual(materialized.count, 2)
        XCTAssertEqual(materialized[0].photoPreset?.id, "beach")
        XCTAssertEqual(materialized[0].duration, 2.5, accuracy: 0.001)
        XCTAssertEqual(materialized[1].startTime, 12, accuracy: 0.001)
        XCTAssertEqual(materialized[1].duration, 5, accuracy: 0.001)
        XCTAssertTrue(materialized[1].autoEnhance.enabled)
        XCTAssertNil(image.photoPreset)
        XCTAssertEqual(video.startTime, 5, accuracy: 0.001)
        XCTAssertNotEqual(materialized[0].id, image.id)
    }

    func testRejectsStaleMediaBeforeRender() {
        let image = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/image.jpg"),
            duration: 3, originalDuration: 3
        )
        let other = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/other.jpg"),
            duration: 3, originalDuration: 3
        )
        let plan = AIAutoCreationPlan(
            sourceIDs: [image.id],
            decisions: [AIAutoCreationDecision(
                id: image.id, sourceURL: image.fileURL,
                kind: .image, photoPresetID: "sunset",
                autoEnhance: .off, offsetSeconds: 0,
                duration: 3, description: "Hoàng hôn")],
            style: .cinematic, title: "Demo",
            description: "Test"
        )
        XCTAssertThrowsError(try AIAutoCreationAnalyzer.materialize(
            plan: plan, sourceClips: [other]))
    }

    func testVideoSegmentsNeverExtendPastSourceMedia() throws {
        let video = TimelineClip(
            kind: .video,
            fileURL: URL(fileURLWithPath: "/tmp/movie.mov"),
            duration: 8, startTime: 3,
            originalDuration: 12
        )
        let plan = AIAutoCreationPlan(
            sourceIDs: [video.id],
            decisions: [AIAutoCreationDecision(
                id: video.id, sourceURL: video.fileURL,
                kind: .video, photoPresetID: nil,
                autoEnhance: .off,
                offsetSeconds: 999,
                duration: 90,
                description: "Scene")],
            style: .travel,
            title: "Short", description: "Video"
        )
        let clip = try XCTUnwrap(
            AIAutoCreationAnalyzer.materialize(
                plan: plan, sourceClips: [video]).first)
        XCTAssertLessThanOrEqual(
            clip.startTime + clip.duration,
            video.originalDuration + 0.0001
        )
        XCTAssertGreaterThan(clip.duration, 0)
    }
}
