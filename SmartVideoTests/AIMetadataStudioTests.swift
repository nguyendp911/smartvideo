import XCTest
import AVFoundation
@testable import SmartVideo

@MainActor
final class AIMetadataStudioTests: XCTestCase {
    func testAIApplicationDoesNotClaimCopyrightOrCreator() throws {
        var before = ExportMetadata()
        before.title = "Old video"
        before.author = "Real author"
        before.copyright = "© Owner"
        before.year = "2026"

        let generated = try AIMetadataDraft(
            title: "Cảnh sắc bình yên",
            description: "Khám phá vẻ đẹp của khu vườn.",
            keywords: ["khu vườn", "thiên nhiên"],
            genre: "Thiên nhiên",
            comment: "Giới thiệu không gian xanh.",
            hashtags: ["#thiennhien", "#vuonxanh"]
        ).validated()
        let after = generated.applying(to: before)
        XCTAssertEqual(after.title, "Cảnh sắc bình yên")
        XCTAssertEqual(after.keywords, "khu vườn, thiên nhiên")
        XCTAssertEqual(after.author, "Real author")
        XCTAssertEqual(after.copyright, "© Owner")
        XCTAssertEqual(after.year, "2026")
        XCTAssertGreaterThan(after.items().count, 0)
        XCTAssertTrue(generated.socialCaption.contains("#thiennhien"))
    }

    func testEmptyMetadataIsRejected() {
        let empty = AIMetadataDraft(
            title: " ", description: "",
            keywords: [], genre: "", comment: "", hashtags: [])
        XCTAssertThrowsError(try empty.validated())
    }

    func testMetadataValidationRemovesDuplicateTagsAndLimitsLength() throws {
        let raw = AIMetadataDraft(
            title: String(repeating: "A", count: 250),
            description: "A sample",
            keywords: ["music", "music", "video"],
            genre: "Short film",
            comment: "Comment",
            hashtags: ["#music", "music", "travel video"]
        )
        let checked = try raw.validated()
        XCTAssertEqual(checked.title.count, 150)
        XCTAssertEqual(checked.keywords.count, 2)
        XCTAssertEqual(checked.hashtags.count, 2)
        XCTAssertTrue(checked.hashtags.contains("#travelvideo"))
    }
}
