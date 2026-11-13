import SwiftUI

/// AI rewrites existing transcript text only; no automatic video upload.
struct GeminiRevoiceStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @AppStorage("ViePN.GeminiGateway.BaseURL") private var gatewayURL = ""
    @AppStorage("ViePN.Gemini.Mode") private var connectionMode = "direct"
    @State private var directAPIKey = ""
    @State private var gatewayToken = ""
    @State private var keyStatus = ""
    @State private var muteSourceVideo = false
    @State private var showConfiguration = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gemini AI • Thuyết minh lại video",
                  systemImage: "sparkles.tv")
                .font(.headline)
            Text("Nhận diện lời dẫn đã có → Gemini viết lại → duyệt nội dung → tạo giọng đọc và phụ đề mới.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Kết nối AI", selection: $connectionMode) {
                Text("API key trực tiếp").tag("direct")
                Text("Gateway riêng").tag("gateway")
            }
            .pickerStyle(.segmented)

            if connectionMode == "direct" {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Nhập Gemini API key", text: $directAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button {
                            if GeminiAPIKeyStore.save(
                                directAPIKey.trimmingCharacters(
                                    in: .whitespacesAndNewlines)) {
                                keyStatus = "Đã lưu API key vào Keychain."
                                model.discoverGeminiModels(apiKey: directAPIKey)
                            } else {
                                keyStatus = "Không lưu được API key vào Keychain."
                            }
                        } label: {
                            Label("Lưu & nhận diện model", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            model.discoverGeminiModels(apiKey: directAPIKey)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isLoadingGeminiModels ||
                                  directAPIKey.isEmpty)
                        Button(role: .destructive) {
                            _ = GeminiAPIKeyStore.save("")
                            directAPIKey = ""
                            model.aiGeminiModels = []
                            model.aiGeminiModelName = ""
                            keyStatus = "Đã xóa API key."
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                    }
                    if model.isLoadingGeminiModels { ProgressView() }
                    if !keyStatus.isEmpty {
                        Text(keyStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                    if !model.aiGeminiModelStatus.isEmpty {
                        Text(model.aiGeminiModelStatus)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Picker("Model Gemini", selection: $model.aiGeminiModelName) {
                        Text("Tự động chọn model phù hợp").tag("")
                        ForEach(model.aiGeminiModels) { item in
                            Text(item.title + " · " + item.name)
                                .tag(item.name)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(model.aiGeminiModels.isEmpty)
                    Text("Tự nhận diện danh sách model được phép dùng với API key này. Không lưu key trong mã nguồn, GitHub hoặc UserDefaults.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Chế độ trực tiếp gửi transcript từ iPhone đến Google qua HTTPS. Với app phát hành công khai, Gateway riêng an toàn hơn.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                DisclosureGroup("Kết nối Gemini Gateway",
                                isExpanded: $showConfiguration) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("https://your-worker.workers.dev",
                                  text: $gatewayURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        SecureField("Gateway access token",
                                    text: $gatewayToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Lưu token vào Keychain") {
                            AIGatewayCredentials.saveToken(gatewayToken)
                        }
                        .buttonStyle(.bordered)
                        Text("API key nằm trên máy chủ Gateway, không nằm trong app.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 5)
                }
            }

            Group {
                Text("Bước 1 • Nhận diện thuyết minh / phụ đề")
                    .font(.subheadline.bold())
                if let selectedClipID,
                   model.clips.contains(where: {
                       $0.id == selectedClipID && $0.kind == .video
                   }) {
                    Button {
                        model.autoCaptionSource = .selectedVideo
                        model.replaceExistingAutoCaptions = true
                        model.generateAutoCaptions(selectedClipID: selectedClipID)
                    } label: {
                        Label("Nhận diện lời nói từ clip đang chọn",
                              systemImage: "waveform")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isGeneratingAutoCaptions)
                } else {
                    Text("Chọn một clip video trên timeline để nhận diện lời nói; hoặc nhập SRT ở tab Phụ đề.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Có \(model.subtitles.count) đoạn phụ đề. Cần rà soát lỗi nhận diện trước khi gửi Gemini.")
                    .font(.caption)
                if model.isGeneratingAutoCaptions { ProgressView() }
                if !model.autoCaptionStatus.isEmpty {
                    Text(model.autoCaptionStatus)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider()
            Text("Bước 2 • Gemini viết lại lời dẫn")
                .font(.subheadline.bold())
            Picker("Phong cách", selection: $model.aiRevoiceStyle) {
                ForEach(["Kể chuyện tự nhiên", "Nữ nhẹ nhàng",
                         "Đời sống thiên nhiên", "Quảng cáo thu hút",
                         "Tin tức chuyên nghiệp", "Giải thích kiến thức",
                         "Hài hước ngắn gọn", "Truyền cảm hứng"],
                        id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Ngôn ngữ", selection: $model.aiRevoiceLanguage) {
                ForEach(["Tiếng Việt", "English", "中文", "日本語", "한국어"],
                        id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            TextField("Yêu cầu thêm: văn phong, đối tượng, nhịp điệu…",
                      text: $model.aiRevoiceInstructions, axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)
            Button {
                if connectionMode == "direct" {
                    model.rewriteSubtitlesDirectGemini(apiKey: directAPIKey)
                } else {
                    AIGatewayCredentials.saveToken(gatewayToken)
                    model.rewriteSubtitlesWithGemini(
                        gatewayURL: gatewayURL, token: gatewayToken
                    )
                }
            } label: {
                Label(model.isRewritingWithGemini ?
                      "Gemini đang viết…" : "Gemini viết lại thuyết minh",
                      systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isRewritingWithGemini ||
                      model.isGeneratingAutoCaptions ||
                      model.subtitles.isEmpty)
            if model.isRewritingWithGemini { ProgressView() }
            if !model.aiRevoiceStatus.isEmpty {
                Text(model.aiRevoiceStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !model.aiRevoiceDraft.isEmpty {
                Divider()
                Text("Bước 3 • Duyệt bản Gemini")
                    .font(.subheadline.bold())
                Text("Mốc phụ đề giữ nguyên; giọng TTS chưa căn khớp từng câu. Kiểm tra nội dung trước khi áp dụng.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.aiRevoiceDraft.prefix(15)) { cue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: "%.1f–%.1fs", cue.start, cue.end))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(cue.text).font(.caption)
                    }
                }
                if model.aiRevoiceDraft.count > 15 {
                    Text("… và \(model.aiRevoiceDraft.count - 15) đoạn khác")
                        .font(.caption2)
                }
                Toggle("Tắt toàn bộ âm thanh clip gốc khi áp dụng",
                       isOn: $muteSourceVideo)
                    .font(.caption)
                Text("Lưu ý: thao tác này cũng tắt nhạc và âm thanh môi trường nằm chung track với giọng nói.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    model.applyGeminiRevoice(
                        muteSourceVideo: muteSourceVideo)
                } label: {
                    Label("Áp dụng lời mới & phụ đề",
                          systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()
            Text("Bước 4 • Xuất giọng thuyết minh")
                .font(.subheadline.bold())
            Button {
                model.generateNarrationFromText()
            } label: {
                Label(model.isGeneratingNarration ?
                      "Đang tạo giọng…" : "Tạo giọng đọc từ lời mới",
                      systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            .disabled(model.narrationText.isEmpty ||
                      model.isGeneratingNarration)
            Button {
                model.generateTimeMatchedRevoice()
            } label: {
                Label(model.isGeneratingSyncedRevoice ?
                      "Đang ghép giọng theo thời gian…" :
                      "Tạo giọng khớp từng mốc phụ đề",
                      systemImage: "waveform.badge.mic")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.subtitles.isEmpty ||
                      model.isGeneratingSyncedRevoice)
            if model.isGeneratingSyncedRevoice { ProgressView() }
            Text("Chế độ khớp mốc tạo tiếng nói từng câu rồi co/giãn thời lượng. Tốc độ giọng có thể không tự nhiên ở câu quá dài; kiểm tra bản xem thử 720p.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Sử dụng giọng iOS đã chọn tại tab Giọng. Bản đầu chưa hỗ trợ giọng Gemini TTS hay tự tách giọng khỏi nhạc nền.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            gatewayToken = AIGatewayCredentials.loadToken()
            directAPIKey = GeminiAPIKeyStore.load()
            if connectionMode == "direct" && !directAPIKey.isEmpty &&
                model.aiGeminiModels.isEmpty {
                model.discoverGeminiModels(apiKey: directAPIKey)
            }
        }
    }
}
