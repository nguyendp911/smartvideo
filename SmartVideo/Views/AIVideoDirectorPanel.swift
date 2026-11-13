import SwiftUI

/// Review-first video intelligence controls. AI suggestions are never
/// applied to timeline, captions, metadata or audio without an explicit tap.
struct AIVideoDirectorPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @State private var showScenes = true

    private var selectedClip: TimelineClip? {
        model.clips.first { $0.id == selectedClipID && $0.kind == .video }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Video Director • Hiểu cảnh quay", systemImage: "eye")
                .font(.headline)
            Text("Vision đọc chữ trong khung hình; Gemini phân tích tối đa 8 khung hình được lấy mẫu. Xem xét kết quả vì các khoảnh khắc giữa khung hình có thể bị bỏ sót.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let selectedClip {
                Text("Clip: " + selectedClip.filename)
                    .font(.caption.bold())
                    .lineLimit(1)
            } else {
                Text("Chọn clip video trên timeline để bắt đầu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Yêu cầu: ví dụ thuyết minh giọng nữ, thiên nhiên…",
                      text: $model.aiVisualInstructions, axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)
            Button {
                model.analyzeSelectedVideoWithGemini(
                    clipID: selectedClipID,
                    apiKey: GeminiAPIKeyStore.load()
                )
            } label: {
                Label(model.isAnalyzingVisualScenes ?
                      "AI đang xem các cảnh…" :
                      "Gemini phân tích video & chữ trong ảnh",
                      systemImage: "sparkles.rectangle.stack")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedClip == nil ||
                      model.isAnalyzingVisualScenes ||
                      model.aiGeminiModels.isEmpty)
            if model.isAnalyzingVisualScenes { ProgressView() }
            if !model.aiVisualStatus.isEmpty {
                Text(model.aiVisualStatus)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let report = model.aiVisualReport,
               model.aiVisualClipID == selectedClipID {
                Divider()
                Text(report.summary)
                    .font(.caption)
                if !report.detectedScreenText.isEmpty {
                    DisclosureGroup("Chữ OCR phát hiện trong khung hình") {
                        Text(report.detectedScreenText.joined(separator: " · "))
                            .font(.caption2)
                            .textSelection(.enabled)
                    }
                    .font(.caption.bold())
                }
                DisclosureGroup("Kịch bản theo từng cảnh",
                                isExpanded: $showScenes) {
                    ForEach(report.scenes) { scene in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "Cảnh %.1f–%.1fs",
                                        scene.start, scene.end))
                                .font(.caption.bold())
                            Text(scene.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(scene.narration)
                                .font(.caption)
                            if !scene.suggestedTitle.isEmpty {
                                Text("Gợi ý: " + scene.suggestedTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(7)
                        .background(Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Button {
                    model.applyDirectorSceneNarration()
                } label: {
                    Label("Đưa lời theo cảnh vào phụ đề",
                          systemImage: "captions.bubble")
                }
                .buttonStyle(.bordered)
                Text("Thao tác này thay phụ đề trong phạm vi clip được phân tích. Lời gốc có thể phục hồi qua lịch sử chỉnh sửa.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}
