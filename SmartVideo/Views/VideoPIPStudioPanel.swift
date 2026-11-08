import SwiftUI
import PhotosUI

struct VideoPIPStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    @Binding var pickerItem: PhotosPickerItem?

    private var selected: VideoOverlayClip? {
        model.videoOverlays.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Video Picture-in-Picture", systemImage: "pip")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    Label("Thêm video", systemImage: "plus")
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .disabled(model.videoOverlays.count >= 4)
            }
            Text("Video PIP chuyển động thật trong MP4. Tối đa 4 lớp video độc lập, hiện không trộn tiếng gốc PIP.")
                .font(.caption2).foregroundStyle(.secondary)

            ForEach(model.videoOverlays) { overlay in
                HStack(spacing: 8) {
                    Button {
                        selectedID = overlay.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "film.stack")
                            Text(overlay.filename).lineLimit(1)
                            Spacer()
                            if selectedID == overlay.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(8)
                        .background(selectedID == overlay.id ?
                            Color.cyan.opacity(0.16) : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        model.removeVideoOverlay(overlay.id)
                        selectedID = model.videoOverlays.first?.id
                    } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.bordered)
                }.font(.caption)
            }

            if let item = selected,
               let idx = model.videoOverlays.firstIndex(where: { $0.id == item.id }) {
                Divider()
                row("Bắt đầu", value: item.start)
                Slider(value: $model.videoOverlays[idx].start,
                       in: 0...max(0.1, model.totalDuration - 0.1),
                       step: 0.1).tint(.cyan)

                row("Thời lượng", value: item.duration)
                Slider(value: $model.videoOverlays[idx].duration,
                       in: 0.1...max(0.2, min(item.sourceDuration - item.sourceStart,
                                              model.totalDuration - item.start)),
                       step: 0.1).tint(.cyan)

                row("Kích thước", value: item.width * 100, suffix: "%")
                Slider(value: $model.videoOverlays[idx].width,
                       in: 0.10...0.95, step: 0.05).tint(.cyan)

                row("Độ mờ", value: item.opacity * 100, suffix: "%")
                Slider(value: $model.videoOverlays[idx].opacity,
                       in: 0.05...1, step: 0.05).tint(.cyan)

                Text("Tọa độ bắt đầu (X/Y)")
                    .font(.caption.bold())
                Slider(value: $model.videoOverlays[idx].startX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.videoOverlays[idx].startY,
                       in: 0.05...0.95, step: 0.01)

                Text("Tọa độ kết thúc (X/Y)")
                    .font(.caption.bold())
                Slider(value: $model.videoOverlays[idx].endX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.videoOverlays[idx].endY,
                       in: 0.05...0.95, step: 0.01)
                Button("Đứng yên (đặt điểm cuối = điểm đầu)") {
                    model.videoOverlays[idx].endX = item.startX
                    model.videoOverlays[idx].endY = item.startY
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }.padding(10)
    }

    private func row(_ label: String, value: Double,
                     suffix: String = "s") -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.1f%@", value, suffix))
                .monospacedDigit()
        }.font(.caption)
    }
}
