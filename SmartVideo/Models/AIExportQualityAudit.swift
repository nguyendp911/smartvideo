import Foundation

struct AIExportFinding: Identifiable, Equatable {
    enum Level: String {
        case critical = "Cần sửa"
        case warning = "Cần kiểm tra"
        case info = "Thông tin"
    }
    let id: String
    let level: Level
    let message: String
}

/// Deterministic pre-export checks. These inspect project settings rather
/// than promising that a rendered file passes perceptual QA.
enum AIExportQualityAudit {
    static func inspect(
        clips: [TimelineClip], subtitles: [SubtitleCue],
        voiceURL: URL?, voiceDuration: Double,
        metadata: ExportMetadata, attachMetadata: Bool,
        totalDuration: Double
    ) -> [AIExportFinding] {
        var findings: [AIExportFinding] = []
        func add(_ id: String, _ level: AIExportFinding.Level, _ message: String) {
            findings.append(AIExportFinding(id: id, level: level, message: message))
        }
        if clips.isEmpty {
            add("no-video", .critical, "Chưa có clip để xuất.")
        }
        if !totalDuration.isFinite || totalDuration <= 0 {
            add("duration", .critical, "Thời lượng dự án không hợp lệ.")
        }
        let ordered = subtitles.sorted { $0.start < $1.start }
        for (index, cue) in ordered.enumerated() {
            if !cue.start.isFinite || !cue.end.isFinite ||
                cue.end <= cue.start || cue.start < 0 ||
                cue.end > totalDuration + 0.1 {
                add("caption-time-\(index)", .critical,
                    "Phụ đề #\(index + 1) có mốc thời gian không hợp lệ.")
            }
            if cue.text.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty {
                add("caption-empty-\(index)", .warning,
                    "Phụ đề #\(index + 1) đang trống.")
            }
            if index > 0 && cue.start < ordered[index - 1].end - 0.2 {
                add("caption-overlap-\(index)", .warning,
                    "Phụ đề #\(index) và #\(index + 1) bị chồng thời gian.")
            }
            if AIRevoiceTimingGuide.needsReview(cue) {
                add("caption-fast-\(index)", .warning,
                    "Phụ đề #\(index + 1) có thể quá dài cho thời gian hiển thị.")
            }
        }
        if voiceURL != nil && voiceDuration > totalDuration + 0.3 {
            add("voice-too-long", .warning,
                "Giọng thuyết minh dài hơn dự án; phần cuối có thể bị cắt.")
        }
        if voiceURL != nil && clips.contains(where: {
            $0.kind == .video && !$0.sourceAudioMuted &&
                $0.sourceAudioVolume > 0.1
        }) {
            add("two-voices", .warning,
                "Video còn âm thanh gốc; kiểm tra tiếng nói chồng với giọng mới.")
        }
        if attachMetadata {
            if metadata.title.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty {
                add("title-empty", .warning, "Metadata chưa có tiêu đề.")
            }
            if metadata.description.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty {
                add("description-empty", .warning, "Metadata chưa có mô tả.")
            }
        }
        if findings.isEmpty {
            add("ready", .info,
                "Không phát hiện lỗi cấu hình phổ biến. Vẫn cần nghe và xem MP4 đã xuất.")
        }
        return findings
    }
}
