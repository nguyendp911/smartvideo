import SwiftUI

/// Reusable keyframe editor for video PIP and title tracks. Defaults to the
/// older start/end animation until the user creates a new keyframe.
struct MultiPointKeyframePanel: View {
    @Binding var keyframes: [OverlayKeyframe]
    @Binding var easing: OverlayEasing
    @Binding var pathMode: OverlayMotionPath

    let start: Double
    let duration: Double
    let timelineSecond: Double
    let legacyStart: OverlayKeyframe
    let legacyEnd: OverlayKeyframe
    let onScrub: (Double) -> Void

    @State private var selectedFrameID: UUID?

    private var displayed: [OverlayKeyframe] {
        keyframes.isEmpty ? [legacyStart, legacyEnd] : keyframes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Multi-Keyframe Pro", systemImage: "diamond.inset.filled")
                .font(.subheadline.bold())

            Text("Tối đa 16 mốc: vị trí, phóng to, xoay và độ mờ. " +
                 "Các mốc giữ tỷ lệ khi thay đổi thời lượng.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            presetStrip
            HStack(spacing: 7) {
                Button {
                    addAtPlayhead()
                } label: {
                    Label("Thêm tại con trỏ", systemImage: "plus.diamond")
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyframes.count >= 16)

                if !keyframes.isEmpty {
                    Button("Về hai điểm") {
                        keyframes = []
                        selectedFrameID = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption)

            if !keyframes.isEmpty {
                frameStrip
                frameEditor
            }

            Picker("Nội suy", selection: $easing) {
                ForEach(OverlayEasing.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)

            Picker("Đường chuyển động", selection: $pathMode) {
                ForEach(OverlayMotionPath.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .font(.caption)

            if keyframes.isEmpty {
                Text("Đang dùng chuyển động hai điểm cũ. " +
                     "Bấm Thêm tại con trỏ hoặc chọn hiệu ứng để bật nhiều mốc.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(Color.cyan.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 11))
    }

    private var presetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ImageKeyframePreset.allCases) { preset in
                    Button(preset.rawValue) {
                        keyframes = preset.makeFrames(
                            x: legacyStart.x, y: legacyStart.y,
                            scale: legacyStart.scale,
                            opacity: legacyStart.opacity
                        )
                        selectedFrameID = keyframes.first?.id
                        onScrub(start)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                }
            }
        }
    }

    private var frameStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keyframes) { frame in
                    Button {
                        selectedFrameID = frame.id
                        onScrub(start + frame.progress * duration)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "diamond.fill")
                            Text(String(format: "%.2fs",
                                frame.progress * duration))
                                .monospacedDigit()
                        }
                        .font(.system(size: 10))
                        .padding(6)
                        .foregroundStyle(selectedFrameID == frame.id ?
                                         Color.black : Color.cyan)
                        .background(
                            selectedFrameID == frame.id ?
                                Color.cyan : Color.cyan.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var frameEditor: some View {
        if let index = keyframes.firstIndex(where: {
            $0.id == selectedFrameID
        }) ?? keyframes.indices.first {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Mốc \(index + 1)/\(keyframes.count)")
                        .font(.caption.bold())
                    Spacer()
                    if index > 0 && index < keyframes.count - 1 {
                        Button(role: .destructive) {
                            keyframes.remove(at: index)
                            selectedFrameID = nil
                        } label: {
                            Label("Xóa mốc", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption2)
                    }
                }
                if index > 0 && index < keyframes.count - 1 {
                    let minimum = keyframes[index - 1].progress + 0.01
                    let maximum = keyframes[index + 1].progress - 0.01
                    if minimum < maximum {
                        Text(String(format: "Thời điểm: %.2fs",
                                    keyframes[index].progress * duration))
                            .font(.caption2)
                        Slider(value: $keyframes[index].progress,
                               in: minimum...maximum, step: 0.005)
                            .tint(.cyan)
                    }
                }
                TrackKeyframeValues(frame: $keyframes[index])
            }
        }
    }

    private func addAtPlayhead() {
        guard duration > 0.1 else { return }
        if keyframes.isEmpty {
            keyframes = [legacyStart, legacyEnd]
        }
        let p = min(0.985, max(0.015,
            (timelineSecond - start) / duration))
        if let nearby = keyframes.first(where: {
            abs($0.progress - p) < 0.015
        }) {
            selectedFrameID = nearby.id
            onScrub(start + nearby.progress * duration)
            return
        }
        guard keyframes.count < 16 else { return }
        var frame = OverlayKeyframeSampler.sample(
            frames: keyframes, easing: easing,
            path: pathMode, atProgress: p
        )
        frame.id = UUID()
        frame.progress = p
        keyframes.append(frame)
        keyframes.sort { $0.progress < $1.progress }
        selectedFrameID = frame.id
        onScrub(start + p * duration)
    }
}

private struct TrackKeyframeValues: View {
    @Binding var frame: OverlayKeyframe

    var body: some View {
        VStack(spacing: 7) {
            slider("X", value: $frame.x, limits: 0.03...0.97, percent: true)
            slider("Y", value: $frame.y, limits: 0.03...0.97, percent: true)
            slider("Kích thước", value: $frame.scale,
                   limits: 0.10...0.95, percent: true)
            slider("Độ mờ", value: $frame.opacity,
                   limits: 0...1, percent: true)
            slider("Góc xoay", value: $frame.rotationDegrees,
                   limits: -360...360, percent: false)
        }
    }

    private func slider(_ title: String, value: Binding<Double>,
                        limits: ClosedRange<Double>, percent: Bool) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: percent ? "%.0f%%" : "%.0f°",
                            value.wrappedValue * (percent ? 100 : 1)))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: limits)
                .tint(.cyan)
        }
    }
}
