import SwiftUI

/// Five-point nonlinear retiming presets and source-relative speed keyframes.
/// Every slider edits actual AVFoundation retiming parameters, not a UI-only
/// animation. The original file is left intact.
struct SpeedCurveStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let clip: TimelineClip

    private var isCustomCurve: Bool {
        guard !clip.speedCurve.isEmpty else { return false }
        return ![SpeedCurvePreset.montage, .hero, .flash]
            .contains { clip.speedCurve == $0.points }
    }

    private func isActive(_ preset: SpeedCurvePreset) -> Bool {
        switch preset {
        case .none: return clip.speedCurve.isEmpty
        case .custom: return isCustomCurve
        default: return clip.speedCurve == preset.points
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Speed Curve", systemImage: "waveform.path")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "%.2fs", clip.renderedDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SpeedCurvePreset.allCases) { preset in
                        Button {
                            model.applySpeedCurve(preset, to: clip.id)
                        } label: {
                            Text(preset.rawValue)
                                .font(.caption.bold())
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .foregroundStyle(isActive(preset) ? .black : .white)
                                .background(
                                    isActive(preset)
                                        ? Color.cyan : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !clip.speedCurve.isEmpty {
                Text("Điều chỉnh 5 mốc tốc độ theo thứ tự từ đầu đến cuối clip")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(clip.speedCurve.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text("\(Int((clip.speedCurve[index].position * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 37, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: {
                                    guard let current = model.clips.first(
                                        where: { $0.id == clip.id }
                                    ), current.speedCurve.indices.contains(index)
                                    else { return 1 }
                                    return current.speedCurve[index].speed
                                },
                                set: { speed in
                                    model.changeSpeedCurveNode(
                                        clip.id, at: index, to: speed
                                    )
                                }
                            ),
                            in: SpeedCurveMath.minSpeed...SpeedCurveMath.maxSpeed,
                            step: 0.05,
                            onEditingChanged: { editing in
                                if editing { model.beginSpeedCurveEdit() }
                            }
                        )
                        .tint(.cyan)

                        Text(String(format: "%.2fx",
                                    clip.speedCurve[index].speed))
                            .font(.caption.monospacedDigit())
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Text("Thấp hơn 1× là chậm, cao hơn 1× là nhanh. Tốc độ được nội suy theo các mốc; khi xuất, AVFoundation chia thành nhiều khoảng ngắn để thay đổi tốc độ.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Chọn Montage, Hero, Flash hoặc Tùy chỉnh để tạo tốc độ thay đổi trong cùng một clip.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text("Speed Curve không tạo khung hình mới bằng optical flow; các video chậm có thể giật nếu FPS nguồn thấp.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
