import SwiftUI

struct AutoCaptionStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Auto Captions · Speech", systemImage: "waveform.and.mic")
                .font(.subheadline.bold())

            Picker("Nguồn lời nói", selection: $model.autoCaptionSource) {
                ForEach(AutoCaptionSource.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Picker("Ngôn ngữ nhận diện",
                   selection: $model.autoCaptionLanguage) {
                ForEach(AutoCaptionLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
            .font(.caption)

            Toggle("Cho phép dịch vụ Speech của Apple",
                   isOn: $model.allowAppleSpeechService)
                .font(.caption)
                .tint(.cyan)

            Text(model.allowAppleSpeechService ?
                 "Bạn cho phép Apple xử lý âm thanh khi cần; có thể cần Internet. " +
                 "Chỉ bật cho nguồn mà bạn có quyền xử lý." :
                 "Chế độ riêng tư: chỉ nhận diện trên iPhone. " +
                 "Nếu ngôn ngữ không hỗ trợ offline, ứng dụng sẽ báo lỗi " +
                 "và KHÔNG tự gửi âm thanh ra mạng.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("Nhận diện toàn bộ (tối đa 10 phút)",
                   isOn: $model.processLongAutoCaptions)
                .font(.caption)
                .tint(.cyan)

            Toggle("Thay toàn bộ phụ đề hiện có",
                   isOn: $model.replaceExistingAutoCaptions)
                .font(.caption)
                .tint(.cyan)

            Button {
                model.generateAutoCaptions(selectedClipID: selectedClipID)
            } label: {
                Label(model.isGeneratingAutoCaptions ?
                      "Đang nhận diện..." : "Nhận diện và tạo phụ đề",
                      systemImage: "captions.bubble")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isGeneratingAutoCaptions ||
                      model.clips.isEmpty)

            if model.isGeneratingAutoCaptions {
                ProgressView("Phân tích lời nói trong đoạn audio...")
                    .font(.caption)
            }
            if !model.autoCaptionStatus.isEmpty {
                Text(model.autoCaptionStatus)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            Text("Âm thanh dài được chia thành các phần 52 giây, nhận diện " +
                 "lần lượt để giữ thời điểm từng từ; giới hạn 10 phút mỗi lần. " +
                 "Có thể mất nhiều thời gian. Sửa từ sai trước khi xuất MP4/SRT.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 11))
    }
}

struct SubtitleStylePanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Kiểu phụ đề", systemImage: "textformat.size")
                .font(.subheadline.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(SubtitleAppearance.Preset.allCases) { preset in
                        Button(preset.rawValue) {
                            model.subtitleAppearance = preset.settings
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack {
                Text("Kích thước chữ")
                Spacer()
                Text(String(format: "%.0f%%",
                            model.subtitleAppearance.fontScale * 100))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.subtitleAppearance.fontScale,
                   in: 0.65...1.6, step: 0.05)
                .tint(.cyan)

            HStack {
                Text("Độ mờ nền")
                Spacer()
                Text("\(Int(model.subtitleAppearance.backgroundOpacity * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.subtitleAppearance.backgroundOpacity,
                   in: 0...0.95, step: 0.05)
                .tint(.cyan)

            Toggle("Đổ bóng chữ",
                   isOn: $model.subtitleAppearance.shadowEnabled)
                .font(.caption)
                .tint(.cyan)

            HStack {
                Text("Màu chữ HEX")
                    .font(.caption)
                TextField("FFFFFF",
                          text: $model.subtitleAppearance.foregroundHex)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
            }

            Divider()
            Toggle("Karaoke · sáng từng từ theo giọng nói",
                   isOn: $model.subtitleAppearance.karaokeEnabled)
                .font(.caption.bold())
                .tint(.cyan)

            if model.subtitleAppearance.karaokeEnabled {
                Picker("Hiệu ứng karaoke",
                       selection: $model.subtitleAppearance.karaokeMotion) {
                    ForEach(KaraokeMotion.allCases) { motion in
                        Text(motion.rawValue).tag(motion)
                    }
                }
                .font(.caption)
                .pickerStyle(.segmented)

                HStack {
                    Text("Màu chữ đang đọc")
                        .font(.caption)
                    TextField("FFE563",
                              text: $model.subtitleAppearance.karaokeHex)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                }
                Text("Karaoke chỉ hoạt động với phụ đề Auto Captions " +
                     "có mốc thời gian từng từ. Phụ đề SRT/TXT vẫn hiển thị bình thường.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 11))
    }
}
