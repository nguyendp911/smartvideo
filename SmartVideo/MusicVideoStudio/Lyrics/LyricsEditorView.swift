import SwiftUI
import UniformTypeIdentifiers

extension MusicVideoStudio {
    /// Lyrics tools: type or import lyrics, spread them over the song, shift everything,
    /// tap along to the music, adjust each word's boundaries, export LRC.
    struct LyricsEditorView: View {
        @ObservedObject var model: MusicVideoEditorModel
        let layerID: UUID
        @Environment(\.dismiss) private var dismiss

        @State private var text = ""
        @State private var lineIndex = 0
        @State private var importing = false
        @State private var tapMode = false
        @State private var taps: [Double] = []
        @State private var recognitionTask: Task<Void, Never>?
        @State private var exportedURL: URL?

        private var layer: LyricsLayer? { model.lyrics(layerID) }

        private static let importTypes: [UTType] = {
            var types: [UTType] = [.plainText, .text]
            for ext in ["lrc", "srt"] { if let t = UTType(filenameExtension: ext) { types.append(t) } }
            return types
        }()

        var body: some View {
            NavigationStack {
                Group {
                    if let layer {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                sourceSection(layer)
                                if !layer.lines.isEmpty {
                                    syncSection(layer)
                                    timingSection(layer)
                                }
                                if !model.lyricsBusy.isEmpty {
                                    HStack(spacing: 8) { ProgressView(); Text(model.lyricsBusy).font(.caption) }
                                }
                                if let message = model.statusMessage {
                                    Text(message).font(.caption).foregroundStyle(.orange)
                                }
                            }
                            .padding(16)
                        }
                    } else {
                        Text("Lớp lời đã bị xoá.").foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Lời karaoke")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Xong") { finish() } }
                }
            }
            .onAppear { text = layer.map(Self.plainText) ?? "" }
            .onDisappear { recognitionTask?.cancel(); if tapMode { model.playback.pause() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes) { result in
                if case .success(let url) = result {
                    model.importLyricsFile(url, into: layerID)
                    text = model.lyrics(layerID).map(Self.plainText) ?? text
                    lineIndex = 0
                }
            }
        }

        static func plainText(_ layer: LyricsLayer) -> String { layer.lines.map(\.text).joined(separator: "\n") }

        private func finish() {
            if tapMode { model.playback.pause() }
            dismiss()
        }

        // MARK: Source

        private func sourceSection(_ layer: LyricsLayer) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("LỜI BÀI HÁT").font(.caption2.bold()).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 120, maxHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .font(.callout)
                HStack {
                    Button { importing = true } label: { Label("Nhập .lrc/.srt/.txt", systemImage: "doc.badge.plus") }
                    Spacer()
                    Button { model.distributePlainLyrics(text, into: layerID); lineIndex = 0 } label: {
                        Label("Chia đều theo nhạc", systemImage: "text.alignleft")
                    }.buttonStyle(.borderedProminent).tint(.cyan)
                }.font(.caption)
                HStack {
                    Button { recognize(layer) } label: {
                        Label("Căn lời bằng nhận diện giọng (thử nghiệm)", systemImage: "waveform.badge.mic")
                    }.disabled(!model.lyricsBusy.isEmpty || layer.audioLayerID == nil)
                    if !model.lyricsBusy.isEmpty {
                        Button("Huỷ") { recognitionTask?.cancel() }.foregroundStyle(.red)
                    }
                }.font(.caption)
                HStack {
                    Button { exportedURL = model.exportLRC(layerID) } label: { Label("Tạo tệp .lrc", systemImage: "square.and.arrow.up") }
                        .disabled(layer.lines.isEmpty)
                    if let exportedURL {
                        ShareLink(item: exportedURL) { Label(exportedURL.lastPathComponent, systemImage: "paperplane") }.lineLimit(1)
                    }
                }.font(.caption)
                Text("Nhận diện giọng dùng Apple Speech: làm cho tiếng nói, nên với nhạc lớn có thể lệch. Hãy tinh chỉnh bên dưới.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }

        private func recognize(_ layer: LyricsLayer) {
            let rows = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            recognitionTask = Task { await model.recognizeLyrics(layerID, rows: rows) }
        }

        // MARK: Shift + tap sync

        private func syncSection(_ layer: LyricsLayer) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("ĐỒNG BỘ").font(.caption2.bold()).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("Dời tất cả").font(.caption)
                    ForEach([-1.0, -0.1, 0.1, 1.0], id: \.self) { step in
                        Button(String(format: "%+.1fs", step)) { model.shiftLyrics(layerID, by: step) }
                            .buttonStyle(.bordered).font(.caption)
                    }
                }
                if tapMode { tapPanel(layer) } else {
                    Button { startTapping(layer) } label: {
                        Label("Chạm theo nhịp để đặt thời gian", systemImage: "hand.tap")
                    }.buttonStyle(.bordered).font(.caption)
                }
            }
        }

        private var allWords: [LyricWord] { (layer?.lines ?? []).flatMap(\.words) }

        private func startTapping(_ layer: LyricsLayer) {
            guard layer.audioLayerID != nil else { return }
            taps = []
            tapMode = true
            model.playback.seek(to: ProjectTime(seconds: max(0, layer.core.start.seconds)))
            model.playback.play()
        }

        private func tapPanel(_ layer: LyricsLayer) -> some View {
            let words = allWords
            let next = taps.count < words.count ? words[taps.count].text : "—"
            return VStack(spacing: 8) {
                Text("Nghe nhạc và chạm đúng lúc bắt đầu mỗi từ.").font(.caption2).foregroundStyle(.secondary)
                Text("Từ tiếp theo: \(next)").font(.headline).foregroundStyle(.yellow)
                Text("\(taps.count)/\(words.count) từ").font(.caption).monospacedDigit()
                Button {
                    let t = LyricsTiming.sourceTime(layer, in: model.project, at: model.playback.time)
                    if taps.count < words.count { taps.append(t) }
                    if taps.count >= words.count { applyTaps() }
                } label: {
                    Text("CHẠM").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 64)
                }.buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                HStack {
                    Button("Bỏ lần chạm cuối") { _ = taps.popLast() }.disabled(taps.isEmpty)
                    Spacer()
                    Button("Huỷ") { model.playback.pause(); tapMode = false }
                    Button("Áp dụng") { applyTaps() }.disabled(taps.isEmpty).buttonStyle(.borderedProminent)
                }.font(.caption)
            }
            .padding(10)
            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }

        private func applyTaps() {
            model.playback.pause()
            let recorded = taps
            model.updateLyrics(layerID) { $0.lines = LyricsSynchronizer.tapSync($0.lines, taps: recorded) }
            tapMode = false
            taps = []
        }

        // MARK: Per-line timing

        private func timingSection(_ layer: LyricsLayer) -> some View {
            let index = min(max(0, lineIndex), layer.lines.count - 1)
            let line = layer.lines[index]
            return VStack(alignment: .leading, spacing: 8) {
                Text("THỜI GIAN TỪNG TỪ").font(.caption2.bold()).foregroundStyle(.secondary)
                HStack {
                    Button { lineIndex = max(0, index - 1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0)
                    Text("Dòng \(index + 1)/\(layer.lines.count)").font(.caption).frame(maxWidth: .infinity)
                    Button { lineIndex = min(layer.lines.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(index >= layer.lines.count - 1)
                }
                Text(line.text).font(.callout).lineLimit(2)
                LineTimingEditor(model: model, playback: model.playback, layerID: layerID, layer: layer, lineIndex: index)
                HStack {
                    Button { playLine(layer, line) } label: { Label("Nghe dòng này", systemImage: "play.fill") }
                    Spacer()
                    ForEach([-0.1, 0.1], id: \.self) { step in
                        Button(String(format: "Dòng %+.1fs", step)) {
                            model.updateLyrics(layerID) { $0.lines = LyricsSynchronizer.moveLine($0.lines, index: index, toStart: $0.lines[index].start + step) }
                        }.buttonStyle(.bordered)
                    }
                }.font(.caption)
            }
        }

        private func playLine(_ layer: LyricsLayer, _ line: LyricLine) {
            let project = LyricsTiming.offset(layer, in: model.project) + line.start - 0.3
            model.playback.seek(to: ProjectTime(seconds: max(0, project)))
            model.playback.play()
        }
    }

    /// Separate view so only the playhead cursor re-renders on every tick.
    struct LineTimingEditor: View {
        @ObservedObject var model: MusicVideoEditorModel
        @ObservedObject var playback: PlaybackEngine
        let layerID: UUID
        let layer: LyricsLayer
        let lineIndex: Int

        var body: some View {
            if layer.lines.indices.contains(lineIndex) {
                LyricsTimelineView(
                    line: layer.lines[lineIndex], lineIndex: lineIndex,
                    playheadSource: LyricsTiming.sourceTime(layer, in: model.project, at: playback.time),
                    onBeginDrag: { model.beginEdit() },
                    onMoveStart: { word, time in
                        model.updateLyrics(layerID, checkpoint: false) {
                            $0.lines = LyricsSynchronizer.moveBoundary($0.lines, line: lineIndex, word: word, to: time)
                        }
                    },
                    onMoveEnd: { word, time in
                        model.updateLyrics(layerID, checkpoint: false) {
                            $0.lines = LyricsSynchronizer.setWordEnd($0.lines, line: lineIndex, word: word, to: time)
                        }
                    })
            }
        }
    }
}
