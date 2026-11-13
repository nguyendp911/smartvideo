import XCTest
@testable import SmartVideo

@MainActor
final class AIRevoiceQualityTests: XCTestCase {
    func testTimingWarningsRespectCaptionDuration() {
        let short = SubtitleCue(start: 0, end: 5,
            text: "Xin chào, đây là một đoạn ngắn.")
        let rushed = SubtitleCue(start: 5, end: 5.6,
            text: "Hôm nay chúng ta cùng khám phá một chủ đề rất thú vị và hấp dẫn.")
        XCTAssertFalse(AIRevoiceTimingGuide.needsReview(short))
        XCTAssertTrue(AIRevoiceTimingGuide.needsReview(rushed))
        XCTAssertGreaterThan(
            AIRevoiceTimingGuide.overrunSeconds(
                text: rushed.text, start: rushed.start, end: rushed.end), 0)
    }

    func testRewriteValidationKeepsOriginalTimeAndRejectsIncompleteOutput() throws {
        let input = [
            AIRevoiceSegment(id: 0, start: 1, end: 2.5, text: "Xin chào"),
            AIRevoiceSegment(id: 1, start: 3, end: 5, text: "Cảm ơn")
        ]
        let result = try GeminiRevoiceClient.validate([
            AIRevoiceSegment(id: 1, start: 999, end: 1000, text: "Xin cảm ơn"),
            AIRevoiceSegment(id: 0, start: 999, end: 1000, text: "Chào bạn")
        ], input: input)
        XCTAssertEqual(result.map(\.start), [1, 3])
        XCTAssertEqual(result.map(\.end), [2.5, 5])
        XCTAssertEqual(result.map(\.text), ["Chào bạn", "Xin cảm ơn"])
        XCTAssertThrowsError(try GeminiRevoiceClient.validate([
            AIRevoiceSegment(id: 0, start: 1, end: 2, text: "Chào")
        ], input: input))
    }

    func testTranscriptPreparationRemovesBlankCuesWithoutShiftingTimes() throws {
        let cues = [
            SubtitleCue(start: 0, end: 1, text: " "),
            SubtitleCue(start: 3, end: 5, text: "Có lời nói")
        ]
        let prepared = try GeminiRevoiceClient.prepare(cues)
        XCTAssertEqual(prepared.count, 1)
        XCTAssertEqual(prepared.first?.id, 0)
        XCTAssertEqual(prepared.first?.start, 3)
    }
}
