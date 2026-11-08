import SwiftUI
import PhotosUI

/// Controls for an independent, movable image/PIP layer.
/// Motion uses a start and an end position (two keyframes).
struct OverlayStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedOverlayID: UUID?
    @Binding var pickedOverlay: PhotosPickerItem?

    private var selected: ImageOverlayClip? {
        model.imageOverlays.first(where: { $0.id == selectedOverlayID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Overlay · Picture-in-Picture", systemImage: "square.on.square")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $pickedOverlay, matching: .images) {
                    Label("Thêm ảnh", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
            Text("Đặt ảnh phía trên clip. Kéo trực tiếp trên preview để đổi điểm bắt đầu; điều chỉnh điểm kết thúc để tạo chuyển động.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if model.imageOverlays.isEmpty {
                Text("Chưa có overlay. Chọn một hình ảnh PNG/JPG từ thư viện.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.imageOverlays) { item in
                        Button {
                            selectedOverlayID = item.id
                        } label: {
                            Text(item.filename)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(maxWidth: 110)
                                .padding(7)
                                .background(
                                    selectedOverlayID == item.id ?
                                        Color.cyan.opacity(0.30) :
                                        Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let item = selected,
               let index = model.imageOverlays.firstIndex(where: { $0.id == item.id }) {
                HStack {
                    Text("Đang chọn: \(item.filename)")
                        .font(.caption.bold())
                        .lineLimit(1)
                    Spacer()
                    Button(role: .destructive) {
                        model.removeImageOverlay(item.id)
                        selectedOverlayID = model.imageOverlays.first?.id
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                let total = max(0.3, model.totalDuration)
                let maxStart = max(0, total - 0.2)
                HStack {
                    Text("Bắt đầu")
                    Spacer()
                    Text(String(format: "%.1fs", item.start)).monospacedDigit()
                }.font(.caption)
                Slider(value: $model.imageOverlays[index].start,
                       in: 0...max(0.1, maxStart), step: 0.1)
                    .tint(.cyan)

                HStack {
                    Text("Thời lượng")
                    Spacer()
                    Text(String(format: "%.1fs", item.duration)).monospacedDigit()
                }.font(.caption)
                Slider(value: $model.imageOverlays[index].duration,
                       in: 0.2...max(0.3, total - item.start), step: 0.1)
                    .tint(.cyan)

                HStack {
                    Text("Kích thước")
                    Spacer()
                    Text("\(Int(item.scale * 100))%")
                }.font(.caption)
                Slider(value: $model.imageOverlays[index].scale,
                       in: 0.1...0.95, step: 0.05).tint(.cyan)

                HStack {
                    Text("Độ mờ")
                    Spacer()
                    Text("\(Int(item.opacity * 100))%")
                }.font(.caption)
                Slider(value: $model.imageOverlays[index].opacity,
                       in: 0.05...1, step: 0.05).tint(.cyan)

                HStack {
                    Text("Xoay")
                    Spacer()
                    Text("\(Int(item.rotationDegrees))°")
                }.font(.caption)
                Slider(value: $model.imageOverlays[index].rotationDegrees,
                       in: -180...180, step: 5).tint(.cyan)

                Divider()
                Text("Keyframe: vị trí bắt đầu và kết thúc")
                    .font(.caption.bold())
                HStack {
                    Button("Giữa") { move(index, x: 0.5, y: 0.5) }
                    Button("Góc trái") { move(index, x: 0.25, y: 0.25) }
                    Button("Góc phải") { move(index, x: 0.75, y: 0.25) }
                }
                .font(.caption2)
                .buttonStyle(.bordered)

                Text("Vị trí ban đầu: X \(Int(item.startX * 100))%, Y \(Int(item.startY * 100))%")
                    .font(.caption2)
                Slider(value: $model.imageOverlays[index].startX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.imageOverlays[index].startY,
                       in: 0.05...0.95, step: 0.01)

                Toggle("Chuyển động (2 keyframe)",
                       isOn: Binding(
                        get: { abs(item.startX - item.endX) +
                               abs(item.startY - item.endY) > 0.01 },
                        set: { enabled in
                            if enabled {
                                model.imageOverlays[index].endX =
                                    min(0.95, model.imageOverlays[index].startX + 0.2)
                                model.imageOverlays[index].endY =
                                    min(0.95, model.imageOverlays[index].startY + 0.2)
                            } else {
                                model.imageOverlays[index].endX =
                                    model.imageOverlays[index].startX
                                model.imageOverlays[index].endY =
                                    model.imageOverlays[index].startY
                            }
                        }
                       )).font(.caption)
                Text("Vị trí cuối: X \(Int(item.endX * 100))%, Y \(Int(item.endY * 100))%")
                    .font(.caption2)
                Slider(value: $model.imageOverlays[index].endX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.imageOverlays[index].endY,
                       in: 0.05...0.95, step: 0.01)

                Text("Overlay được ghi vào MP4, trên VFX và dưới phụ đề. Mới hỗ trợ lớp ảnh, chưa hỗ trợ overlay video hoặc nhiều keyframe phức tạp.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private func move(_ index: Int, x: Double, y: Double) {
        model.imageOverlays[index].startX = x
        model.imageOverlays[index].startY = y
        model.imageOverlays[index].endX = x
        model.imageOverlays[index].endY = y
    }
}
