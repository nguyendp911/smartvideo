import SwiftUI
import UIKit

struct MediaInspectorPanel: View {
    let clip: TimelineClip?
    @State private var inspection: MediaInspection?
    @State private var isInspecting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Media Inspector", systemImage: "waveform.path.ecg")
                .font(.headline)
                .foregroundStyle(.cyan)
            Text("Đọc thông tin file cục bộ bằng AVFoundation. Tệp không được tải lên máy chủ.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let clip {
                HStack {
                    Image(systemName: clip.kind == .video ? "film" : "photo")
                        .foregroundStyle(.cyan)
                    Text(clip.filename)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Task { await runInspection(clip) }
                    } label: {
                        Label(isInspecting ? "Đang đọc…" : "Phân tích",
                              systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInspecting)
                }

                if isInspecting { ProgressView("Đang đọc metadata…") }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let inspection {
                    VStack(alignment: .leading, spacing: 7) {
                        metric("Định dạng", inspection.videoCodec ?? (clip.kind == .image ? "Ảnh tĩnh" : "Không rõ"))
                        metric("Kích thước", "\\(inspection.width.map(String.init) ?? "—") × \\(inspection.height.map(String.init) ?? "—")")
                        metric("Thời lượng", inspection.duration.map { String(format: "%.2f giây", $0) } ?? (clip.kind == .image ? "Ảnh tĩnh" : "Không rõ"))
                        metric("Tốc độ khung hình", inspection.nominalFrameRate.map { String(format: "%.3f FPS", $0) } ?? "Không có metadata")
                        metric("Bitrate video", inspection.videoBitrate.map { String(format: "%.2f Mbps", $0 / 1_000_000) } ?? "Không có metadata")
                        metric("Âm thanh", inspection.hasAudio ? "\\(inspection.audioCodec ?? "Có") · \\(inspection.audioChannels.map(String.init) ?? "?") kênh" : "Không có track")
                        metric("HDR", inspection.isHDR.map { $0 ? "Phát hiện HDR" : "Không phát hiện HDR" } ?? "Không xác định")
                        if let inspectionSize = inspection.fileSize {
                            metric("Dung lượng", ByteCountFormatter.string(fromByteCount: inspectionSize, countStyle: .file))
                        }

                        if !inspection.warnings.isEmpty {
                            Divider()
                            Label("Cần lưu ý", systemImage: "exclamationmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            ForEach(Array(inspection.warnings.enumerated()), id: \.offset) { _, warning in
                                Text("• \\(warning)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ShareLink(item: inspection.report) {
                            Label("Chia sẻ báo cáo kỹ thuật", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                Label("Thêm hoặc chọn một clip trên Timeline để phân tích.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .onChange(of: clip?.id) { _ in
            inspection = nil
            error = nil
        }
    }

    private func metric(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.caption)
    }

    @MainActor
    private func runInspection(_ clip: TimelineClip) async {
        isInspecting = true
        error = nil
        defer { isInspecting = false }
        do {
            inspection = try await MediaInspector.inspect(clip.fileURL)
        } catch {
            self.error = "Không đọc được metadata: \\(error.localizedDescription)"
        }
    }
}
