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

            Text("Xử lý âm thanh thuyết minh thật trước khi ghép MP4. EQ, compressor và noise gate hoạt động offline; bản thu gốc được giữ để khôi phục.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Chất giọng")
                .font(.caption.bold())
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(VoiceMasteringPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        model.masteringSettings = preset.settings
                    }
                    .font(.caption2)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        model.masteringSettings == preset.settings ?
                            Color.cyan.opacity(0.28) :
                            Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .buttonStyle(.plain)
                }
            }

            Divider()
            Text("EQ 3 dải")
                .font(.subheadline.bold())

            dbSlider("Bass · 155 Hz", value: $model.masteringSettings.bassDB,
                     bounds: -12...12)
            dbSlider("Mid · 1,45 kHz", value: $model.masteringSettings.midDB,
                     bounds: -12...12)
            dbSlider("Treble · 4,9 kHz", value: $model.masteringSettings.trebleDB,
                     bounds: -12...12)

            Divider()
            Text("Compressor")
                .font(.subheadline.bold())

            dbSlider("Ngưỡng nén", value:
                     $model.masteringSettings.compressorThreshold,
                     bounds: -36...(-8), suffix: " dBFS")

            HStack {
                Text("Tỷ lệ nén")
                Spacer()
                Text(String(format: "%.1f:1",
                            model.masteringSettings.compressorRatio))
                    .monospacedDigit()
            }.font(.caption)
            Slider(value: $model.masteringSettings.compressorRatio,
                   in: 1...6, step: 0.5)
                .tint(.cyan)

            Toggle("Noise gate · giảm ồn khi không nói",
                   isOn: $model.masteringSettings.noiseGateEnabled)
                .font(.caption)
                .tint(.cyan)
            if model.masteringSettings.noiseGateEnabled {
                dbSlider("Ngưỡng lọc tiếng nhỏ", value:
                         $model.masteringSettings.noiseGateThreshold,
                         bounds: -60...(-30), suffix: " dBFS")
            }

            dbSlider("Tăng gain đầu ra", value:
                     $model.masteringSettings.outputGainDB,
                     bounds: -6...8)

            HStack(spacing: 8) {
                Button {
                    beforePlayer?.stop()
                    afterPlayer?.stop()
                    model.applyVoiceMastering()
                } label: {
                    Label(model.isMasteringVoice ? "Đang xử lý..." :
                          "Áp dụng vào giọng đọc",
                          systemImage: "waveform.badge.checkmark")
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
                ProgressView("Đang xử lý PCM, không ghi đè bản gốc…")
                    .font(.caption)
            }
            if !model.masteringMessage.isEmpty {
                Text(model.masteringMessage)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }
            if model.originalVoiceoverURL != nil {
                HStack {
                    Button("Nghe bản gốc") {
                        if let url = model.originalVoiceoverURL {
                            play(url, processed: false)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Nghe bản xử lý") {
                        if let url = model.voiceoverURL {
                            play(url, processed: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
            }

            Text("Noise gate chỉ hạ tiếng nhỏ trong đoạn im lặng, không phải khử tạp âm bằng AI. Compressor có thể làm nền ồn rõ hơn; hãy nghe so sánh trước/sau. Âm lượng lớn được giới hạn mức đỉnh để tránh clipping.")
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

    private func dbSlider(_ label: String, value: Binding<Double>,
                          bounds: ClosedRange<Double>,
                          suffix: String = " dB") -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%+.1f%@", value.wrappedValue, suffix))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: bounds, step: 0.5)
                .tint(.cyan)
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
            model.errorText = "Không phát được bản giọng đọc: \(error.localizedDescription)"
        }
    }
}
