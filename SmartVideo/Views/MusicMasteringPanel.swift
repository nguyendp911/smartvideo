import SwiftUI
import AVFoundation

/// Original offline music EQ presets, not licensed effect packs.
enum MusicTonePreset: String, CaseIterable, Identifiable {
    case original = "Nguyên bản"
    case warm = "Âm ấm"
    case bright = "Sáng rõ"
    case bass = "Bass Boost"
    case cinematic = "Điện ảnh"
    case loFi = "Lo-fi"

    var id: String { rawValue }

    var settings: VoiceMasteringSettings {
        switch self {
        case .original:
            return VoiceMasteringSettings(
                bassDB: 0, midDB: 0, trebleDB: 0,
                compressorThreshold: -20, compressorRatio: 1,
                noiseGateEnabled: false, noiseGateThreshold: -46,
                outputGainDB: 0
            )
        case .warm:
            return VoiceMasteringSettings(
                bassDB: 3, midDB: 0.8, trebleDB: -1.5,
                compressorThreshold: -20, compressorRatio: 1.5,
                noiseGateEnabled: false, noiseGateThreshold: -46,
                outputGainDB: 0
            )
        case .bright:
            return VoiceMasteringSettings(
                bassDB: -1.5, midDB: 2, trebleDB: 3.5,
                compressorThreshold: -21, compressorRatio: 1.5,
                noiseGateEnabled: false, noiseGateThreshold: -46,
                outputGainDB: 0
            )
        case .bass:
            return VoiceMasteringSettings(
                bassDB: 6, midDB: -1, trebleDB: 1,
                compressorThreshold: -22, compressorRatio: 2,
                noiseGateEnabled: false, noiseGateThreshold: -46,
                outputGainDB: 0
            )
        case .cinematic:
            return VoiceMasteringSettings(
                bassDB: 3.5, midDB: -1, trebleDB: 2,
                compressorThreshold: -23, compressorRatio: 2.5,
                noiseGateEnabled: false, noiseGateThreshold: -46,
                outputGainDB: 1
            )
        case .loFi:
            return VoiceMasteringSettings(
                bassDB: 2, midDB: -1, trebleDB: -5,
                compressorThreshold: -24, compressorRatio: 2,
                noiseGateEnabled: false, noiseGateThreshold: -46,
                outputGainDB: 0
            )
        }
    }
}

struct MusicMasteringPanel: View {
    @ObservedObject var model: EditorViewModel
    @State private var player: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Music Mastering", systemImage: "slider.horizontal.3")
                .font(.subheadline.bold())

            Text("Xử lý EQ và độ động nhạc nền trước khi xuất. Nhạc gốc vẫn được giữ để khôi phục.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            MusicMasteringPresets(model: model)
            MusicMasteringEQ(model: model)

            HStack {
                Text("Tỷ lệ nén")
                Spacer()
                Text(String(format: "%.1f:1",
                            model.musicMasteringSettings.compressorRatio))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.musicMasteringSettings.compressorRatio,
                   in: 1...5, step: 0.5)
                .tint(.cyan)

            HStack {
                Text("Ngưỡng nén")
                Spacer()
                Text(String(format: "%.0f dBFS",
                            model.musicMasteringSettings.compressorThreshold))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.musicMasteringSettings.compressorThreshold,
                   in: -34...(-8), step: 1)
                .tint(.cyan)

            HStack(spacing: 8) {
                Button {
                    player?.stop()
                    model.applyMusicMastering()
                } label: {
                    Label("Áp dụng EQ", systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    player?.stop()
                    model.normalizeMusic()
                } label: {
                    Label("Chuẩn hóa RMS", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
            .disabled(model.isProcessingMusic || model.musicURL == nil)

            HStack(spacing: 8) {
                Button {
                    player?.stop()
                    model.restoreOriginalMusic()
                } label: {
                    Label("Khôi phục nhạc gốc",
                          systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(model.originalMusicURL == nil ||
                          model.isProcessingMusic)

                Button {
                    if let url = model.musicURL {
                        play(url)
                    }
                } label: {
                    Label("Nghe nhạc", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .disabled(model.musicURL == nil ||
                          model.isProcessingMusic)
            }
            .font(.caption)

            if model.isProcessingMusic {
                ProgressView("Đang xử lý nhạc nền…")
                    .font(.caption)
            }
            if !model.musicProcessingMessage.isEmpty {
                Text(model.musicProcessingMessage)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            Text("Chuẩn hóa dùng mức RMS −18 dBFS và giới hạn sample peak −1 dBFS; không phải phép đo LUFS/true-peak chuyên dụng. File PCM trung gian có thể lớn, nhạc tối đa 15 phút.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 11))
        .onDisappear { player?.stop() }
    }

    private func play(_ url: URL) {
        do {
            player?.stop()
            try AVAudioSession.sharedInstance().setCategory(.playback)
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.currentTime = min(
                max(0, model.musicStartSeconds), newPlayer.duration
            )
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            model.errorText = "Không mở được nhạc: \(error.localizedDescription)"
        }
    }
}

private struct MusicMasteringPresets: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ], spacing: 6) {
            ForEach(MusicTonePreset.allCases) { preset in
                Button {
                    model.musicMasteringSettings = preset.settings
                } label: {
                    Text(preset.rawValue)
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            model.musicMasteringSettings == preset.settings ?
                                Color.cyan.opacity(0.25) :
                                Color.white.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MusicMasteringEQ: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(spacing: 6) {
            dbSlider("Bass", value: $model.musicMasteringSettings.bassDB)
            dbSlider("Mid", value: $model.musicMasteringSettings.midDB)
            dbSlider("Treble", value: $model.musicMasteringSettings.trebleDB)
        }
    }

    private func dbSlider(_ label: String, value: Binding<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%+.1f dB", value.wrappedValue))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: -12...12, step: 0.5)
                .tint(.cyan)
        }
    }
}
