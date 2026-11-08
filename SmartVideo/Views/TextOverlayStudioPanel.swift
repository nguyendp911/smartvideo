import SwiftUI

struct TextOverlayStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?

    private var selected: TextOverlayClip? {
        model.textOverlays.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Lớp chữ & tiêu đề", systemImage: "textformat")
                    .font(.headline)
                Spacer()
                Button {
                    model.addTextOverlay()
                    selectedID = model.textOverlays.last?.id
                } label: {
                    Label("Thêm chữ", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }

            ForEach(model.textOverlays) { item in
                HStack(spacing: 6) {
                    Button {
                        selectedID = item.id
                    } label: {
                        HStack {
                            Text(item.text).lineLimit(1)
                            Spacer()
                            if selectedID == item.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(8)
                        .background(selectedID == item.id ?
                            Color.cyan.opacity(0.18) : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        model.removeTextOverlay(item.id)
                        selectedID = model.textOverlays.first?.id
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                }
                .font(.caption)
            }

            if let item = selected,
               let idx = model.textOverlays.firstIndex(where: { $0.id == item.id }) {
                TextField("Nội dung chữ", text: $model.textOverlays[idx].text,
                          axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                row("Bắt đầu", "\(String(format: "%.1f", item.start))s")
                Slider(value: $model.textOverlays[idx].start,
                       in: 0...max(0.1, model.totalDuration - 0.1),
                       step: 0.1).tint(.cyan)

                row("Thời lượng", "\(String(format: "%.1f", item.duration))s")
                Slider(value: $model.textOverlays[idx].duration,
                       in: 0.1...max(0.2, model.totalDuration - item.start),
                       step: 0.1).tint(.cyan)

                row("Cỡ chữ", "\(Int(item.fontSize))")
                Slider(value: $model.textOverlays[idx].fontSize,
                       in: 20...120, step: 2).tint(.cyan)

                Text("Màu chữ (HEX)")
                    .font(.caption.bold())
                TextField("FFFFFF", text: $model.textOverlays[idx].colorHex)
                    .textInputAutocapitalization(.characters)
                    .textFieldStyle(.roundedBorder)

                Toggle("Nền tối sau chữ",
                       isOn: $model.textOverlays[idx].useBackground)
                    .font(.caption)
                row("Độ mờ", "\(Int(item.opacity * 100))%")
                Slider(value: $model.textOverlays[idx].opacity,
                       in: 0.05...1, step: 0.05).tint(.cyan)

                Picker("Đường chuyển động", selection: $model.textOverlays[idx].easing) {
                    ForEach(OverlayEasing.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Text("Vị trí đầu: kéo trên preview hoặc chỉnh X/Y")
                    .font(.caption.bold())
                Slider(value: $model.textOverlays[idx].startX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.textOverlays[idx].startY,
                       in: 0.05...0.95, step: 0.01)

                Text("Vị trí cuối")
                    .font(.caption.bold())
                Slider(value: $model.textOverlays[idx].endX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.textOverlays[idx].endY,
                       in: 0.05...0.95, step: 0.01)

                Button("Đặt tiêu đề chính giữa") {
                    model.textOverlays[idx].startX = 0.5
                    model.textOverlays[idx].startY = 0.5
                    model.textOverlays[idx].endX = 0.5
                    model.textOverlays[idx].endY = 0.5
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }.padding(10)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.caption)
    }
}
