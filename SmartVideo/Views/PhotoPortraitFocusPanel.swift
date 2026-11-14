import SwiftUI

/// Photo-only portrait/background focusing with local Apple Vision preflight.
struct PhotoPortraitFocusPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @Binding var compareOriginal: Bool

    @State private var isCheckingSubject = false
    @State private var focusStatus = ""
    @State private var showManualControls = true

    private var photo: TimelineClip? {
        model.clips.first {
            $0.id == selectedClipID && $0.kind == .image
        }
    }

    private var settings: PhotoPortraitFocusSettings {
        photo?.portraitFocus ?? .off
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Portrait Focus • Xóa phông nghệ thuật",
                  systemImage: "camera.aperture")
                .font(.headline)
            Text("Vision nhận diện người trên ảnh, làm mờ riêng hậu cảnh, làm sáng chủ thể và làm mềm mép tóc/quần áo. Không gửi ảnh lên máy chủ.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if photo == nil {
                Text("Hãy chọn một ảnh trên timeline.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 7) {
                ForEach(PhotoPortraitFocusSettings.Style.allCases) { style in
                    Button {
                        checkThenApply(style.settings)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: style.symbol)
                                .font(.title3)
                            Text(style.rawValue)
                                .font(.caption2.bold())
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .disabled(photo == nil || isCheckingSubject)
                }
            }
            if isCheckingSubject { ProgressView() }
            if !focusStatus.isEmpty {
                Text(focusStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if settings.enabled {
                DisclosureGroup("Tinh chỉnh chiều sâu",
                                isExpanded: $showManualControls) {
                    VStack(spacing: 10) {
                        amountSlider("Độ mờ hậu cảnh",
                                     path: \.blurStrength,
                                     in: 0...1,
                                     value: settings.blurStrength)
                        amountSlider("Giảm sáng nền",
                                     path: \.backgroundDim,
                                     in: 0...0.4,
                                     value: settings.backgroundDim)
                        amountSlider("Màu nền",
                                     path: \.backgroundSaturation,
                                     in: 0.55...1.2,
                                     value: settings.backgroundSaturation)
                        amountSlider("Mềm đường viền",
                                     path: \.edgeSoftness,
                                     in: 0...1,
                                     value: settings.edgeSoftness)
                        amountSlider("Sáng chủ thể",
                                     path: \.subjectLiftEV,
                                     in: 0...0.4,
                                     value: settings.subjectLiftEV)
                    }
                }
                .font(.caption.bold())
                Toggle("So sánh ảnh gốc",
                       isOn: $compareOriginal)
                    .font(.caption)
                Button(role: .destructive) {
                    model.applyPortraitFocus(
                        to: selectedClipID, settings: .off)
                    compareOriginal = false
                    focusStatus = "Đã tắt Portrait Focus."
                } label: {
                    Label("Xóa hiệu ứng Portrait Focus",
                          systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            Text("Chỉ hỗ trợ ảnh có người được Vision phát hiện. Đây là mô phỏng xóa phông dựa trên mặt nạ chủ thể, không phải bản đồ độ sâu quang học. Hiệu ứng được xuất vào MP4 và có thể hoàn tác.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.purple.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: selectedClipID) { _ in
            focusStatus = ""
        }
    }

    private func checkThenApply(_ value: PhotoPortraitFocusSettings) {
        guard let photo else { return }
        let id = photo.id
        let fileURL = photo.fileURL
        isCheckingSubject = true
        focusStatus = "Đang nhận diện người bằng Vision trên iPhone…"
        Task {
            defer { isCheckingSubject = false }
            do {
                let found = try await PhotoPortraitFocusProcessor.detectPerson(
                    in: fileURL)
                guard self.photo?.id == id,
                      self.photo?.fileURL == fileURL else {
                    focusStatus = "Ảnh đã đổi; hãy thử lại."
                    return
                }
                guard found else {
                    focusStatus = "Không thấy người đủ rõ trong ảnh. Chưa áp hiệu ứng để tránh làm mờ toàn bộ cảnh."
                    return
                }
                model.applyPortraitFocus(to: id, settings: value)
                compareOriginal = false
                focusStatus = "Đã nhận diện người và áp dụng hiệu ứng."
            } catch {
                focusStatus = "Không thể nhận diện người: " +
                    error.localizedDescription
            }
        }
    }

    private func amountSlider(
        _ label: String,
        path: WritableKeyPath<PhotoPortraitFocusSettings, Double>,
        in bounds: ClosedRange<Double>,
        value: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.0f%%",
                            path == \.backgroundSaturation ?
                              value * 100 : value / bounds.upperBound * 100))
                    .monospacedDigit()
            }
            .font(.caption2)
            Slider(value: Binding(
                get: { settings[keyPath: path] },
                set: { next in
                    var updated = settings
                    updated[keyPath: path] = next
                    model.updatePortraitFocus(
                        clipID: selectedClipID, settings: updated)
                }
            ), in: bounds, onEditingChanged: { editing in
                if editing {
                    model.beginPortraitFocusAdjustment()
                }
            })
            .tint(.purple)
        }
    }
}
