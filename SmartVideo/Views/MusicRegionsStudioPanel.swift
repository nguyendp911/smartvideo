import SwiftUI

/// Music-region editor. Each region is a non-destructive EDL using the
/// existing SoundEffectClip data layout, but mixed on separate music tracks.
struct MusicRegionsStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let importAudio: () -> Void
    let onScrub: (Double) -> Void

    @State private var selectedFrameID: UUID?

    private var selected: SoundEffectClip? {
        model.musicRegions.first(where: { $0.id == selectedID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Multi-Music Studio", systemImage: "music.note.list")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(model.musicRegions.count)/12")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Một nhạc nền") {
                    model.selectMusicRegionMode(false)
                }
                .buttonStyle(.bordered)
                .tint(model.musicRegionMode ? .gray : .green)
                Button("Nhiều đoạn nhạc") {
                    model.selectMusicRegionMode(true)
                }
                .buttonStyle(.bordered)
                .tint(model.musicRegionMode ? .green : .gray)
            }
            .font(.caption)
            .tint(.green)

            if model.musicRegionMode {
                Text("Mỗi đoạn nhạc phát độc lập. Nhạc nền một bài được giữ trong dự án nhưng không phát đồng thời, tránh lồng tiếng gấp đôi.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button(action: importAudio) {
                        Label("Nhập MP3", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isImportingMusicRegion ||
                              model.musicRegions.count >= 12 ||
                              model.clips.isEmpty)
                    if model.musicURL != nil {
                        Button {
                            if let id = model.addCurrentMusicAsRegion() {
                                selectedID = id
                            }
                        } label: {
                            Label("Từ nhạc nền", systemImage: "music.note")
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.musicRegions.count >= 12)
                    }
                    Button {
                        if let id = model.pasteMusicRegionAtPlayhead() {
                            selectedID = id
                        }
                    } label: {
                        Label("Dán", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.musicRegions.count >= 12)
                }
                .font(.caption2)
                if model.isImportingMusicRegion {
                    ProgressView("Đang nhập và kiểm tra nhạc…")
                        .font(.caption2)
                }

                if model.musicRegions.isEmpty {
                    Text("Chưa có đoạn nhạc. Chọn Nhập MP3 hoặc Từ nhạc nền để bắt đầu.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ForEach(model.musicRegions) { region in
                    HStack(spacing: 5) {
                        Button {
                            selectedID = region.id
                            selectedFrameID = nil
                            onScrub(region.start)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: region.muted ?
                                      "speaker.slash" : "music.note")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(region.filename)
                                        .font(.caption.bold())
                                        .lineLimit(1)
                                    Text(String(format: "%.1fs – %.1fs",
                                                region.start, region.end))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if selectedID == region.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(7)
                            .background(
                                selectedID == region.id ?
                                    Color.green.opacity(0.18) :
                                    Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            model.removeMusicRegion(region.id)
                            if selectedID == region.id {
                                selectedID = model.musicRegions.first?.id
                                selectedFrameID = nil
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let selected {
                    controls(selected)
                }
            }
        }
        .onAppear {
            if selectedID == nil {
                selectedID = model.musicRegions.first?.id
            }
        }
        .onChange(of: selectedID) { _ in
            selectedFrameID = nil
        }
    }

    private func trimStart(_ id: UUID) -> Binding<Double> {
        Binding {
            model.musicRegions.first(where: { $0.id == id })?
                .sourceStart ?? 0
        } set: { newValue in
            guard let index = model.musicRegions.firstIndex(where: {
                $0.id == id
            }) else { return }
            let original = model.musicRegions[index]
            let end = original.sourceStart + original.duration
            let start = min(max(0, newValue), max(0, end - 0.1))
            model.musicRegions[index].sourceStart = start
            model.musicRegions[index].duration = max(0.1, end - start)
        }
    }

    private func trimEnd(_ id: UUID) -> Binding<Double> {
        Binding {
            guard let region = model.musicRegions.first(where: {
                $0.id == id
            }) else { return 0 }
            return region.sourceStart + region.duration
        } set: { newValue in
            guard let index = model.musicRegions.firstIndex(where: {
                $0.id == id
            }) else { return }
            let original = model.musicRegions[index]
            let maxEnd = min(original.originalDuration,
                             original.sourceStart +
                             max(0.1, model.totalDuration - original.start))
            let end = min(maxEnd, max(original.sourceStart + 0.1,
                                      newValue))
            model.musicRegions[index].duration = max(
                0.1, end - original.sourceStart
            )
        }
    }

    @ViewBuilder
    private func controls(_ region: SoundEffectClip) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text("Chỉnh đoạn nhạc đã chọn")
                .font(.subheadline.bold())

            AudioWaveformTrimView(
                url: region.fileURL,
                sourceDuration: region.originalDuration,
                trimStart: trimStart(region.id),
                trimEnd: trimEnd(region.id),
                title: "Cắt đầu/cuối nguồn theo sóng âm",
                playheadSource: model.timelineSecond >= region.start &&
                    model.timelineSecond <= region.end ?
                    region.sourceStart + model.timelineSecond -
                        region.start : nil,
                onEditBegan: { model.beginSoundEffectsEdit() }
            )

            HStack(spacing: 5) {
                Button {
                    model.copyMusicRegion(region.id)
                } label: {
                    Label("Sao chép", systemImage: "doc.on.doc")
                }
                Button {
                    if let id = model.duplicateMusicRegion(region.id) {
                        selectedID = id
                    }
                } label: {
                    Label("Nhân bản", systemImage: "plus.square.on.square")
                }
                .disabled(model.musicRegions.count >= 12)
                Button {
                    if let id = model.splitMusicRegionAtPlayhead(
                        region.id
                    ) {
                        selectedID = id
                    }
                } label: {
                    Label("Tách tại con trỏ", systemImage: "scissors")
                }
                .disabled(model.musicRegions.count >= 12 ||
                          model.timelineSecond < region.start + 0.1 ||
                          model.timelineSecond > region.end - 0.1)
            }
            .font(.caption2)
            .buttonStyle(.bordered)

            HStack {
                Text("Vị trí trên video")
                Spacer()
                Text(String(format: "%.2fs", region.start))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(
                value: Binding(
                    get: {
                        model.musicRegions.first(where: {
                            $0.id == region.id
                        })?.start ?? 0
                    },
                    set: {
                        model.moveMusicRegion(
                            region.id, to: $0, recordUndo: false
                        )
                    }
                ),
                in: 0...max(0.1, model.totalDuration - 0.1),
                step: 0.05,
                onEditingChanged: { editing in
                    if editing { model.beginSoundEffectsEdit() }
                }
            ).tint(.green)

            HStack {
                Text("Âm lượng đoạn")
                Spacer()
                Text("\(Int(region.volume * 100))%")
                    .monospacedDigit()
            }.font(.caption)
            Slider(value: Binding(
                get: {
                    Double(model.musicRegions.first(where: {
                        $0.id == region.id
                    })?.volume ?? 0.38)
                },
                set: {
                    guard let index = model.musicRegions.firstIndex(
                        where: { $0.id == region.id }
                    ) else { return }
                    model.musicRegions[index].volume =
                        AudioAutomationMath.clampGain(Float($0))
                }
            ), in: 0...1, step: 0.05,
               onEditingChanged: { editing in
                   if editing { model.beginSoundEffectsEdit() }
               })
                .tint(.green)

            Toggle("Tắt tiếng đoạn này", isOn: Binding(
                get: {
                    model.musicRegions.first(where: {
                        $0.id == region.id
                    })?.muted ?? false
                },
                set: { value in
                    guard let index = model.musicRegions.firstIndex(
                        where: { $0.id == region.id }
                    ) else { return }
                    model.beginSoundEffectsEdit()
                    model.musicRegions[index].muted = value
                }
            ))
            .font(.caption)

            ForEach([true, false], id: \.self) { fadeIn in
                let seconds = fadeIn ? region.fadeIn : region.fadeOut
                HStack {
                    Text(fadeIn ? "Fade vào" : "Fade ra")
                    Spacer()
                    Text(String(format: "%.2fs", seconds))
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(
                    value: Binding(
                        get: {
                            guard let entry = model.musicRegions.first(
                                where: { $0.id == region.id }
                            ) else { return 0 }
                            return fadeIn ? entry.fadeIn : entry.fadeOut
                        },
                        set: { value in
                            guard let index = model.musicRegions.firstIndex(
                                where: { $0.id == region.id }
                            ) else { return }
                            if fadeIn {
                                model.musicRegions[index].fadeIn =
                                    min(3, max(0, value))
                            } else {
                                model.musicRegions[index].fadeOut =
                                    min(3, max(0, value))
                            }
                        }
                    ),
                    in: 0...3, step: 0.05,
                    onEditingChanged: { editing in
                        if editing { model.beginSoundEffectsEdit() }
                    }
                ).tint(.green)
            }

            Divider()
            HStack {
                Label("Keyframe âm lượng", systemImage: "waveform.path.ecg")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(region.volumeKeyframes.count)/16")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            AudioGainCurveView(
                frames: region.volumeKeyframes,
                selectedID: selectedFrameID,
                playheadProgress: (model.timelineSecond - region.start) /
                    max(0.1, region.duration),
                onSelect: { selectedFrameID = $0 }
            )
            Button {
                if let keyID = model.addMusicRegionKeyframe(region.id) {
                    selectedFrameID = keyID
                }
            } label: {
                Label("Thêm mốc tại con trỏ",
                      systemImage: "plus.diamond.fill")
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .disabled(model.timelineSecond < region.start ||
                      model.timelineSecond > region.end ||
                      region.volumeKeyframes.count >= 16)

            if let frame = region.volumeKeyframes.first(where: {
                $0.id == selectedFrameID
            }) {
                HStack {
                    Text(String(format: "Mốc %.2fs",
                        region.start + frame.progress * region.duration))
                    Spacer()
                    Text("\(Int(frame.gain * 100))%")
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(
                    value: Binding(
                        get: {
                            Double(model.musicRegions.first(where: {
                                $0.id == region.id
                            })?.volumeKeyframes.first(where: {
                                $0.id == frame.id
                            })?.gain ?? 1)
                        },
                        set: {
                            model.moveMusicRegionKeyframe(
                                region.id, frameID: frame.id,
                                progress: frame.progress, gain: Float($0)
                            )
                        }
                    ), in: 0...1, step: 0.05,
                    onEditingChanged: { editing in
                        if editing { model.beginSoundEffectsEdit() }
                    }
                ).tint(.orange)
                Button(role: .destructive) {
                    model.deleteMusicRegionKeyframe(
                        region.id, frameID: frame.id
                    )
                    selectedFrameID = nil
                } label: {
                    Label("Xóa mốc", systemImage: "trash")
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
            Text("Kéo đoạn màu xanh lá trên timeline để đổi thời điểm. Keyframe được áp dụng cho cả preview và MP4; các file nhạc gốc không bị thay đổi.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
