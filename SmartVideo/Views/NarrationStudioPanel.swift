import SwiftUI
import AVFoundation

/// Narration controls: voice, tone, rate, pitch, silence removal and narration captions.
struct NarrationStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @ObservedObject var recorder: VoiceRecorder
    let importVoice: () -> Void

    @State private var voicePreview = AVSpeechSynthesizer()
    @State private var filePreview: AVAudioPlayer?

    private var voices: [NarrationVoiceChoice] {
        NarrationVoiceChoice.available
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Studio thuyết minh", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Text("Offline")
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            Text("Chọn giọng iOS đang có trên máy. Số lượng giọng phụ thuộc gói giọng đã cài trong Cài đặt iPhone.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Giọng đọc", selection: $model.narratorVoiceID) {
                Text("Tiếng Việt mặc định").tag("")
                ForEach(voices) { voice in
                    Text(voice.title).tag(voice.id)
                }
            }
            .pickerStyle(.menu)

            Text("Phong cách đọc")
                .font(.caption.bold())
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(NarrationTone.allCases) { tone in
                    Button(tone.rawValue) { model.narratorTone = tone }
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(model.narratorTone == tone ? .black : .white)
                        .background(
                            model.narratorTone == tone ? Color.cyan : Color.white.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .buttonStyle(.plain)
                }
            }

            HStack {
                Text("Tốc độ đọc")
                Spacer()
                Text(String(format: "%.0f%%", model.narratorRate * 100))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.narratorRate, in: 0.75...1.30, step: 0.05)
                .tint(.cyan)

            HStack {
                Text("Cao độ giọng")
                Spacer()
                Text(String(format: "%.0f%%", model.narratorPitch * 100))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.narratorPitch, in: 0.75...1.25, step: 0.05)
                .tint(.cyan)

            Button {
                let sample = model.narrationText.trimmingCharacters(in: .whitespacesAndNewlines)
                voicePreview.stopSpeaking(at: .immediate)
                let utterance = AVSpeechUtterance(
                    string: sample.isEmpty ?
                        "Xin chào, đây là giọng thuyết minh của ViePN Smart Video." :
                        String(sample.prefix(160))
                )
                if let voice = AVSpeechSynthesisVoice(identifier: model.narratorVoiceID) {
                    utterance.voice = voice
                } else {
                    utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
                }
                utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                                     max(AVSpeechUtteranceMinimumSpeechRate,
                                         model.narratorTone.rate * model.narratorRate))
                utterance.pitchMultiplier = min(2,
                    max(0.5, model.narratorTone.pitch * model.narratorPitch))
                voicePreview.speak(utterance)
            } label: {
                Label("Nghe thử giọng", systemImage: "play.circle")
            }
            .buttonStyle(.bordered)

            TextField("Nhập lời thuyết minh...", text: $model.narrationText, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    voicePreview.stopSpeaking(at: .immediate)
                    model.generateNarrationFromText()
                } label: {
                    Label(model.isGeneratingNarration ? "Đang tạo..." : "Tạo bản đọc",
                          systemImage: "speaker.wave.2")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isGeneratingNarration ||
                    model.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    model.createSubtitlesFromNarrationText()
                } label: {
                    Label("Tạo phụ đề", systemImage: "captions.bubble")
                }
                .buttonStyle(.bordered)
                .disabled(model.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.caption)

            Divider()
            Text("Bản thuyết minh")
                .font(.subheadline.bold())

            HStack {
                Button {
                    if recorder.isRecording {
                        model.voiceoverURL = recorder.stop()
                        model.originalVoiceoverURL = nil
                        model.masteringMessage = ""
                    } else {
                        recorder.start()
                    }
                } label: {
                    Label(recorder.isRecording ? "Dừng thu" : "Thu micro",
                          systemImage: recorder.isRecording ? "stop.circle" : "mic")
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .cyan)

                Button(action: importVoice) {
                    Label("Nhập giọng đọc", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)

            if let file = model.voiceoverURL {
                Text(file.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    Button {
                        do {
                            filePreview?.stop()
                            filePreview = try AVAudioPlayer(contentsOf: file)
                            filePreview?.play()
                        } catch {
                            model.errorText = "Không phát được thuyết minh: \(error.localizedDescription)"
                        }
                    } label: {
                        Label("Nghe bản đọc", systemImage: "play")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        model.removeSilenceFromNarration()
                    } label: {
                        Label(model.isRemovingSilence ? "Đang cắt..." : "Xóa khoảng lặng",
                              systemImage: "waveform.path.ecg.rectangle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRemovingSilence)
                }
                .font(.caption)

                if model.isRemovingSilence {
                    ProgressView("Đang dò khoảng lặng và ghép lời nói…")
                        .font(.caption2)
                }
                if let removed = model.lastSilenceRemoved {
                    Text(String(format: "Đã cắt %.1f giây khoảng lặng, tạo file mới.", removed))
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
            }

            HStack {
                Text("Ngưỡng phát hiện lời nói")
                Spacer()
                Text("\(Int(model.silenceThreshold)) dBFS")
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.silenceThreshold, in: -55...(-24), step: 1)
                .tint(.cyan)

            HStack {
                Text("Khoảng lặng tối thiểu")
                Spacer()
                Text(String(format: "%.2fs", model.silenceGap))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: $model.silenceGap, in: 0.25...1.2, step: 0.05)
                .tint(.cyan)

            Text("Giữ khoảng đệm 0,12 giây trước/sau câu để tránh cắt mất âm đầu. Nên nghe lại bản đã xử lý; tính năng này chưa tự đồng bộ phụ đề theo phần lời bị cắt.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            VoiceMasteringPanel(model: model)
        }
        .padding(10)
    }
}
