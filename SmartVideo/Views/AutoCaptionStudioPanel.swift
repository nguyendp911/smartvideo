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

            Text("Mỗi lần phân tích tối đa 58 giây đầu của nguồn được chọn. " +
                 "Nếu là video, thời gian phụ đề tự căn theo vị trí, điểm cắt " +
                 "và tốc độ của clip. Hãy kiểm tra và sửa lời nhận diện trước khi xuất.")
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
        }
        .padding(10)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 11))
    }
}
