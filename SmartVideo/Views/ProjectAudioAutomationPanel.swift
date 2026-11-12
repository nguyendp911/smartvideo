import SwiftUI

/// Music and narration each have independent 16-point gain automation.
/// The same project seconds and gain values are used by live preview and MP4.
struct ProjectAudioAutomationPanel: View {
    @ObservedObject var model: EditorViewModel
    let lane: ProjectAudioLane
    @State private var selectedID: UUID?

    private var start: Double { model.projectAudioStart(lane) }
    private var duration: Double { model.projectAudioDuration(lane) }
    private var frames: [AudioGainKeyframe] {
        model.projectAudioFrames(lane)
    }
    private var laneLabel: String {
        lane == .music ? "Nhạc nền" : "Thuyết minh"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            HStack {
                Label("Keyframe · " + laneLabel,
                      systemImage: "waveform.path.ecg")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(frames.count)/16")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Vị trí trên video")
                Spacer()
                Text(String(format: "%.2fs", start))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: Binding(
                get: { model.projectAudioStart(lane) },
                set: {
                    model.projectAudioMove(lane, to: $0,
                                           recordUndo: false)
                }
            ), in: 0...max(0.1, model.totalDuration - 0.1),
               step: 0.05, onEditingChanged: { editing in
                   if editing { model.beginSoundEffectsEdit() }
               })
                .tint(.cyan)

            AudioGainCurveView(
                frames: frames,
                selectedID: selectedID,
                playheadProgress: (model.timelineSecond - start) /
                    max(0.1, duration),
                onSelect: { selectedID = $0 }
            )
            HStack(spacing: 8) {
                Button {
                    if let id = model.addProjectAudioKeyframe(lane) {
                        selectedID = id
                    }
                } label: {
                    Label("Thêm mốc tại con trỏ",
                          systemImage: "plus.diamond.fill")
                }
                .disabled(duration < 0.1 || frames.count >= 16 ||
                    model.timelineSecond < start ||
                    model.timelineSecond > start + duration)
                if !frames.isEmpty {
                    Button("Xóa tất cả") {
                        model.clearProjectAudioKeyframes(lane)
                        selectedID = nil
                    }
                    .tint(.orange)
                }
            }
            .font(.caption2)
            .buttonStyle(.bordered)

            if let selectedID,
               let frame = frames.first(where: { $0.id == selectedID }) {
                HStack {
                    Text(String(format: "Mốc %.2fs",
                                start + frame.progress * duration))
                    Spacer()
                    Text("\(Int(frame.gain * 100))%")
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(value: Binding(
                    get: {
                        Double(model.projectAudioFrames(lane)
                            .first(where: { $0.id == selectedID })?.gain ?? 1)
                    },
                    set: { value in
                        model.moveProjectAudioKeyframe(
                            lane, id: selectedID,
                            progress: frame.progress, gain: Float(value)
                        )
                    }
                ), in: 0...1, step: 0.05,
                   onEditingChanged: { editing in
                       if editing { model.beginSoundEffectsEdit() }
                   })
                    .tint(.orange)
                Button(role: .destructive) {
                    model.removeProjectAudioKeyframe(
                        lane, id: selectedID
                    )
                    self.selectedID = nil
                } label: {
                    Label("Xóa mốc đang chọn", systemImage: "trash")
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
            Text("Kéo nhạc hoặc giọng đọc trên timeline mở rộng. Thêm mốc khi con trỏ ở trong track; chạm chấm cam để chỉnh âm lượng. Mốc được lưu vào dự án và áp dụng khi xuất MP4.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
