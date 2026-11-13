import XCTest
import Foundation
@testable import SmartVideo

@MainActor
final class AIDirectorPipelineTests: XCTestCase {
    func testGeminiPCMIsWrappedInValidWAVHeader() throws {
        let pcm = Data(repeating: 0x33, count: 4800)
        let wav = PCMToWAV.encode(pcm: pcm)
        XCTAssertEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")
        XCTAssertEqual(wav[44], 0x33)
    }

    func testExportAuditFindsCaptionTimingAndDuplicatedVoices() {
        let clip = TimelineClip(kind: .video,
                                fileURL: URL(fileURLWithPath: "/tmp/demo.mp4"),
                                duration: 5, originalDuration: 5)
        let cues = [
            SubtitleCue(start: 0, end: 1.0, text: "Câu thử nghiệm thứ nhất"),
            SubtitleCue(start: 0.4, end: 2.0, text: "Câu thử nghiệm thứ hai")
        ]
        var metadata = ExportMetadata()
        metadata.title = ""
        let findings = AIExportQualityAudit.inspect(
            clips: [clip], subtitles: cues,
            voiceURL: URL(fileURLWithPath: "/tmp/tts.wav"),
            voiceDuration: 7,
            metadata: metadata, attachMetadata: true, totalDuration: 5
        )
        let ids = Set(findings.map(\.id))
        XCTAssertTrue(ids.contains("caption-overlap-1"))
        XCTAssertTrue(ids.contains("voice-too-long"))
        XCTAssertTrue(ids.contains("two-voices"))
        XCTAssertTrue(ids.contains("title-empty"))
    }

    func testExportAuditDoesNotClaimVisualQAForEmptyWarnings() {
        var metadata = ExportMetadata()
        metadata.title = "Example"
        metadata.description = "Example description"
        let clip = TimelineClip(kind: .video,
                                fileURL: URL(fileURLWithPath: "/tmp/demo.mp4"),
                                duration: 5, originalDuration: 5)
        let findings = AIExportQualityAudit.inspect(
            clips: [clip], subtitles: [],
            voiceURL: nil, voiceDuration: 0,
            metadata: metadata, attachMetadata: true, totalDuration: 5
        )
        XCTAssertEqual(findings.map(\.id), ["ready"])
    }
}
