import SwiftUI
import AVFoundation

/// Compact CapCut-style sound effects workspace. A multi-track SFX layer
/// stays separate from background music and voiceover.
struct SoundEffectsStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let importAudio: () -> Void

    @Binding var selectedID: UUID?
    @State private var previewPlayer: AVAudioPlayer?

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

            Text("Âm thanh tự tạo là mẫu gốc do ứng dụng tổng hợp. Mỗi track có thể phát chồng lên nhạc nền, giọng đọc và tiếng video. Preview là nghe riêng hiệu ứng; cần xuất MP4 để nghe bản phối cuối.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .onAppear {
            if selectedID == nil {
                selectedID = model.soundEffects.first?.id
            }
        }
        .onDisappear {
            previewPlayer?.stop()
        }
    }

    @ViewBuilder
    private func editorForSelected(_ index: Int) -> some View {
        let item = model.soundEffects[index]
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            Text("Chỉnh track đã chọn")
                .font(.subheadline.bold())
            AudioWaveformBars(url: item.fileURL)
                .frame(height: 50)

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

            HStack {
                Text("Vị trí phát")
                Spacer()
                Text(String(format: "%.2fs", item.start)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].start,
                   in: 0...max(0.1, model.totalDuration - 0.1),
                   step: 0.05).tint(.cyan)

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
               step: 0.05).tint(.cyan)

            HStack {
                Text("Thời lượng phát")
                Spacer()
                Text(String(format: "%.2fs", item.duration)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].duration,
                   in: 0.1...max(0.2, min(
                    item.originalDuration - item.sourceStart,
                    model.totalDuration - item.start
                   )), step: 0.05).tint(.cyan)

            HStack {
                Text("Âm lượng")
                Spacer()
                Text("\(Int(item.volume * 100))%")
            }.font(.caption)
            Slider(value: $model.soundEffects[index].volume,
                   in: 0...1, step: 0.05).tint(.cyan)
            Toggle("Tắt tiếng track này",
                   isOn: $model.soundEffects[index].muted)
                .font(.caption)

            HStack {
                Text("Fade-in")
                Spacer()
                Text(String(format: "%.2fs", item.fadeIn)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].fadeIn,
                   in: 0...min(2, max(0.05, item.duration / 2)),
                   step: 0.05).tint(.cyan)

            HStack {
                Text("Fade-out")
                Spacer()
                Text(String(format: "%.2fs", item.fadeOut)).monospacedDigit()
            }.font(.caption)
            Slider(value: $model.soundEffects[index].fadeOut,
                   in: 0...min(2, max(0.05, item.duration / 2)),
                   step: 0.05).tint(.cyan)
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
