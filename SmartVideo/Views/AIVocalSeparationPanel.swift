import SwiftUI
import AVFoundation

struct AIVocalSeparationPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @AppStorage("ViePN.Separator.BaseURL") private var serverURL = ""
    @State private var token = ""
    @State private var showSettings = false
    @State private var approveUpload = false
    @State private var approveReplacement = false
    @State private var audioPreview: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Voice Separation • Giữ nhạc nền",
                  systemImage: "waveform.path")
                .font(.headline)
            Text("Tách vocal và nền bằng mô hình Demucs trên máy chủ riêng, không phải Gemini. Có thể còn nhiễu giọng hoặc mất một phần nhạc.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Máy chủ Audio Separator", isExpanded: $showSettings) {
                TextField("https://your-separator.example.com",
                          text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                SecureField("Access token của Audio Separator",
                            text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button("Lưu token vào Keychain") {
                    _ = AIVocalSeparatorCredentials.save(token)
                }
                .buttonStyle(.bordered)
                Text("Cần triển khai backend/audio_separator với HTTPS và token riêng trước. Chế độ này không chạy offline và chưa hỗ trợ nhiều clip ghép.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("Tôi đồng ý tải AUDIO của clip lên máy chủ riêng để tách giọng.",
                   isOn: $approveUpload)
                .font(.caption)
            Button {
                _ = AIVocalSeparatorCredentials.save(token)
                model.separateSelectedClipVoice(
                    clipID: selectedClipID,
                    serverURL: serverURL, token: token
                )
            } label: {
                Label(model.isSeparatingAudio ?
                      "AI đang tách giọng…" : "Tách giọng, giữ nhạc và âm môi trường",
                      systemImage: "waveform")
            }
            .buttonStyle(.bordered)
            .disabled(!approveUpload ||
                      selectedClipID == nil ||
                      model.isSeparatingAudio ||
                      serverURL.isEmpty || token.isEmpty ||
                      model.clips.count != 1)
            if model.isSeparatingAudio { ProgressView() }
            if !model.separationStatus.isEmpty {
                Text(model.separationStatus)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let separated = model.separatedBackgroundURL {
                HStack(spacing: 8) {
                    Button {
                        do {
                            audioPreview?.stop()
                            audioPreview = try AVAudioPlayer(
                                contentsOf: separated)
                            audioPreview?.play()
                        } catch {
                            model.errorText = "Không phát được nền âm thanh: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Nghe thử nền", systemImage: "play.circle")
                    }
                    .buttonStyle(.bordered)
                    ShareLink(item: separated) {
                        Label("Chia sẻ M4A", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                Toggle("Tôi đồng ý tắt track âm thanh gốc và thay nhạc nền hiện tại.",
                       isOn: $approveReplacement)
                    .font(.caption)
                Button {
                    audioPreview?.stop()
                    model.applySeparatedBackground()
                    approveReplacement = false
                } label: {
                    Label("Áp dụng nền đã tách vào video",
                          systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!approveReplacement)
                Text("Bước áp dụng thay track nhạc hiện có trong dự án một clip. Nên sao lưu dự án trước khi thay.")
                    .font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12))
        .onAppear { token = AIVocalSeparatorCredentials.load() }
    }
}
