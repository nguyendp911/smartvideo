import SwiftUI
import AVFoundation

struct VoiceMasteringPanel: View {
    @ObservedObject var model: EditorViewModel
    @State private var beforePlayer: AVAudioPlayer?
    @State private var afterPlayer: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Voice Mastering Pro", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text("On-device DSP")
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            Text("EQ, compressor và noise gate xử lý thật bản thuyết minh trước khi ghép MP4. File gốc được giữ lại.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VoiceMasteringPresets(model: model)
            Divider()
            VoiceMasteringEQ(model: model)
            Divider()
            VoiceMasteringDynamics(model: model)
            Divider()
            HStack(spacing: 8) {
                Button {
                    beforePlayer?.stop()
                    afterPlayer?.stop()
                    model.applyVoiceMastering()
                } label: {
                    Label(model.isMasteringVoice ? "Đang xử lý..." :
                          "Áp dụng vào giọng đọc",
                          systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isMasteringVoice || model.voiceoverURL == nil)

                Button {
                    beforePlayer?.stop()
                    afterPlayer?.stop()
                    model.restoreOriginalNarration()
                } label: {
                    Label("Khôi phục", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(model.originalVoiceoverURL == nil ||
                          model.isMasteringVoice)
            }
            .font(.caption)

            if model.isMasteringVoice {
                ProgressView("Đang xử lý âm thanh…")
                    .font(.caption)
            }
            if !model.masteringMessage.isEmpty {
                Text(model.masteringMessage)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            if model.originalVoiceoverURL != nil {
                HStack(spacing: 8) {
                    Button("Nghe bản gốc") {
                        if let source = model.originalVoiceoverURL {
                            play(source, processed: false)
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Nghe bản xử lý") {
                        if let source = model.voiceoverURL {
                            play(source, processed: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
            }

            Text("Noise gate chỉ giảm tiếng rất nhỏ khi không nói, không phải khử ồn bằng AI. Compressor có thể làm tiếng nền rõ hơn; nên nghe so sánh trước và sau.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 11))
        .onDisappear {
            beforePlayer?.stop()
            afterPlayer?.stop()
        }
    }

    private func play(_ url: URL, processed: Bool) {
        do {
            beforePlayer?.stop()
            afterPlayer?.stop()
            let player = try AVAudioPlayer(contentsOf: url)
            try AVAudioSession.sharedInstance().setCategory(.playback)
            player.prepareToPlay()
            player.play()
            if processed {
                afterPlayer = player
            } else {
                beforePlayer = player
            }
        } catch {
            model.errorText = "Không phát được giọng đọc: \(error.localizedDescription)"
        }
    }
}

private struct VoiceMasteringPresets: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Chất giọng")
                .font(.subheadline.bold())
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(VoiceMasteringPreset.allCases) { preset in
                    Button {
                        model.masteringSettings = preset.settings
                    } label: {
                        Text(preset.rawValue)
                            .font(.caption2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                model.masteringSettings == preset.settings ?
                                    Color.cyan.opacity(0.30) :
                                    Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct VoiceMasteringEQ: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EQ 3 dải")
                .font(.subheadline.bold())
            VoiceDBSlider(title: "Bass · 155 Hz",
                          value: $model.masteringSettings.bassDB,
                          range: -12...12)
            VoiceDBSlider(title: "Mid · 1,45 kHz",
                          value: $model.masteringSettings.midDB,
                          range: -12...12)
            VoiceDBSlider(title: "Treble · 4,9 kHz",
                          value: $model.masteringSettings.trebleDB,
                          range: -12...12)
        }
    }
}

private struct VoiceMasteringDynamics: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Compressor & Noise Gate")
                .font(.subheadline.bold())

            VoiceDBSlider(title: "Ngưỡng nén",
                          value: $model.masteringSettings.compressorThreshold,
                          range: -36...(-8), suffix: " dBFS")

            HStack {
                Text("Tỷ lệ nén")
                Spacer()
                Text(String(format: "%.1f:1",
                            model.masteringSettings.compressorRatio))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.masteringSettings.compressorRatio,
                   in: 1...6, step: 0.5)
                .tint(.cyan)

            Toggle("Noise gate · giảm tiếng nhỏ",
                   isOn: $model.masteringSettings.noiseGateEnabled)
                .font(.caption)
                .tint(.cyan)

            if model.masteringSettings.noiseGateEnabled {
                VoiceDBSlider(
                    title: "Ngưỡng mở cổng",
                    value: $model.masteringSettings.noiseGateThreshold,
                    range: -60...(-30),
                    suffix: " dBFS"
                )
            }

            VoiceDBSlider(title: "Gain đầu ra",
                          value: $model.masteringSettings.outputGainDB,
                          range: -6...8)
        }
    }
}

private struct VoiceDBSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix: String = " dB"

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%+.1f%@", value, suffix))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $value, in: range, step: 0.5)
                .tint(.cyan)
        }
    }
}
