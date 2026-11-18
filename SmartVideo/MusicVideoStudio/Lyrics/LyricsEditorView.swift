import SwiftUI
import UniformTypeIdentifiers

extension MusicVideoStudio {
    /// Lyrics tools, easiest first: spread lyrics on the music's BEATS, tap once per LINE while the
    /// song plays, or fine-tune single words with snapping to beats.
    struct LyricsEditorView: View {
        @ObservedObject var model: MusicVideoEditorModel
        let layerID: UUID
        @Environment(\.dismiss) private var dismiss

        enum TapMode { case lines, words }

        @State private var text = ""
        @State private var lineIndex = 0
        @State private var importing = false
        @State private var tapMode: TapMode?
        @State private var taps: [Double] = []
        @State private var recognitionTask: Task<Void, Never>?
        @State private var exportedURL: URL?
        @State private var beats: [Double] = []
        @State private var loadingBeats = false
        @State private var beatsPerLine = 4
        @State private var snapToBeats = true

        /// People tap a little after they hear the word: take this off every tap.
        static let tapLatency = 0.10

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
                                beatSection(layer)
                                tapSection(layer)
                                if !layer.lines.isEmpty {
                                    linesSection(layer)
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
            .task {
                guard let layer, layer.audioLayerID != nil, beats.isEmpty else { return }
                loadingBeats = true
                beats = await model.fileBeats(for: layer)
                loadingBeats = false
            }
            .onDisappear { recognitionTask?.cancel(); if tapMode != nil { model.playback.pause() } }
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
            if tapMode != nil { model.playback.pause() }
            dismiss()
        }

        private var typedRows: [String] {
            let rows = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return rows.isEmpty ? (layer?.lines.map(\.text) ?? []) : rows
        }

        /// Beats inside the part of the song that plays.
        private func playingBeats(_ layer: LyricsLayer) -> [Double] {
            let range = model.lyricsSourceRange(layer)
            return beats.filter { $0 >= range.start - 0.001 && $0 < range.start + range.duration }
        }

        // MARK: 1. Source

