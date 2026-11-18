import SwiftUI

extension MusicVideoStudio {
    struct ExportSheetView: View {
        @ObservedObject var model: MusicVideoEditorModel
        @StateObject private var exporter = ProjectExporter()
        @State private var settings = ExportSheetView.loadSettings()
        @Environment(\.dismiss) private var dismiss

        private static let key = "musicVideoStudio.exportSettings"

        static func loadSettings() -> ExportSettings {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let saved = try? JSONDecoder().decode(ExportSettings.self, from: data) else { return ExportSettings() }
            return saved.sanitized
        }

        private func remember() {
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.key) }
        }

        private var size: (width: Int, height: Int) { settings.size(aspect: model.project.aspect) }
        private var duration: ProjectTime { model.project.duration }

        var body: some View {
            NavigationStack {
                Form {
                    switch exporter.phase {
                    case .idle, .cancelled, .failed: settingsSections
                    case .finished(let url): finishedSection(url)
                    default: progressSection
                    }
                }
                .navigationTitle("Xuất video")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") { dismiss() }.disabled(exporter.isRunning)
                    }
                }
            }
            .interactiveDismissDisabled(exporter.isRunning)
            .onAppear { model.playback.pause() }
            .onChange(of: settings) { _ in remember() }
        }

        @ViewBuilder private var settingsSections: some View {
            Section("Chất lượng") {
                Picker("Độ phân giải", selection: $settings.resolution) {
                    ForEach(ExportResolution.allCases) { Text($0.title).tag($0) }
                }
                Picker("Khung hình/giây", selection: $settings.fps) {
                    ForEach(ExportSettings.supportedFPS, id: \.self) { Text("\($0) fps").tag($0) }
                }.pickerStyle(.segmented)
                Picker("Bộ mã hóa", selection: $settings.codec) {
                    ForEach(ExportCodec.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Định dạng", selection: $settings.container) {
                    ForEach(ExportContainer.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section("Tóm tắt") {
                LabeledContent("Tỉ lệ", value: model.project.aspect.rawValue)
                LabeledContent("Kích thước", value: "\(size.width) × \(size.height)")
                LabeledContent("Thời lượng", value: duration.timecode(fps: settings.sanitized.fps))
                LabeledContent("Số khung hình", value: "\(settings.totalFrames(duration: duration))")
                LabeledContent("Dung lượng ước tính",
                               value: ByteCountFormatter.string(fromByteCount: settings.estimatedBytes(duration: duration, aspect: model.project.aspect), countStyle: .file))
                Text("Âm thanh AAC 192 kbps, trộn từ các clip nhạc theo đúng âm lượng, mờ dần và lặp như khi xem trước.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if settings.codec == .hevc {
                Text("HEVC nhỏ hơn nhưng một số thiết bị và ứng dụng cũ không phát được.").font(.caption).foregroundStyle(.orange)
            }
            if settings.resolution == .p2160 || (settings.resolution == .p1440 && settings.fps == 60) {
                Text("Độ phân giải cao và 60 fps cần nhiều thời gian và bộ nhớ. Giữ màn hình sáng và để ứng dụng ở phía trước trong lúc xuất.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if case .failed(let message) = exporter.phase {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if case .cancelled = exporter.phase {
                Text("Đã huỷ. Chưa có tệp nào được tạo.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    remember()
                    exporter.start(model: model, settings: settings)
                } label: {
                    Label("Bắt đầu xuất", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
            }
        }

        private var progressSection: some View {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: exporter.fraction).tint(.cyan)
                    Text(statusText).font(.footnote).monospacedDigit()
                    Text("Đừng thoát ứng dụng. Màn hình được giữ sáng cho đến khi xong.").font(.caption2).foregroundStyle(.secondary)
                }
                Button("Huỷ xuất", role: .destructive) { exporter.cancel() }
            }
        }

        private var statusText: String {
            switch exporter.phase {
            case .preparing(let what): return what
            case .rendering(let done, let total): return "Đang dựng khung hình \(done)/\(total) (\(Int(exporter.fraction * 100))%)"
            case .encodingAudio: return "Đang mã hóa âm thanh…"
            case .finishing: return "Đang hoàn tất tệp…"
            default: return ""
            }
        }

        private func finishedSection(_ url: URL) -> some View {
            Group {
                Section {
                    Label("Đã xuất xong", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    LabeledContent("Tệp", value: url.lastPathComponent)
                    if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        LabeledContent("Dung lượng", value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                    }
                }
                Section {
                    Button {
                        Task { await exporter.saveToPhotos() }
                    } label: { Label("Lưu vào Ảnh", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(.cyan)
                    ShareLink(item: url) { Label("Chia sẻ / Lưu vào Tệp", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    if let message = exporter.saveMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    Button("Xuất lại với cài đặt khác") { exporter.reset() }
                }
            }
        }
    }
}
