import SwiftUI
import UIKit

struct MetadataPanel: View {
    @ObservedObject var model: EditorViewModel
    @State private var geminiKey = ""
    @State private var keyStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Metadata khi xuất MP4", systemImage: "tag")
                .font(.headline)

            aiMetadataStudio

            Toggle("Lọc metadata của tệp nguồn", isOn: $model.stripMetadata)
                .font(.caption)

            Toggle("Gắn metadata do tôi nhập", isOn: $model.addCustomMetadata)
                .font(.caption)
                .tint(.cyan)

            if model.addCustomMetadata {
                Group {
                    field("Tiêu đề", text: $model.metadata.title, hint: "Tên video")
                    field("Tác giả", text: $model.metadata.author, hint: "Người tạo")
                    field("Mô tả", text: $model.metadata.description, hint: "Giới thiệu video")
                    field("Bản quyền", text: $model.metadata.copyright, hint: "© Chủ sở hữu")
                    field("Từ khóa", text: $model.metadata.keywords, hint: "gameplay, cinematic")
                    field("Thể loại", text: $model.metadata.genre, hint: "Ví dụ: Education")
                    field("Ghi chú", text: $model.metadata.comment, hint: "Thông tin bổ sung")
                    field("Năm", text: $model.metadata.year, hint: "2026")
                }
                Button("Điền thông tin ViePN mẫu") {
                    model.metadata.title = "ViePN Smart Video"
                    model.metadata.author = "ViePN"
                    model.metadata.description = "Video được dựng bằng ViePN Smart Video"
                    model.metadata.keywords = "ViePN, video"
                    model.metadata.genre = "Video"
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            Divider()
            DisclosureGroup("Kiểm tra chất lượng trước khi xuất MP4") {
                let findings = AIExportQualityAudit.inspect(
                    clips: model.clips,
                    subtitles: model.subtitles,
                    voiceURL: model.voiceoverURL,
                    voiceDuration: model.voiceoverDuration,
                    metadata: model.metadata,
                    attachMetadata: model.addCustomMetadata,
                    totalDuration: model.totalDuration
                )
                ForEach(findings) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.level == .critical ?
                              "xmark.octagon" :
                              item.level == .warning ?
                              "exclamationmark.triangle" : "checkmark.circle")
                            .foregroundStyle(item.level == .critical ?
                                             .red : item.level == .warning ?
                                             .orange : .green)
                        Text(item.message)
                            .font(.caption)
                    }
                }
                Text("Chỉ kiểm tra dữ liệu dự án. Hãy nghe giọng đọc và xem file xuất thực tế để phát hiện lỗi hình, âm thanh hoặc đồng bộ.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .font(.subheadline.bold())

            Text("Dữ liệu mới được ghi vào container MP4 khi xuất nếu định dạng hỗ trợ; từng ứng dụng có thể không hiển thị tất cả trường. Lọc metadata nguồn không xóa các thông số kỹ thuật như thời lượng, codec hoặc độ phân giải.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func draftText(
        _ keyPath: WritableKeyPath<AIMetadataDraft, String>
    ) -> Binding<String> {
        Binding(
            get: { model.aiMetadataDraft?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var draft = model.aiMetadataDraft else { return }
                draft[keyPath: keyPath] = value
                model.aiMetadataDraft = draft
            }
        )
    }

    private func draftWords(
        _ keyPath: WritableKeyPath<AIMetadataDraft, [String]>
    ) -> Binding<String> {
        Binding(
            get: {
                model.aiMetadataDraft?[keyPath: keyPath]
                    .joined(separator: ", ") ?? ""
            },
            set: { value in
                guard var draft = model.aiMetadataDraft else { return }
                draft[keyPath: keyPath] = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                model.aiMetadataDraft = draft
            }
        )
    }

    private var aiMetadataStudio: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Metadata Studio • Gemini", systemImage: "sparkles")
                .font(.subheadline.bold())
            Text("Tạo mới tiêu đề, mô tả, thể loại, từ khóa và hashtag dựa trên lời thuyết minh/phụ đề. Không tự suy đoán tác giả hay bản quyền.")
                .font(.caption)
                .foregroundStyle(.secondary)

            SecureField("Gemini API key", text: $geminiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button("Lưu key & tìm model") {
                    let clean = geminiKey.trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else {
                        keyStatus = "Cần nhập Gemini API key."
                        return
                    }
                    if GeminiAPIKeyStore.save(clean) {
                        keyStatus = "Đã lưu key vào Keychain."
                        model.discoverGeminiModels(apiKey: clean)
                    } else {
                        keyStatus = "Không lưu được key."
                    }
                }
                .buttonStyle(.bordered)
                Button {
                    model.discoverGeminiModels(apiKey: geminiKey)
                } label: {
                    Label("Làm mới", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(geminiKey.isEmpty || model.isLoadingGeminiModels)
            }
            .font(.caption)
            if !keyStatus.isEmpty {
                Text(keyStatus).font(.caption2).foregroundStyle(.secondary)
            }
            if model.isLoadingGeminiModels { ProgressView() }
            if !model.aiGeminiModelStatus.isEmpty {
                Text(model.aiGeminiModelStatus)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Picker("Model", selection: $model.aiGeminiModelName) {
                Text("Tự động").tag("")
                ForEach(model.aiGeminiModels) { item in
                    Text(item.title).tag(item.name)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.aiGeminiModels.isEmpty)

            Picker("Phong cách metadata",
                   selection: $model.aiMetadataStyle) {
                ForEach(["Tự nhiên, chuyên nghiệp", "SEO tìm kiếm",
                         "TikTok / Reels ngắn gọn", "YouTube hấp dẫn",
                         "Giáo dục, dễ hiểu", "Bán hàng thuyết phục",
                         "Du lịch và đời sống", "Điện ảnh"],
                        id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            TextField("Yêu cầu riêng (không bắt buộc)",
                      text: $model.aiMetadataInstructions,
                      axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)

            Button {
                model.generateAIMetadata(apiKey: geminiKey)
            } label: {
                Label(model.isGeneratingAIMetadata ?
                      "AI đang tạo metadata…" : "Tạo metadata bằng Gemini",
                      systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isGeneratingAIMetadata ||
                      model.aiGeminiModels.isEmpty ||
                      geminiKey.isEmpty)
            Button {
                model.generateAIPublishingVariants(apiKey: geminiKey)
            } label: {
                Label(model.isGeneratingPublishingVariants ?
                      "Đang tạo 3 bài đăng…" :
                      "Tạo 3 phiên bản YouTube / TikTok / Facebook",
                      systemImage: "rectangle.stack")
            }
            .buttonStyle(.bordered)
            .disabled(model.isGeneratingPublishingVariants ||
                      model.isGeneratingAIMetadata ||
                      model.aiGeminiModels.isEmpty ||
                      geminiKey.isEmpty)
            if model.isGeneratingPublishingVariants { ProgressView() }
            if !model.aiPublishingVariants.isEmpty {
                Text("AI Publishing Studio — chọn phiên bản")
                    .font(.caption.bold())
                let channels = ["TikTok / Reels", "YouTube", "Facebook"]
                ForEach(model.aiPublishingVariants.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(index < channels.count ? channels[index] : "Bài đăng")
                            .font(.caption.bold())
                        Text(model.aiPublishingVariants[index].title)
                            .font(.caption)
                        HStack(spacing: 7) {
                            Button("Dùng bản này") {
                                model.aiMetadataDraft =
                                    model.aiPublishingVariants[index]
                            }
                            .buttonStyle(.borderedProminent)
                            ShareLink(item:
                                model.aiPublishingVariants[index].socialCaption
                            ) {
                                Label("Chia sẻ", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                        }
                        .font(.caption2)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if model.isGeneratingAIMetadata { ProgressView() }
            if !model.aiMetadataStatus.isEmpty {
                Text(model.aiMetadataStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.aiMetadataDraft != nil {
                Divider()
                Text("Xem và sửa bản AI tạo trước khi gắn vào MP4")
                    .font(.caption.bold())
                field("Tiêu đề AI", text: draftText(\.title),
                      hint: "Tiêu đề video")
                field("Mô tả AI", text: draftText(\.description),
                      hint: "Nội dung video")
                field("Từ khóa AI (cách nhau bằng dấu phẩy)",
                      text: draftWords(\.keywords), hint: "từ khóa 1, từ khóa 2")
                field("Thể loại AI", text: draftText(\.genre),
                      hint: "Giáo dục")
                field("Ghi chú AI", text: draftText(\.comment),
                      hint: "Ghi chú xuất bản")
                field("Hashtag (chỉ dùng cho bài đăng mạng xã hội)",
                      text: draftWords(\.hashtags),
                      hint: "#video, #thiennhien")
                HStack(spacing: 8) {
                    Button {
                        model.applyAIMetadata()
                    } label: {
                        Label("Áp dụng vào MP4", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    if let socialCaption = model.aiMetadataDraft?.socialCaption {
                        ShareLink(item: socialCaption) {
                            Label("Chia sẻ mô tả", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.caption)
                Text("Hashtag dùng cho chú thích mạng xã hội, không đảm bảo được các nền tảng đọc từ MP4. Nút Áp dụng chỉ cập nhật trường metadata biên tập; không thay đổi tác giả, bản quyền hoặc năm.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.cyan.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12))
        .onAppear {
            geminiKey = GeminiAPIKeyStore.load()
            if !geminiKey.isEmpty && model.aiGeminiModels.isEmpty {
                model.discoverGeminiModels(apiKey: geminiKey)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>,
                       hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
    }
}
