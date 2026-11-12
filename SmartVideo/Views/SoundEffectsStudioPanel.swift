import SwiftUI
import AVFoundation

/// Compact CapCut-style sound effects workspace. A multi-track SFX layer
/// stays separate from background music and voiceover.
struct SoundEffectsStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let importAudio: () -> Void
    @State private var previewPlayer: AVAudioPlayer?
    @State private var mixPlayer: AVPlayer?
    @State private var isPreparingMix = false
    @State private var selectedKeyframeID: UUID?

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return model.soundEffects.firstIndex(where: { $0.id == selectedID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Thư viện hiệu ứng âm thanh", systemImage: "waveform.badge.plus")
                    .font(.headline)
                Spacer()
                Button(action: importAudio) {
                    Label("Nhập tệp", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .disabled(model.soundEffects.count >= 12)
            }

            Text("Hiệu ứng âm thanh có track riêng. Chạm mốc trên timeline để đặt âm, hoặc chọn từng track rồi chỉnh vị trí phát.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 7),
                GridItem(.flexible(), spacing: 7),
                GridItem(.flexible(), spacing: 7)
            ], spacing: 7) {
                ForEach(BuiltInSoundEffect.allCases) { preset in
                    Button {
                        model.addBuiltInSound(preset)
                        selectedID = model.soundEffects.last?.id
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: preset.symbol)
                                .font(.title3)
                            Text(preset.rawValue)
                                .font(.caption2.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cyan.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.soundEffects.count >= 12 ||
                              model.clips.isEmpty)
                }
            }

            Divider()
            HStack {
                Label("Beat Sync · Phối âm", systemImage: "metronome")
                    .font(.subheadline.bold())
                Spacer()
                if model.detectedTempoBPM > 0 {
                    Text(String(format: "~%.0f BPM", model.detectedTempoBPM))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.cyan)
                }
            }

            HStack(spacing: 7) {
                Button {
                    model.analyzeMusicBeats()
                } label: {
                    Label(model.isDetectingBeats ? "Đang phân tích..." :
                          "Phân tích nhịp MP3", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.musicURL == nil || model.isDetectingBeats)

                Button {
                    model.snapAllSoundsToBeats()
                } label: {
                    Label("Căn tất cả FX", systemImage: "magnet")
                }
                .buttonStyle(.bordered)
                .disabled(model.timelineBeatMarkers.isEmpty ||
                          model.soundEffects.isEmpty)
            }
            .font(.caption)

            if model.isDetectingBeats {
                ProgressView("Đang phân tích năng lượng âm thanh…")
                    .font(.caption2)
            }

            if !model.timelineBeatMarkers.isEmpty {
                HStack {
                    Text("\(model.timelineBeatMarkers.count) mốc nhịp")
                        .font(.caption2)
                    Spacer()
                    Text("Ước lượng từ tín hiệu, có thể sai nhịp")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                BeatTimelineStrip(beatPositions: model.timelineBeatMarkers,
                                  totalDuration: model.totalDuration)
                    .frame(height: 28)
            } else if model.musicURL == nil {
                Text("Chọn nhạc nền trong tab Âm thanh để phân tích nhịp.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    if mixPlayer != nil {
                        mixPlayer?.pause()
                        mixPlayer = nil
                    } else {
                        playMixedAudio()
                    }
                } label: {
                    Label(mixPlayer == nil ?
                          (isPreparingMix ? "Đang chuẩn bị..." : "Nghe bản phối") :
                          "Dừng bản phối",
                          systemImage: mixPlayer == nil ?
                              "play.circle.fill" : "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparingMix || (
                    model.soundEffects.isEmpty &&
                    (model.musicRegionMode ?
                        model.musicRegions.isEmpty :
                        model.musicURL == nil) &&
                    model.voiceoverURL == nil
                ))
            }
            Text("Nghe thử bản phối từ con trỏ: MP3 + giọng thuyết minh + SFX. Chưa bao gồm tiếng gốc video và ducking nên kết quả cuối vẫn cần kiểm tra MP4.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Text("Track âm thanh")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(model.soundEffects.count)/12")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if model.soundEffects.isEmpty {
                Text("Chưa có hiệu ứng. Thêm âm thanh mẫu hoặc nhập MP3, M4A, WAV từ Tệp.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.soundEffects) { item in
                HStack(spacing: 7) {
                    Button {
                        selectedID = item.id
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: item.muted ?
                                  "speaker.slash" : "waveform")
                                .foregroundStyle(item.muted ? .orange : .cyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.filename)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                Text(String(format: "%.1fs → %.1fs",
                                            item.start, item.end))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedID == item.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .padding(7)
                        .background(selectedID == item.id ?
                            Color.cyan.opacity(0.15) : Color.white.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        previewPlayer?.stop()
                        model.removeSoundEffect(item.id)
                        selectedID = model.soundEffects.first?.id
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let index = selectedIndex,
               model.soundEffects.indices.contains(index) {
                editorForSelected(index)
            }

            Text("SFX có thể phát chồng lên nhạc nền, giọng đọc và tiếng video. Bộ nghe thử bản phối chưa gồm tiếng gốc clip; khi xuất MP4, track gốc vẫn theo tùy chọn Giữ tiếng gốc.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .onAppear {
            if selectedID == nil {
                selectedID = model.soundEffects.first?.id
            }
        }
        .onChange(of: selectedID) { _ in
            selectedKeyframeID = nil
        }
        .onDisappear {
            previewPlayer?.stop()
            mixPlayer?.pause()
            mixPlayer = nil
        }
    }

    private func playMixedAudio() {
        guard !isPreparingMix else { return }
        previewPlayer?.stop()
        isPreparingMix = true
        let duration = model.totalDuration
        let music = model.musicRegionMode ? nil : model.musicURL
        let regions = model.musicRegionMode ? model.musicRegions : []
        let voice = model.voiceoverURL
        let effects = model.soundEffects
        let start = model.musicStartSeconds
        let timelineOffset = model.musicTimelineOffset
        let musicFrames = model.musicVolumeKeyframes
        let voiceFrames = model.voiceVolumeKeyframes
        let highlight = model.musicHighlightDuration
        let repeatMusic = model.repeatShortMusic
        let musicVolume = model.musicVolume
        let musicFadeIn = model.musicFadeIn
        let musicFadeOut = model.musicFadeOut
        let voiceStart = model.voiceoverOffset
        let voiceVolume = model.voiceoverVolume
        let playhead = model.timelineSecond
        Task {
            defer { isPreparingMix = false }
            do {
                let item = try await AudioMixPreviewComposer.makeItem(
                    duration: duration,
                    musicURL: music,
                    musicStart: start,
                    musicTimelineOffset: timelineOffset,
                    musicHighlightDuration: highlight,
                    repeatMusic: repeatMusic,
                    musicVolume: musicVolume,
                    musicVolumeKeyframes: musicFrames,
                    musicFadeIn: musicFadeIn,
                    musicFadeOut: musicFadeOut,
                    narrationURL: voice,
                    narrationStart: voiceStart,
                    narrationVolume: voiceVolume,
                    voiceVolumeKeyframes: voiceFrames,
                    musicRegions: regions,
                    effects: effects
                )
                try AVAudioSession.sharedInstance().setCategory(
                    .playback, mode: .default,
                    options: [.mixWithOthers]
                )
                let player = AVPlayer(playerItem: item)
                mixPlayer = player
                await player.seek(
                    to: CMTime(seconds: min(playhead, duration),
                               preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                player.play()
            } catch {
                model.errorText = "Không nghe được bản phối: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private func editorForSelected(_ index: Int) -> some View {
        let item = model.soundEffects[index]
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text("Chỉnh track đã chọn")
                .font(.subheadline.bold())
            AudioWaveformTrimView(
                url: item.fileURL,
                sourceDuration: item.originalDuration,
                trimStart: sfxTrimStart(item.id),
                trimEnd: sfxTrimEnd(item.id),
                title: "Waveform · kéo để cắt nguồn",
                playheadSource: model.timelineSecond >= item.start &&
                    model.timelineSecond <= item.end ?
                    item.sourceStart + model.timelineSecond - item.start : nil,
                onEditBegan: { model.beginSoundEffectsEdit() }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        do {
                            if previewPlayer?.isPlaying == true {
                            previewPlayer?.stop()
                        }
                        let player = try AVAudioPlayer(
                            contentsOf: item.fileURL
                        )
                        player.currentTime = min(
                            max(0, item.sourceStart), player.duration
                        )
                        player.volume = item.muted ? 0 : item.volume
                        player.play()
                        previewPlayer = player
                    } catch {
                        model.errorText = "Không phát được SFX: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Nghe thử", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    _ = model.snapSoundToNearestBeat(item.id)
                } label: {
                    Label("Căn nhịp", systemImage: "metronome")
                }
                .buttonStyle(.bordered)
                .disabled(model.timelineBeatMarkers.isEmpty)

                Button {
                    model.moveSoundEffectToPlayhead(item.id)
                } label: {
                    Label("Đặt tại con trỏ", systemImage: "scope")
                }
                .buttonStyle(.bordered)

                Button {
                    if let created = model.duplicateSoundEffect(item.id) {
                        selectedID = created
                    }
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .disabled(model.soundEffects.count >= 12)
                }
                .font(.caption)
            }

            HStack {
                Text("Vị trí phát")
                Spacer()
                Text(String(format: "%.2fs", item.start)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].start,
                   in: 0...max(0.1, model.totalDuration - 0.1),
                   step: 0.05, onEditingChanged: { editing in
                       if editing { model.beginSoundEffectsEdit() }
                   }).tint(.cyan)

            HStack {
                Text("Cắt đầu nguồn")
                Spacer()
                Text(String(format: "%.2fs", item.sourceStart)).monospacedDigit()
            }.font(.caption)
            Slider(value: Binding(
                get: { model.soundEffects[index].sourceStart },
                set: { newStart in
                    model.soundEffects[index].sourceStart = newStart
                    let remain = max(0.1, item.originalDuration - newStart)
                    model.soundEffects[index].duration =
                        min(model.soundEffects[index].duration, remain)
                }
            ), in: 0...max(0.1, item.originalDuration - 0.1),
               step: 0.05, onEditingChanged: { editing in
                   if editing { model.beginSoundEffectsEdit() }
               }).tint(.cyan)

            HStack {
                Text("Thời lượng phát")
                Spacer()
                Text(String(format: "%.2fs", item.duration)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].duration,
                   in: 0.1...max(0.2, min(
                    item.originalDuration - item.sourceStart,
                    model.totalDuration - item.start
                   )), step: 0.05, onEditingChanged: { editing in
                       if editing { model.beginSoundEffectsEdit() }
                   }).tint(.cyan)

            HStack {
                Text("Âm lượng")
                Spacer()
                Text("\(Int(item.volume * 100))%")
            }.font(.caption)
            Slider(value: $model.soundEffects[index].volume,
                   in: 0...1, step: 0.05, onEditingChanged: { editing in
                       if editing { model.beginSoundEffectsEdit() }
                   }).tint(.cyan)
            Toggle("Tắt tiếng track này",
                   isOn: Binding(
                       get: { model.soundEffects[index].muted },
                       set: { newValue in
                           model.beginSoundEffectsEdit()
                           model.soundEffects[index].muted = newValue
                       }
                   ))
                .font(.caption)

            HStack {
                Text("Fade-in")
                Spacer()
                Text(String(format: "%.2fs", item.fadeIn)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].fadeIn,
                   in: 0...min(2, max(0.05, item.duration / 2)),
                   step: 0.05, onEditingChanged: { editing in
                       if editing { model.beginSoundEffectsEdit() }
                   }).tint(.cyan)

            HStack {
                Text("Fade-out")
                Spacer()
                Text(String(format: "%.2fs", item.fadeOut)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].fadeOut,
                   in: 0...min(2, max(0.05, item.duration / 2)),
                   step: 0.05, onEditingChanged: { editing in
                       if editing { model.beginSoundEffectsEdit() }
                   }).tint(.cyan)

            Divider()
            volumeKeyframeEditor(item)
        }
    }

    private func sfxTrimStart(_ id: UUID) -> Binding<Double> {
        Binding {
            model.soundEffects.first(where: { $0.id == id })?.sourceStart ?? 0
        } set: { value in
            guard let i = model.soundEffects.firstIndex(where: { $0.id == id })
            else { return }
            let sound = model.soundEffects[i]
            let end = min(sound.originalDuration,
                          sound.sourceStart + sound.duration)
            let from = min(max(0, value), max(0, end - 0.1))
            model.soundEffects[i].sourceStart = from
            model.soundEffects[i].duration = min(
                max(0.1, end - from),
                max(0.1, model.totalDuration - sound.start)
            )
        }
    }

    private func sfxTrimEnd(_ id: UUID) -> Binding<Double> {
        Binding {
            guard let sound = model.soundEffects.first(where: {
                $0.id == id
            }) else { return 0 }
            return sound.sourceStart + sound.duration
        } set: { value in
            guard let i = model.soundEffects.firstIndex(where: { $0.id == id })
            else { return }
            let sound = model.soundEffects[i]
            let end = min(sound.originalDuration,
                          max(sound.sourceStart + 0.1, value))
            model.soundEffects[i].duration = min(
                max(0.1, end - sound.sourceStart),
                max(0.1, model.totalDuration - sound.start)
            )
        }
    }

    @ViewBuilder
    private func volumeKeyframeEditor(_ item: SoundEffectClip) -> some View {
        let progress = (model.timelineSecond - item.start) /
                       max(0.1, item.duration)
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Keyframe âm lượng", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(item.volumeKeyframes.count)/16")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            AudioGainCurveView(
                frames: item.volumeKeyframes,
                selectedID: selectedKeyframeID,
                playheadProgress: progress,
                onSelect: { selectedKeyframeID = $0 }
            )

            HStack(spacing: 7) {
                Button {
                    if let id = model.addSoundVolumeKeyframe(item.id) {
                        selectedKeyframeID = id
                    }
                } label: {
                    Label("Thêm tại con trỏ", systemImage: "plus.diamond.fill")
                }
                .disabled(item.volumeKeyframes.count >= 16 ||
                    model.timelineSecond < item.start ||
                    model.timelineSecond > item.end)
                Button {
                    if let id = model.splitSoundEffectAtPlayhead(item.id) {
                        selectedID = id
                        selectedKeyframeID = nil
                    }
                } label: {
                    Label("Tách FX", systemImage: "scissors")
                }
                .disabled(model.soundEffects.count >= 12)
            }
            .font(.caption2)
            .buttonStyle(.borderedProminent)

            if let keyframe = item.volumeKeyframes.first(where: {
                $0.id == selectedKeyframeID
            }) {
                HStack {
                    Text(String(format: "Mốc %.2fs", keyframe.progress *
                                item.duration + item.start))
                    Spacer()
                    Text("\(Int(keyframe.gain * 100))%")
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(value: Binding(
                    get: {
                        Double(model.soundEffects.first(where: {
                            $0.id == item.id
                        })?.volumeKeyframes.first(where: {
                            $0.id == keyframe.id
                        })?.gain ?? 1)
                    },
                    set: {
                        model.updateSoundVolumeKeyframe(
                            item.id, frameID: keyframe.id, gain: Float($0)
                        )
                    }
                ), in: 0...1, step: 0.05,
                   onEditingChanged: { editing in
                       if editing { model.beginSoundEffectsEdit() }
                   })
                    .tint(.orange)
                Button(role: .destructive) {
                    model.deleteSoundVolumeKeyframe(
                        item.id, frameID: keyframe.id
                    )
                    selectedKeyframeID = nil
                } label: {
                    Label("Xóa mốc đã chọn", systemImage: "trash")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            if !item.volumeKeyframes.isEmpty {
                Button("Xóa toàn bộ keyframe") {
                    model.resetSoundVolumeKeyframes(item.id)
                    selectedKeyframeID = nil
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
            Text("Đặt con trỏ trong FX → Thêm mốc → chọn chấm màu cam và chỉnh mức tiếng. Các mốc nối tuyến tính, nghe thử ngay và được đưa vào MP4.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AudioWaveformBars: View {
    let url: URL
    @State private var bars: [Double] = Array(repeating: 0.18, count: 64)

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(Color.cyan.opacity(0.60 + 0.30 * bars[i]))
                        .frame(
                            width: max(1, (geometry.size.width - 96) / 64),
                            height: max(3, geometry.size.height * bars[i])
                        )
                        .frame(height: geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: url.path) {
            if let sample = try? await AudioWaveformSampler.sample(url: url),
               !sample.isEmpty {
                bars = sample
            }
        }
        .accessibilityLabel("Waveform âm thanh")
    }
}