        private func sourceSection(_ layer: LyricsLayer) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. LỜI BÀI HÁT").font(.caption2.bold()).foregroundStyle(.secondary)
                Text("Dán hoặc gõ lời, mỗi dòng một câu hát.").font(.caption2).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .frame(minHeight: 110, maxHeight: 170)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .font(.callout)
                HStack {
                    Button { importing = true } label: { Label("Nhập .lrc/.srt/.txt", systemImage: "doc.badge.plus") }
                    Spacer()
                    Button { model.distributePlainLyrics(text, into: layerID); lineIndex = 0 } label: {
                        Label("Chia đều cả bài", systemImage: "text.alignleft")
                    }.buttonStyle(.bordered)
                }.font(.caption)
                DisclosureGroup("Nâng cao: nhận diện giọng, xuất LRC") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button { recognize(layer) } label: {
                            Label("Căn lời bằng nhận diện giọng (thử nghiệm)", systemImage: "waveform.badge.mic")
                        }.disabled(!model.lyricsBusy.isEmpty || layer.audioLayerID == nil)
                        if !model.lyricsBusy.isEmpty { Button("Huỷ nhận diện") { recognitionTask?.cancel() }.foregroundStyle(.red) }
                        Text("Apple Speech làm cho tiếng nói, nên với nhạc lớn có thể lệch. Hãy tinh chỉnh bên dưới.")
                            .font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Button { exportedURL = model.exportLRC(layerID) } label: { Label("Tạo tệp .lrc", systemImage: "square.and.arrow.up") }
                                .disabled(layer.lines.isEmpty)
                            if let exportedURL {
                                ShareLink(item: exportedURL) { Label(exportedURL.lastPathComponent, systemImage: "paperplane") }.lineLimit(1)
                            }
                        }
                    }.padding(.top, 4)
                }.font(.caption)
            }
        }

        private func recognize(_ layer: LyricsLayer) {
            recognitionTask = Task { await model.recognizeLyrics(layerID, rows: typedRows) }
        }

        // MARK: 2. Beats (the easy way)

        private func beatSection(_ layer: LyricsLayer) -> some View {
            let usable = playingBeats(layer)
            return VStack(alignment: .leading, spacing: 8) {
                Text("2. CHIA THEO NHỊP NHẠC (DỄ NHẤT)").font(.caption2.bold()).foregroundStyle(.secondary)
                if layer.audioLayerID == nil {
                    Text("Gắn lớp lời với một clip nhạc (bảng thuộc tính) để dùng nhịp.").font(.caption2).foregroundStyle(.orange)
                } else if loadingBeats {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Đang tìm nhịp…").font(.caption2) }
                } else if usable.count < 2 {
                    Text("Chưa tìm thấy nhịp rõ trong bài này. Hãy dùng \"Chạm theo dòng\" bên dưới.").font(.caption2).foregroundStyle(.orange)
                } else {
                    Text("Tìm thấy \(usable.count) nhịp (khoảng \(Int((60 / max(0.2, LyricsBeatSync.interval(usable))).rounded())) nhịp/phút). Mỗi dòng sẽ bắt đầu đúng một nhịp.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Stepper("Mỗi dòng = \(beatsPerLine) nhịp", value: $beatsPerLine, in: 1...16).font(.caption)
                    HStack {
                        Button { spreadOnBeats(layer, fromPlayhead: false) } label: { Label("Từ đầu bài", systemImage: "backward.end") }
                        Button { spreadOnBeats(layer, fromPlayhead: true) } label: { Label("Từ vị trí đang phát", systemImage: "play.circle") }
                    }.buttonStyle(.borderedProminent).tint(.cyan).font(.caption)
                    Button { snapLines(layer) } label: { Label("Hút các dòng đã có vào nhịp gần nhất", systemImage: "scope") }
                        .buttonStyle(.bordered).font(.caption).disabled(layer.lines.isEmpty)
                    Text("Mẹo: nhạc pop thường 4 nhịp = 1 câu ngắn, 8 nhịp = 1 câu dài. Thử số khác nếu lời bị sớm hoặc muộn.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }

        private func spreadOnBeats(_ layer: LyricsLayer, fromPlayhead: Bool) {
            let usable = playingBeats(layer)
            var first = 0
            if fromPlayhead {
                let now = LyricsTiming.sourceTime(layer, in: model.project, at: model.playback.time)
                first = LyricsBeatSync.firstBeatIndex(atOrAfter: now, beats: usable) ?? 0
            }
            let lines = LyricsBeatSync.distributeOnBeats(rows: typedRows, beats: usable, beatsPerLine: beatsPerLine, firstBeat: first)
            guard !lines.isEmpty else { model.setStatus("Chưa có lời để chia."); return }
            model.setStatus(nil)
            model.updateLyrics(layerID) { $0.lines = lines }
            lineIndex = 0
        }

        private func snapLines(_ layer: LyricsLayer) {
            let usable = playingBeats(layer)
            model.updateLyrics(layerID) { $0.lines = LyricsBeatSync.snapLines($0.lines, beats: usable) }
        }

        // MARK: 3. Tapping

        private var allWords: [LyricWord] { (layer?.lines ?? []).flatMap(\.words) }

        private func tapSection(_ layer: LyricsLayer) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("3. CHẠM THEO NHẠC").font(.caption2.bold()).foregroundStyle(.secondary)
                if tapMode == nil {
                    Text("Nhạc phát, bạn chạm mỗi khi một câu bắt đầu. Chỉ cần chạm một lần cho mỗi dòng.").font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button { startTapping(layer, .lines) } label: { Label("Chạm theo dòng", systemImage: "hand.tap.fill") }
                            .buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                        Button { startTapping(layer, .words) } label: { Label("Chạm từng từ", systemImage: "hand.tap") }
                            .buttonStyle(.bordered)
                    }.font(.caption).disabled(layer.lines.isEmpty || layer.audioLayerID == nil)
                    HStack(spacing: 8) {
                        Text("Dời tất cả").font(.caption)
                        ForEach([-1.0, -0.1, 0.1, 1.0], id: \.self) { step in
                            Button(String(format: "%+.1fs", step)) { model.shiftLyrics(layerID, by: step) }
                                .buttonStyle(.bordered).font(.caption)
                        }
                    }
                } else {
                    tapPanel(layer)
                }
            }
        }

        private func startTapping(_ layer: LyricsLayer, _ mode: TapMode) {
            taps = []
            tapMode = mode
            model.playback.seek(to: ProjectTime(seconds: max(0, layer.core.start.seconds)))
            model.playback.play()
        }

        private func tapPanel(_ layer: LyricsLayer) -> some View {
            let mode = tapMode ?? .lines
            let labels = mode == .lines ? layer.lines.map(\.text) : allWords.map(\.text)
            let next = taps.count < labels.count ? labels[taps.count] : "—"
            return VStack(spacing: 8) {
                Text(mode == .lines ? "Chạm khi mỗi DÒNG bắt đầu." : "Chạm khi mỗi TỪ bắt đầu.").font(.caption2).foregroundStyle(.secondary)
                Text(next).font(.headline).foregroundStyle(.yellow).multilineTextAlignment(.center).lineLimit(2)
                Text("\(taps.count)/\(labels.count)").font(.caption).monospacedDigit()
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let t = LyricsTiming.sourceTime(layer, in: model.project, at: model.playback.time) - Self.tapLatency
                    if taps.count < labels.count { taps.append(max(0, t)) }
                    if taps.count >= labels.count { applyTaps() }
                } label: {
                    Text("CHẠM").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 72)
                }.buttonStyle(.borderedProminent).tint(.yellow).foregroundStyle(.black)
                HStack {
                    Button("Bỏ lần chạm cuối") { _ = taps.popLast() }.disabled(taps.isEmpty)
                    Spacer()
                    Button("Huỷ") { model.playback.pause(); tapMode = nil }
                    Button("Áp dụng") { applyTaps() }.disabled(taps.isEmpty).buttonStyle(.borderedProminent)
                }.font(.caption)
            }
            .padding(10)
            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }

        private func applyTaps() {
            model.playback.pause()
            let recorded = taps, mode = tapMode ?? .lines
            let usable = layer.map(playingBeats) ?? []
            model.updateLyrics(layerID) { layer in
                switch mode {
                case .lines: layer.lines = LyricsBeatSync.tapLines(layer.lines, taps: recorded)
                case .words: layer.lines = LyricsSynchronizer.tapSync(layer.lines, taps: recorded)
                }
                if snapToBeats, usable.count >= 2, mode == .lines {
                    layer.lines = LyricsBeatSync.snapLines(layer.lines, beats: usable, window: 0.12)
                }
            }
            tapMode = nil
            taps = []
        }

        // MARK: 4. Lines + fine tuning

        private func linesSection(_ layer: LyricsLayer) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("4. CÁC DÒNG (chạm để nghe và chỉnh)").font(.caption2.bold()).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(layer.lines.enumerated()), id: \.element.id) { index, line in
                            Button { lineIndex = index; playLine(layer, line) } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary).frame(width: 22)
                                    Text(String(format: "%d:%05.2f", Int(line.start) / 60, line.start.truncatingRemainder(dividingBy: 60)))
                                        .font(.caption2.monospacedDigit()).foregroundStyle(.cyan)
                                    Text(line.text).font(.caption).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 5).padding(.horizontal, 8)
                                .background(index == lineIndex ? Color.yellow.opacity(0.22) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }

        private func timingSection(_ layer: LyricsLayer) -> some View {
            let index = min(max(0, lineIndex), layer.lines.count - 1)
            let line = layer.lines[index]
            let usable = playingBeats(layer)
            return VStack(alignment: .leading, spacing: 8) {
                Text("5. CHỈNH TỪNG TỪ").font(.caption2.bold()).foregroundStyle(.secondary)
                HStack {
                    Button { lineIndex = max(0, index - 1) } label: { Image(systemName: "chevron.left") }.disabled(index == 0)
                    Text("Dòng \(index + 1)/\(layer.lines.count)").font(.caption).frame(maxWidth: .infinity)
                    Button { lineIndex = min(layer.lines.count - 1, index + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(index >= layer.lines.count - 1)
                }
                Text(line.text).font(.callout).lineLimit(2)
                LineTimingEditor(model: model, playback: model.playback, layerID: layerID, layer: layer, lineIndex: index,
                                 beats: usable, snap: snapToBeats)
                if usable.count >= 2 {
                    Toggle("Kéo thanh có hút vào nhịp (vạch cam)", isOn: $snapToBeats).font(.caption)
                }
                HStack {
                    Button { playLine(layer, line) } label: { Label("Nghe dòng này", systemImage: "play.fill") }
                    Spacer()
                    if usable.count >= 2 {
                        Button { moveLine(index, line, beats: usable, forward: false) } label: { Label("Nhịp", systemImage: "chevron.left") }
                            .buttonStyle(.bordered)
                        Button { moveLine(index, line, beats: usable, forward: true) } label: { Label("Nhịp", systemImage: "chevron.right") }
                            .buttonStyle(.bordered)
                    } else {
                        ForEach([-0.1, 0.1], id: \.self) { step in
                            Button(String(format: "Dòng %+.1fs", step)) {
                                model.updateLyrics(layerID) { $0.lines = LyricsSynchronizer.moveLine($0.lines, index: index, toStart: $0.lines[index].start + step) }
                            }.buttonStyle(.bordered)
                        }
                    }
                }.font(.caption)
            }
        }

        private func moveLine(_ index: Int, _ line: LyricLine, beats: [Double], forward: Bool) {
            guard let target = LyricsBeatSync.neighbor(of: line.start, beats: beats, forward: forward) else { return }
            model.updateLyrics(layerID) { $0.lines = LyricsSynchronizer.moveLine($0.lines, index: index, toStart: target) }
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
        var beats: [Double] = []
        var snap = false

        private func snapped(_ time: Double) -> Double {
            snap ? LyricsBeatSync.snapTime(time, beats: beats, threshold: 0.07) : time
        }

        var body: some View {
            if layer.lines.indices.contains(lineIndex) {
                LyricsTimelineView(
                    line: layer.lines[lineIndex], lineIndex: lineIndex,
                    playheadSource: LyricsTiming.sourceTime(layer, in: model.project, at: playback.time),
                    beats: beats,
                    onBeginDrag: { model.beginEdit() },
                    onMoveStart: { word, time in
                        model.updateLyrics(layerID, checkpoint: false) {
                            $0.lines = LyricsSynchronizer.moveBoundary($0.lines, line: lineIndex, word: word, to: snapped(time))
                        }
                    },
                    onMoveEnd: { word, time in
                        model.updateLyrics(layerID, checkpoint: false) {
                            $0.lines = LyricsSynchronizer.setWordEnd($0.lines, line: lineIndex, word: word, to: snapped(time))
                        }
                    })
            }
        }
    }
}
