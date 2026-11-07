import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

private enum EditorTool: String, CaseIterable, Identifiable {
    case clip = "Đoạn"
    case frame = "Khung"
    case captions = "Phụ đề"
    case audio = "Âm thanh"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .clip: return "scissors"
        case .frame: return "aspectratio"
        case .captions: return "captions.bubble"
        case .audio: return "waveform"
        }
    }
}

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @StateObject private var recorder = VoiceRecorder()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedClipID: UUID?
    @State private var activeTool: EditorTool = .clip
    @State private var activeFilePicker: EditorDocumentKind?
    @State private var showDocumentImporter = false
    @State private var subtitleFileForShare: URL?
    @State private var previewPlayer: AVPlayer?
    @State private var localSecond = 0.0
    @State private var isPlaying = false

    private let accent = Color.cyan

    private var selectedClip: TimelineClip? {
        model.clips.first(where: { $0.id == selectedClipID })
    }

    private var playheadSecond: Double {
        guard let selectedClipID, let index = model.clips.firstIndex(where: { $0.id == selectedClipID }) else {
            return 0
        }
        let before = model.clips.prefix(index).reduce(0.0) { $0 + $1.duration }
        return before + localSecond
    }

    private var activeSubtitle: String {
        model.subtitles.first(where: { $0.start <= playheadSecond && $0.end >= playheadSecond })?.text ?? ""
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 6) {
                topBar
                    .padding(.top, 3)

                videoPreview
                    .frame(height: previewHeight(for: geometry.size.height))

                timeline
                toolPicker

                ScrollView {
                    toolPanel
                        .padding(.horizontal, 2)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 15))
            }
            .padding(.horizontal, 12)
            .frame(width: geometry.size.width, height: geometry.size.height,
                   alignment: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            exportBar
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(red: 0.055, green: 0.067, blue: 0.09))
        }
        .background(Color(red: 0.055, green: 0.067, blue: 0.09)
            .ignoresSafeArea())
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            Task {
                await model.importSelections(items)
                pickerItems = []
            }
        }
        .onChange(of: model.clips.count) { _ in
            if !model.clips.contains(where: { $0.id == selectedClipID }) {
                selectedClipID = model.clips.first?.id
            }
        }
        .onChange(of: selectedClipID) { _ in
            updatePreview()
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            guard isPlaying, let player = previewPlayer else { return }
            if let clip = selectedClip {
                localSecond = max(0, player.currentTime().seconds - clip.startTime)
                if localSecond >= clip.duration {
                    player.pause()
                    isPlaying = false
                }
            }
        }
        // One native fileImporter, with no nested UIKit sheet dismissal.
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: activeFilePicker?.allowedTypes ?? [.audio],
            allowsMultipleSelection: false
        ) { result in
            let kind = activeFilePicker
            activeFilePicker = nil
            switch result {
            case .success(let urls):
                guard let kind, let url = urls.first else { return }
                switch kind {
                case .music: model.importMusic(from: url)
                case .voice: model.importVoiceover(from: url)
                case .subtitles: model.importSubtitles(from: url)
                }
            case .failure(let error):
                model.errorText = "Không thể mở tệp: \(error.localizedDescription)"
            }
        }
        .onChange(of: recorder.errorText) { message in
            if let message { model.errorText = message }
        }
        .alert("ViePN Smart Video", isPresented: Binding(
            get: { model.errorText != nil },
            set: { if !$0 { model.errorText = nil } }
        )) {
            Button("Đóng", role: .cancel) { model.errorText = nil }
        } message: {
            Text(model.errorText ?? "")
        }
    }

    private func previewHeight(for availableHeight: CGFloat) -> CGFloat {
        // Height is computed from the content area after respecting the
        // system safe area and the pinned export bar.
        min(300, max(150, availableHeight * 0.36))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack.fill")
                .font(.title3)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("ViePN Smart Video").font(.headline)
                Text("Studio · Offline").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 30,
                         matching: .any(of: [.images, .videos])) {
                Label("Thêm", systemImage: "plus.circle.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(model.isImporting || model.isExporting)
        }
        .frame(height: 42)
    }

    private var videoPreview: some View {
        GeometryReader { geometry in
            let ratio = model.canvas.ratio
            let canvasWidth = max(1, min(geometry.size.width, geometry.size.height * ratio))
            let canvasHeight = canvasWidth / ratio
            let previewCaption = activeSubtitle.isEmpty && activeTool == .captions
                ? "Kéo phụ đề để đổi vị trí"
                : activeSubtitle

            ZStack {
                Color.black
                if let clip = selectedClip {
                    if clip.kind == .image,
                       let image = UIImage(contentsOfFile: clip.fileURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: model.contentMode == .fill ? .fill : .fit)
                            .frame(width: canvasWidth, height: canvasHeight)
                            .clipped()
                    } else if let previewPlayer {
                        VideoPreviewSurface(player: previewPlayer, mode: model.contentMode)
                            .frame(width: canvasWidth, height: canvasHeight)
                            .clipped()
                    }
                } else if activeTool != .captions {
                    Label("Thêm ảnh hoặc video để bắt đầu", systemImage: "video.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }

                if !previewCaption.isEmpty {
                    Text(previewCaption)
                        .font(.system(size: max(11, min(19, canvasWidth * 0.046)),
                                      weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        .frame(width: canvasWidth * 0.72)
                        .background(.black.opacity(0.72),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .position(
                            x: canvasWidth * (0.36 + 0.28 * model.subtitleX),
                            y: canvasHeight * (0.08 + 0.84 * model.subtitleY)
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("captionCanvas"))
                                .onChanged { value in
                                    guard activeTool == .captions else { return }
                                    let px = Double(value.location.x / canvasWidth)
                                    let py = Double(value.location.y / canvasHeight)
                                    model.subtitleX = min(1, max(0, (px - 0.36) / 0.28))
                                    model.subtitleY = min(1, max(0, (py - 0.08) / 0.84))
                                }
                        )
                        .allowsHitTesting(activeTool == .captions)
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .coordinateSpace(name: "captionCanvas")
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(accent.opacity(0.9), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                Text("\(model.canvas.shortLabel) · \(model.contentMode.rawValue)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                    .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                if selectedClip?.kind == .video {
                    Button {
                        guard let player = previewPlayer else { return }
                        if isPlaying {
                            player.pause()
                            isPlaying = false
                        } else {
                            let start = (selectedClip?.startTime ?? 0) + localSecond
                            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
                            player.play()
                            isPlaying = true
                        }
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                    }
                    .padding(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: model.canvas)
        }
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }

    private var timeline: some View {
        VStack(spacing: 4) {
            HStack {
                Label("Timeline", systemImage: "rectangle.3.group")
                    .font(.caption.bold())
                Text("\(model.clips.count) đoạn")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f giây", model.totalDuration))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            if model.clips.isEmpty {
                Text("Bấm Thêm để nhập video hoặc ảnh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 67)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.clips) { clip in
                            Button {
                                selectedClipID = clip.id
                                activeTool = .clip
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(Color.white.opacity(0.1))
                                        if clip.kind == .image,
                                           let image = UIImage(contentsOfFile: clip.fileURL.path) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                                .frame(width: 76, height: 46).clipped()
                                        } else {
                                            Image(systemName: "film.fill").foregroundStyle(accent)
                                        }
                                    }
                                    .frame(width: 76, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    Text(String(format: "%.1fs", clip.duration))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.white)
                                }
                                .padding(4)
                                .background(selectedClipID == clip.id
                                            ? accent.opacity(0.2) : Color.white.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 9))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(selectedClipID == clip.id ? accent : .clear,
                                                lineWidth: 1.5)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(height: 96, alignment: .top)
    }

    private var toolPicker: some View {
        HStack(spacing: 5) {
            ForEach(EditorTool.allCases) { tool in
                Button {
                    activeTool = tool
                    previewPlayer?.pause()
                    isPlaying = false
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.symbol).font(.system(size: 16))
                        Text(tool.rawValue).font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(activeTool == tool ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(activeTool == tool ? accent : Color.white.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch activeTool {
        case .clip: clipPanel
        case .frame: framePanel
        case .captions: subtitlePanel
        case .audio: audioPanel
        }
    }

    @ViewBuilder
    private var clipPanel: some View {
        if let clip = selectedClip {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(clip.filename).font(.caption).lineLimit(1)
                    Spacer()
                    Button {
                        model.moveClip(id: clip.id, delta: -1)
                    } label: { Image(systemName: "arrow.left.circle") }
                    Button {
                        model.moveClip(id: clip.id, delta: 1)
                    } label: { Image(systemName: "arrow.right.circle") }
                    Button(role: .destructive) {
                        model.removeClip(id: clip.id)
                    } label: { Image(systemName: "trash") }
                }

                if clip.kind == .video {
                    HStack {
                        Text("Điểm vào")
                        Spacer()
                        Text(String(format: "%.1fs", clip.startTime))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    Slider(value: startBinding(clip.id),
                           in: 0...max(0, clip.originalDuration - 0.1),
                           step: 0.1)
                        .tint(accent)
                }

                HStack {
                    Text("Thời lượng").font(.caption)
                    Spacer()
                    Button("−0.5s") { changeDuration(clip.id, by: -0.5) }
                        .buttonStyle(.bordered)
                    Text(String(format: "%.1fs", clip.duration))
                        .font(.caption.monospacedDigit())
                    Button("+0.5s") { changeDuration(clip.id, by: 0.5) }
                        .buttonStyle(.bordered)
                }
                Slider(value: durationBinding(clip.id),
                       in: 0.1...max(0.1, clip.availableDuration),
                       step: 0.1)
                    .tint(accent)
            }
            .padding(10)
        } else {
            Text("Chọn một đoạn trên timeline để chỉnh sửa.")
                .font(.subheadline).foregroundStyle(.secondary).padding(12)
        }
    }

    private var framePanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Chọn tỷ lệ khung hình")
                .font(.subheadline.bold())

            HStack(spacing: 7) {
                ForEach(CanvasFormat.allCases) { format in
                    Button {
                        model.canvas = format
                    } label: {
                        Text(format.shortLabel)
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(model.canvas == format ? .black : .white)
                            .background(
                                model.canvas == format ? accent : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            let pixels = model.canvas.size(for: model.quality)
            Text("Đang chọn: \(model.canvas.rawValue) · \(Int(pixels.width)) × \(Int(pixels.height)) px")
                .font(.caption)
                .foregroundStyle(accent)

            Text("Ảnh/video trong khung")
                .font(.caption.bold())
            Picker("Chế độ cắt", selection: $model.contentMode) {
                ForEach(CanvasContentMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Text("Độ phân giải xuất")
                .font(.caption.bold())
            Picker("Chất lượng", selection: $model.quality) {
                ForEach(RenderQuality.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Text("Khung viền xanh trong phần xem trước chính là tỷ lệ sẽ được xuất. Phủ đầy cắt phần ngoài khung; Vừa khung giữ trọn hình.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var subtitlePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Vị trí phụ đề · kéo trực tiếp trên khung xem trước")
                    .font(.caption.bold())
                HStack(spacing: 7) {
                    Button("Phía trên") {
                        model.subtitleX = 0.5
                        model.subtitleY = 0.07
                    }
                    Button("Chính giữa") {
                        model.subtitleX = 0.5
                        model.subtitleY = 0.5
                    }
                    Button("Phía dưới") {
                        model.subtitleX = 0.5
                        model.subtitleY = 0.90
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption2)

                HStack {
                    Text("Ngang")
                    Spacer()
                    Text("\(Int(model.subtitleX * 100))%")
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(value: $model.subtitleX, in: 0...1)
                    .tint(accent)

                HStack {
                    Text("Dọc")
                    Spacer()
                    Text("\(Int(model.subtitleY * 100))%")
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(value: $model.subtitleY, in: 0...1)
                    .tint(accent)
            }
            .padding(7)
            .background(Color.white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 7) {
                Button {
                    activeFilePicker = .subtitles
                    showDocumentImporter = true
                } label: {
                    Label("Nhập TXT/SRT", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                Button {
                    model.addSubtitle()
                } label: {
                    Label("Thêm câu", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                if !model.subtitles.isEmpty {
                    Button("Tạo SRT") {
                        subtitleFileForShare = model.exportSRT()
                    }.buttonStyle(.bordered)
                }
            }
            .font(.caption)

            if let subtitleFileForShare {
                ShareLink(item: subtitleFileForShare) {
                    Label("Chia sẻ file SRT đã tạo", systemImage: "square.and.arrow.up")
                }
                .font(.caption)
            }

            if model.subtitles.isEmpty {
                Text("Nhập TXT để chia câu theo thời lượng video, hoặc SRT để giữ thời gian gốc. Phụ đề sẽ xuất hiện trên video MP4.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach($model.subtitles) { $cue in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Nội dung phụ đề", text: $cue.text, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(1...3)
                            .textFieldStyle(.roundedBorder)
                        Button(role: .destructive) {
                            model.subtitles.removeAll { $0.id == cue.id }
                        } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f → %.1fs", cue.start, cue.end))
                            .font(.caption2.monospacedDigit())
                        Spacer()
                        Button("← 0.5s") {
                            let distance = min(0.5, cue.start)
                            cue.start -= distance
                            cue.end -= distance
                        }
                        Button("0.5s →") {
                            cue.start += 0.5
                            cue.end += 0.5
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
                .padding(6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    activeFilePicker = .music
                    showDocumentImporter = true
                } label: {
                    Label("Nhạc MP3", systemImage: "music.note")
                }
                .buttonStyle(.bordered)

                Button {
                    activeFilePicker = .voice
                    showDocumentImporter = true
                } label: {
                    Label("Tệp giọng đọc", systemImage: "mic")
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)

            HStack {
                Button {
                    if recorder.isRecording {
                        model.voiceoverURL = recorder.stop()
                    } else {
                        recorder.start()
                    }
                } label: {
                    Label(recorder.isRecording ? "Dừng và dùng bản ghi" : "Ghi thuyết minh",
                          systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .cyan)
                Spacer()
                if model.voiceoverURL != nil {
                    Button(role: .destructive) {
                        model.voiceoverURL = nil
                    } label: {
                        Label("Xóa giọng", systemImage: "xmark.circle")
                    }
                    .font(.caption)
                }
            }

            if let voice = model.voiceoverURL {
                Text("Thuyết minh: \(voice.lastPathComponent)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }

            if model.isImportingAudio {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Đang kiểm tra tệp MP3…").font(.caption)
                }
            }

            if let music = model.musicURL {
                HStack {
                    Text("Nhạc: \(music.lastPathComponent)")
                        .font(.caption).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) {
                        model.musicURL = nil
                        model.musicDuration = 0
                    } label: { Image(systemName: "xmark.circle.fill") }
                }

                HStack {
                    Text("Cắt nhạc từ")
                    Spacer()
                    Text(String(format: "%.1fs", model.musicStartSeconds))
                        .monospacedDigit()
                }.font(.caption)

                Button {
                    model.suggestMusicCut()
                } label: {
                    Label(model.isScanningMusic ? "Đang dò tiếng nhạc…" : "Tự bỏ phần mở đầu im lặng",
                          systemImage: "wand.and.stars")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(model.isScanningMusic)

                Slider(value: $model.musicStartSeconds,
                       in: 0...max(0.1, model.musicDuration - 0.1),
                       step: 0.5)
                    .tint(accent)

                Toggle("Tự lặp nhạc nếu ngắn hơn video", isOn: $model.repeatShortMusic)
                    .font(.caption)
                HStack {
                    Text("Âm lượng nhạc")
                    Spacer()
                    Text("\(Int(model.musicVolume * 100))%")
                }.font(.caption)
                Slider(value: $model.musicVolume, in: 0...1)
                    .tint(accent)
                Text("Tự dừng đúng cuối video, fade-out 1.2 giây và giảm nhạc trong lúc thuyết minh.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Toggle("Giữ tiếng gốc của các clip", isOn: $model.keepOriginalAudio)
                .font(.caption)
        }
        .padding(10)
    }

    private var exportBar: some View {
        VStack(spacing: 6) {
            if model.isImporting {
                HStack {
                    ProgressView()
                    Text("Đang nhập media…").font(.caption)
                }
            }
            if model.isExporting {
                HStack {
                    ProgressView()
                    Text("Đang render — giữ ứng dụng mở").font(.caption)
                }
            }
            if let result = model.exportedURL {
                HStack {
                    Button {
                        Task { await model.saveToPhotos() }
                    } label: {
                        Label(model.didSaveToPhotos ? "Đã lưu" : "Lưu vào Ảnh",
                              systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.didSaveToPhotos)
                    ShareLink(item: result) {
                        Label("Chia sẻ MP4", systemImage: "square.and.arrow.up")
                    }
                }
                .font(.caption)
            }

            Button {
                previewPlayer?.pause()
                isPlaying = false
                model.export()
            } label: {
                HStack {
                    Spacer()
                    Label("Xuất video MP4 · \(model.quality.rawValue)", systemImage: "square.and.arrow.up.fill")
                        .font(.headline)
                    Spacer()
                }
                .frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(model.clips.isEmpty || model.isImporting || model.isExporting)
        }
    }

    private func startBinding(_ id: UUID) -> Binding<Double> {
        Binding {
            model.clips.first(where: { $0.id == id })?.startTime ?? 0
        } set: { newValue in
            guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
            model.clips[index].startTime = newValue
            model.clips[index].duration = min(model.clips[index].duration,
                                               model.clips[index].availableDuration)
            localSecond = 0
            updatePreview()
        }
    }

    private func durationBinding(_ id: UUID) -> Binding<Double> {
        Binding {
            model.clips.first(where: { $0.id == id })?.duration ?? 1
        } set: { newValue in
            guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
            model.clips[index].duration = max(0.1,
                min(newValue, model.clips[index].availableDuration))
        }
    }

    private func changeDuration(_ id: UUID, by amount: Double) {
        guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
        model.clips[index].duration = max(0.1,
            min(model.clips[index].duration + amount, model.clips[index].availableDuration))
    }

    private func updatePreview() {
        previewPlayer?.pause()
        isPlaying = false
        localSecond = 0
        guard let clip = selectedClip, clip.kind == .video else {
            previewPlayer = nil
            return
        }
        let player = AVPlayer(url: clip.fileURL)
        player.seek(to: CMTime(seconds: clip.startTime, preferredTimescale: 600))
        previewPlayer = player
    }
}

private final class PlayerSurface: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct VideoPreviewSurface: UIViewRepresentable {
    var player: AVPlayer
    var mode: CanvasContentMode

    func makeUIView(context: Context) -> PlayerSurface {
        let surface = PlayerSurface()
        surface.backgroundColor = .black
        return surface
    }

    func updateUIView(_ uiView: PlayerSurface, context: Context) {
        uiView.videoLayer.player = player
        uiView.videoLayer.videoGravity = mode == .fill ? .resizeAspectFill : .resizeAspect
    }
}
