import SwiftUI
import PhotosUI

/// One-tap AI video creation from imported photos/videos.
/// Local Vision works without an API key; Gemini is explicit opt-in.
struct AIAutoVideoCreatorPanel: View {
    @ObservedObject var model: EditorViewModel

    @State private var selectedMedia: [PhotosPickerItem] = []
    @State private var style: AIAutoCreationStyle = .reels
    @State private var useGemini = false
    @State private var saveToPhotos = false
    @State private var isImportingForAI = false
    @State private var showDetailedPlan = false

    private var busy: Bool {
        isImportingForAI || model.isImporting ||
            model.isRunningAIAutoCreator || model.isExporting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Auto Video Creator", systemImage: "sparkles.tv")
                .font(.headline)
            Text("Nhập ảnh/video → AI xem nội dung → chọn cảnh, màu, tăng nét, bố cục và tiêu đề → tự dựng MP4 hoàn chỉnh. Không cần chỉnh từng bước.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Loại video", selection: $style) {
                ForEach(AIAutoCreationStyle.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            Toggle("Nhờ Gemini phân tích ngữ cảnh hình ảnh",
                   isOn: $useGemini)
                .font(.caption)
            if useGemini {
                Text("Chỉ khi bật tùy chọn này, ảnh mẫu và khung hình thu nhỏ sẽ gửi đến API Gemini của Google để tạo tiêu đề và chọn tone màu. Không gửi video gốc hoặc âm thanh. Cần lưu API key ở phần Gemini.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Chế độ offline: Apple Vision nhận diện hình ảnh, điểm nổi bật và bộ lọc. Không tải media lên máy chủ.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Toggle("Tự lưu MP4 vào ứng dụng Ảnh sau khi xuất",
                   isOn: $saveToPhotos)
                .font(.caption)

            PhotosPicker(
                selection: $selectedMedia,
                maxSelectionCount: 12,
                matching: .any(of: [.images, .videos])
            ) {
                Label("Nhập ảnh/video và tự tạo MP4",
                      systemImage: "photo.badge.plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 47)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(busy)

            if !model.clips.isEmpty {
                Button {
                    model.startAIAutoCreator(
                        style: style,
                        useGemini: useGemini,
                        automaticallySaveToPhotos: saveToPhotos
                    )
                } label: {
                    Label("Tự dựng từ \(model.clips.count) media trên timeline",
                          systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .disabled(busy || model.clips.count > 12)
            }

            if busy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(isImportingForAI ? "Đang nhập ảnh/video…" :
                         "AI đang phân tích hoặc xuất MP4 — giữ ứng dụng mở")
                        .font(.caption)
                }
            }
            if !model.aiAutoCreatorStatus.isEmpty {
                Text(model.aiAutoCreatorStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let plan = model.aiAutoCreatorPlan {
                DisclosureGroup("Bản dựng AI đã chọn",
                                isExpanded: $showDetailedPlan) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.title)
                            .font(.caption.bold())
                        Text(plan.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Nguồn phân tích: " +
                             (plan.usedGemini ? "Gemini + Apple Vision" :
                              "Apple Vision offline"))
                            .font(.caption2)
                        ForEach(plan.decisions) { decision in
                            HStack(alignment: .top, spacing: 7) {
                                Image(systemName:
                                    decision.kind == .image ? "photo" : "video")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(decision.sourceURL.lastPathComponent)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                    Text(decision.description)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(String(
                                        format: "%.1fs · %@",
                                        decision.duration,
                                        decision.photoPresetID ?? "Video highlight"
                                    ))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .font(.subheadline.bold())
            }

            if let output = model.exportedURL,
               !model.isRunningAIAutoCreator {
                ShareLink(item: output) {
                    Label("Chia sẻ video MP4 đã hoàn thành",
                          systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            Text("Giữ nguyên ảnh/video gốc và timeline đang chỉnh. Không tự thêm nhạc có bản quyền, không tự nhận diện lời thoại từ khung hình. Bản dựng tối đa 12 media mỗi lần.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(Color.cyan.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: selectedMedia) { selections in
            guard !selections.isEmpty, !busy else { return }
            let newItems = selections
            let selectedStyle = style
            let selectedGemini = useGemini
            let selectedSave = saveToPhotos
            isImportingForAI = true
            Task {
                let existing = Set(model.clips.map(\.id))
                await model.importSelections(newItems)
                let newIDs = model.clips.filter {
                    !existing.contains($0.id)
                }.map(\.id)
                selectedMedia = []
                isImportingForAI = false
                if !newIDs.isEmpty {
                    model.startAIAutoCreator(
                        clipIDs: newIDs,
                        style: selectedStyle,
                        useGemini: selectedGemini,
                        automaticallySaveToPhotos: selectedSave
                    )
                }
            }
        }
    }
}
