import SwiftUI

/// Multi-point keyframe editor for an image overlay. Keyframes store
/// normalized time and render identically in the video exporter and preview.
struct OverlayKeyframeStudio: View {
    @ObservedObject var model: EditorViewModel
    let overlayID: UUID
    let onScrub: (Double) -> Void
    @State private var selectedFrameID: UUID?

    private var overlayIndex: Int? {
        model.imageOverlays.firstIndex { $0.id == overlayID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Keyframe Pro · Nhiều điểm chuyển động",
                  systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.bold())

            Text("Tạo nhiều mốc để điều khiển vị trí, zoom, xoay và độ mờ. " +
                 "Mỗi mốc bám theo thời lượng Overlay, không làm thay đổi ảnh gốc.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let index = overlayIndex {
                presetButtons(index)
                actionButtons(index)

                if !model.imageOverlays[index].keyframes.isEmpty {
                    framesList(index)
                    frameControls(index)
                    Picker("Gia tốc giữa các mốc",
                           selection: $model.imageOverlays[index].easing) {
                        ForEach(OverlayEasing.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .font(.caption)
                    .pickerStyle(.menu)
                } else {
                    Text("Chưa bật chế độ nhiều điểm. Vị trí đầu/cuối " +
                         "đang hoạt động như các phiên bản trước.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.cyan.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 11))
    }

    private func presetButtons(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Mẫu chuyển động")
                .font(.caption.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(ImageKeyframePreset.allCases) { preset in
                        Button(preset.rawValue) {
                            model.applyImageKeyframePreset(
                                overlayID, preset: preset
                            )
                            selectedFrameID = model.imageOverlays[index]
                                .keyframes.first?.id
                            onScrub(model.imageOverlays[index].start)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func actionButtons(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedFrameID = model.addImageOverlayKeyframe(
                    overlayID, atTimeline: model.timelineSecond
                )
            } label: {
                Label("Thêm tại con trỏ", systemImage: "plus.diamond")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.imageOverlays[index].keyframes.count >= 16)

            if !model.imageOverlays[index].keyframes.isEmpty {
                Button("Về 2 điểm") {
                    model.clearImageKeyframes(overlayID)
                    selectedFrameID = nil
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.caption)
    }

    private func framesList(_ index: Int) -> some View {
        let overlay = model.imageOverlays[index]
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(overlay.keyframes.count) mốc chuyển động · tối đa 16")
                .font(.caption.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(overlay.keyframes) { frame in
                        Button {
                            selectedFrameID = frame.id
                            onScrub(overlay.start +
                                    frame.progress * overlay.duration)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "diamond.fill")
                                    .font(.caption)
                                Text(String(format: "%.2fs",
                                    frame.progress * overlay.duration))
                                    .monospacedDigit()
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(selectedFrameID == frame.id ?
                                             Color.black : Color.cyan)
                            .padding(7)
                            .background(
                                selectedFrameID == frame.id ?
                                    Color.cyan : Color.cyan.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func frameControls(_ index: Int) -> some View {
        let frames = model.imageOverlays[index].keyframes
        if let keyIndex = frames.firstIndex(where: {
            $0.id == selectedFrameID
        }) ?? frames.indices.first {
            let frame = frames[keyIndex]
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Đang sửa mốc \(keyIndex + 1)")
                        .font(.caption.bold())
                    Spacer()
                    if keyIndex > 0 && keyIndex < frames.count - 1 {
                        Button(role: .destructive) {
                            model.removeImageOverlayKeyframe(
                                overlayID, frameID: frame.id
                            )
                            selectedFrameID = nil
                        } label: {
                            Label("Xóa mốc", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption2)
                    }
                }
                if keyIndex > 0 && keyIndex < frames.count - 1 {
                    let minimum = frames[keyIndex - 1].progress + 0.01
                    let maximum = frames[keyIndex + 1].progress - 0.01
                    if minimum < maximum {
                        HStack {
                            Text("Vị trí trên đoạn")
                            Spacer()
                            Text(String(format: "%.2fs",
                                frame.progress *
                                model.imageOverlays[index].duration))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        Slider(
                            value: $model.imageOverlays[index]
                                .keyframes[keyIndex].progress,
                            in: minimum...maximum, step: 0.005
                        )
                        .tint(.cyan)
                    }
                }
                OverlayKeyframeValues(
                    frame: $model.imageOverlays[index]
                        .keyframes[keyIndex]
                )
            }
        }
    }
}

private struct OverlayKeyframeValues: View {
    @Binding var frame: OverlayKeyframe

    var body: some View {
        VStack(spacing: 7) {
            valueSlider("Vị trí ngang", value: $frame.x,
                        range: 0.03...0.97, format: "%.0f%%", multiplier: 100)
            valueSlider("Vị trí dọc", value: $frame.y,
                        range: 0.03...0.97, format: "%.0f%%", multiplier: 100)
            valueSlider("Kích thước", value: $frame.scale,
                        range: 0.1...0.95, format: "%.0f%%", multiplier: 100)
            valueSlider("Độ mờ", value: $frame.opacity,
                        range: 0...1, format: "%.0f%%", multiplier: 100)
            valueSlider("Góc xoay", value: $frame.rotationDegrees,
                        range: -360...360, format: "%.0f°", multiplier: 1)
        }
    }

    private func valueSlider(
        _ name: String, value: Binding<Double>,
        range: ClosedRange<Double>, format: String, multiplier: Double
    ) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(name)
                Spacer()
                Text(String(format: format, value.wrappedValue * multiplier))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: range)
                .tint(.cyan)
        }
    }
}
