import SwiftUI

struct Hook3sStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @State private var selectedID: UUID?
    @State private var hookTitle = ""

    private var selectedClip: TimelineClip? {
        model.clips.first { $0.id == selectedClipID && $0.kind == .video }
    }
    private var chosen: Hook3sSuggestion? {
        model.hook3sSuggestions.first { $0.id == selectedID } ??
            model.hook3sSuggestions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Hook 3s • Mở đầu giữ chân người xem",
                  systemImage: "bolt.fill")
                .font(.headline)
            Text("Quét video bằng Vision trên iPhone và chọn 3 giây nhiều chuyển động, gương mặt hoặc tương phản. Đây là đề xuất dựa trên khung hình, không bảo đảm video viral.")
                .font(.caption).foregroundStyle(.secondary)
            if let selectedClip {
                Text("Đang chọn: " + selectedClip.filename)
                    .font(.caption2.bold()).lineLimit(1)
            } else {
                Text("Chọn một clip video trên timeline.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button {
                selectedID = nil
                model.findHook3s(clipID: selectedClipID)
            } label: {
                Label(model.isFindingHook3s ?
                      "Đang tìm Hook 3s…" : "Tự tìm 3 giây thu hút nhất",
                      systemImage: "sparkles.tv")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedClip == nil || model.isFindingHook3s)
            if model.isFindingHook3s { ProgressView() }
            if !model.hook3sStatus.isEmpty {
                Text(model.hook3sStatus)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !model.hook3sSuggestions.isEmpty {
                Text("Chọn đoạn mở đầu")
                    .font(.caption.bold())
                ForEach(model.hook3sSuggestions) { candidate in
                    Button {
                        selectedID = candidate.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: chosen?.id == candidate.id ?
                                  "largecircle.fill.circle" : "circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Giây %.1f–%.1f • Điểm %.0f/100",
                                            candidate.start,
                                            candidate.start + candidate.duration,
                                            candidate.score * 100))
                                    .font(.caption.bold())
                                Text(candidate.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .background(
                        chosen?.id == candidate.id ?
                            Color.cyan.opacity(0.12) :
                            Color.secondary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                TextField("Câu Hook nổi bật trên video (không bắt buộc)",
                          text: $hookTitle)
                    .textFieldStyle(.roundedBorder)
                Button {
                    if let chosen {
                        _ = model.insertHook3s(
                            clipID: selectedClipID,
                            suggestion: chosen,
                            title: hookTitle
                        )
                    }
                } label: {
                    Label("Chèn Hook 3 giây vào đầu video",
                          systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.borderedProminent)
                Text("Đoạn gốc vẫn giữ nguyên. Phụ đề, chữ, âm thanh và các lớp thời gian sẽ được dời về sau. Nếu dùng chuyển cảnh hòa tan, phần chuyển tiếp sẽ chồng lên cuối Hook.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if model.canUndoHook3s {
                Button {
                    model.undoHook3s()
                } label: {
                    Label("Hoàn tác chèn Hook 3s",
                          systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

struct AutoEnhanceStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @Binding var compareOriginal: Bool
    @State private var strength = 0.65

    private var selectedClip: TimelineClip? {
        model.clips.first { $0.id == selectedClipID }
    }
    private var settings: AutoEnhanceSettings {
        selectedClip?.autoEnhance ?? .off
    }
    private func setting(_ keyPath: WritableKeyPath<AutoEnhanceSettings, Double>)
        -> Binding<Double> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                guard let selectedClipID else { return }
                var updated = settings
                updated.enabled = true
                updated[keyPath: keyPath] = value
                model.setAutoEnhance(selectedClipID, settings: updated)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Auto Enhance • Làm đẹp & tăng nét",
                  systemImage: "camera.filters")
                .font(.headline)
            Text("Tự đo ánh sáng khung hình; cân sáng, tăng tương phản nhẹ, giữ màu tự nhiên, giảm nhiễu và làm nét bằng Core Image.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Cường độ tự tối ưu")
                Spacer()
                Text("\(Int(strength * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $strength, in: 0.2...1, step: 0.05)
                .tint(.cyan)
            Button {
                compareOriginal = false
                model.autoEnhanceClip(
                    clipID: selectedClipID, strength: strength
                )
            } label: {
                Label(model.isAutoTuningEnhance ?
                      "Đang phân tích ảnh…" : "Tự làm đẹp và tăng nét",
                      systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedClipID == nil || model.isAutoTuningEnhance)
            if model.isAutoTuningEnhance { ProgressView() }
            if !model.autoEnhanceStatus.isEmpty {
                Text(model.autoEnhanceStatus)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if settings.enabled {
                VStack(spacing: 6) {
                    parameter("Phơi sáng", value: setting(\.exposureEV),
                              range: -0.6...0.8,
                              display: String(format: "%+.2f EV", settings.exposureEV))
                    parameter("Tương phản", value: setting(\.contrast),
                              range: 0.8...1.25,
                              display: String(format: "%.2f", settings.contrast))
                    parameter("Màu sắc", value: setting(\.saturation),
                              range: 0.8...1.2,
                              display: String(format: "%.2f", settings.saturation))
                    parameter("Giảm nhiễu", value: setting(\.noiseReduction),
                              range: 0...0.06,
                              display: String(format: "%.3f", settings.noiseReduction))
                    parameter("Độ nét", value: setting(\.sharpness),
                              range: 0...0.9,
                              display: String(format: "%.2f", settings.sharpness))
                }
                Toggle("So sánh ảnh/video gốc",
                       isOn: $compareOriginal)
                    .font(.caption)
                Button(role: .destructive) {
                    if let selectedClipID {
                        model.disableAutoEnhance(selectedClipID)
                        compareOriginal = false
                    }
                } label: {
                    Label("Tắt Auto Enhance", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            Text("Áp dụng vào cả preview và MP4 xuất ra. Đây là khử nhiễu/làm nét thuật toán, không phải AI phục hồi chi tiết thực hay nâng độ phân giải siêu phân giải.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.cyan.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func parameter(_ label: String, value: Binding<Double>,
                           range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(display).monospacedDigit()
            }
            .font(.caption2)
            Slider(value: value, in: range)
                .tint(.cyan)
        }
    }
}
