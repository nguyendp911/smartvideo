import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

private enum EditorTool: String, CaseIterable, Identifiable {
    case clip = "Đoạn"
    case frame = "Khung"
    case vfx = "VFX"
    case captions = "Phụ đề"
    case audio = "Âm thanh"
    case effects = "Hiệu ứng"
    case ai = "AI"
    case narration = "Giọng"
    case metadata = "Metadata"
    case overlay = "Overlay"
    case pip = "Video PIP"
    case title = "Chữ"
    case sfx = "Âm FX"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .clip: return "scissors"
        case .frame: return "aspectratio"
        case .vfx: return "wand.and.stars"
        case .captions: return "captions.bubble"
        case .audio: return "waveform"
        case .effects: return "wand.and.stars"
        case .ai: return "sparkles"
        case .narration: return "mic.circle"
        case .metadata: return "tag"
        case .overlay: return "square.on.square"
        case .pip: return "pip"
        case .title: return "textformat"
        case .sfx: return "waveform"
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
    @State private var showProjects = false
    @State private var showRenderedPreview = false
    @State private var pickedOverlay: PhotosPickerItem?
    @State private var selectedOverlayID: UUID?
    @State private var pickedPIP: PhotosPickerItem?
    @State private var selectedPIPID: UUID?
    @State private var selectedTextID: UUID?
    @State private var selectedSoundID: UUID?

    private let accent = Color.cyan

    private var selectedClip: TimelineClip? {
        model.clips.first(where: { $0.id == selectedClipID })
    }

    private var playheadSecond: Double {
        guard let selectedClipID, let index = model.clips.firstIndex(where: { $0.id == selectedClipID }) else {
            return 0
        }
        return model.timelineStart(of: index) + localSecond
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
        .onChange(of: pickedPIP) { item in
            guard let item else { return }
            Task {
                await model.importVideoOverlay(item)
                selectedPIPID = model.videoOverlays.last?.id
                pickedPIP = nil
            }
        }
        .onChange(of: pickedOverlay) { item in
            guard let item else { return }
            Task {
                await model.importImageOverlay(item)
                selectedOverlayID = model.imageOverlays.last?.id
                pickedOverlay = nil
            }
        }
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
                localSecond = max(0, (player.currentTime().seconds - clip.startTime) / max(0.25, clip.playbackSpeed))
                if let index = model.clips.firstIndex(where: { $0.id == clip.id }) {
                    model.timelineSecond = min(model.totalDuration,
                        model.timelineStart(of: index) + localSecond)
                }
                if localSecond >= clip.renderedDuration {
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
                case .soundEffect:
                    model.importSoundEffect(from: url)
                }
            case .failure(let error):
                model.errorText = "Không thể mở tệp: \(error.localizedDescription)"
            }
        }
        .onChange(of: model.renderedPreviewURL) { url in
            if url != nil { showRenderedPreview = true }
        }
        .sheet(isPresented: $showRenderedPreview) {
            if let file = model.renderedPreviewURL {
                RenderedPreviewSheet(url: file)
            }
        }
        .sheet(isPresented: $showProjects) {
            ProjectLibrarySheet(model: model) {
                selectedClipID = model.clips.first?.id
                model.timelineSecond = 0
                updatePreview()
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
        min(255, max(135, availableHeight * 0.31))
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "film.stack.fill")
                .font(.title3)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("ViePN Smart Video").font(.subheadline.bold()).lineLimit(1)
                Text("Studio · Offline").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { showProjects = true } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Dự án")
            Menu {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        activeTool = tool
                        previewPlayer?.pause()
                        isPlaying = false
                    } label: {
                        Label(tool.rawValue, systemImage: tool.symbol)
                    }
                }
            } label: {
                Label("Công cụ", systemImage: "square.grid.2x2")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
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
                            .scaleEffect(x: clip.flipHorizontal ? -1 : 1,
                                         y: clip.flipVertical ? -1 : 1)
                            .clipped()
                    } else if let previewPlayer {
                        VideoPreviewSurface(player: previewPlayer, mode: model.contentMode)
                            .frame(width: canvasWidth, height: canvasHeight)
                            .scaleEffect(x: clip.flipHorizontal ? -1 : 1,
                                         y: clip.flipVertical ? -1 : 1)
                            .clipped()
                    }
                } else if activeTool != .captions {
                    Label("Thêm ảnh hoặc video để bắt đầu", systemImage: "video.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(6)
                }

                VideoPIPCanvasPreview(
                    model: model, selectedID: $selectedPIPID,
                    second: playheadSecond,
                    canvas: CGSize(width: canvasWidth, height: canvasHeight),
                    editable: activeTool == .pip
                )

                if !model.vfxPresets.isEmpty {
                    VFXPreviewOverlay(presets: model.vfxPresets,
                                      intensity: model.vfxIntensity)
                        .frame(width: canvasWidth, height: canvasHeight)
                        .allowsHitTesting(false)
                }

                // Preview independent image overlays only during their
                // active time range. Drag to reposition start keyframe.
                ForEach(model.imageOverlays) { overlay in
                    if playheadSecond >= overlay.start && playheadSecond <= overlay.end,
                       let index = model.imageOverlays.firstIndex(where: { $0.id == overlay.id }),
                       FileManager.default.fileExists(atPath: overlay.fileURL.path) {
                        let fraction = min(1, max(0,
                            (playheadSecond - overlay.start) / max(0.1, overlay.duration)))
                        let currentX = overlay.startX + (overlay.endX - overlay.startX) * fraction
                        let currentY = overlay.startY + (overlay.endY - overlay.startY) * fraction
                        KeyedOverlayImage(overlay: overlay)
                            .frame(width: canvasWidth * CGFloat(overlay.scale))
                            .opacity(overlay.opacity)
                            .rotationEffect(.degrees(overlay.rotationDegrees))
                            .position(
                                x: canvasWidth * CGFloat(currentX),
                                y: canvasHeight * CGFloat(currentY)
                            )
                            .overlay {
                                if activeTool == .overlay &&
                                    selectedOverlayID == overlay.id {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.cyan, lineWidth: 1)
                                        .frame(width: canvasWidth * CGFloat(overlay.scale))
                                        .position(
                                            x: canvasWidth * CGFloat(currentX),
                                            y: canvasHeight * CGFloat(currentY)
                                        )
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0,
                                            coordinateSpace: .named("captionCanvas"))
                                    .onChanged { value in
                                        guard activeTool == .overlay else { return }
                                        selectedOverlayID = overlay.id
                                        let nextX = min(0.95, max(0.05,
                                            Double(value.location.x / canvasWidth)))
                                        let nextY = min(0.95, max(0.05,
                                            Double(value.location.y / canvasHeight)))
                                        // Move both keyframes by the same delta,
                                        // preserving the configured motion path.
                                        let deltaX = nextX - currentX
                                        let deltaY = nextY - currentY
                                        model.imageOverlays[index].startX =
                                            min(0.95, max(0.05, overlay.startX + deltaX))
                                        model.imageOverlays[index].startY =
                                            min(0.95, max(0.05, overlay.startY + deltaY))
                                        model.imageOverlays[index].endX =
                                            min(0.95, max(0.05, overlay.endX + deltaX))
                                        model.imageOverlays[index].endY =
                                            min(0.95, max(0.05, overlay.endY + deltaY))
                                    }
                            )
                            .allowsHitTesting(activeTool == .overlay)
                    }
                }

                TextCanvasPreview(
                    model: model, selectedID: $selectedTextID,
                    second: playheadSecond,
                    canvas: CGSize(width: canvasWidth, height: canvasHeight),
                    editable: activeTool == .title
                )

                if !previewCaption.isEmpty {
                    KaraokeSubtitlePreview(
                        text: previewCaption,
                        cue: model.subtitles.first(where: {
                            $0.start <= playheadSecond && $0.end >= playheadSecond
                        }),
                        appearance: model.subtitleAppearance,
                        playhead: playheadSecond
                    )
                        .font(.system(size: max(10, min(28,
                            canvasWidth * 0.046 * CGFloat(model.subtitleAppearance.fontScale))),
                                      weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(uiColor: TextOverlayRenderer.uiColor(
                            hex: model.subtitleAppearance.foregroundHex
                        )))
                        .shadow(color: model.subtitleAppearance.shadowEnabled ?
                                .black.opacity(0.85) : .clear,
                                radius: 2, x: 1, y: 1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                        .frame(width: canvasWidth * 0.72)
                        .background(.black.opacity(
                            model.subtitleAppearance.backgroundOpacity),
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
                            player.playImmediately(atRate: Float(selectedClip?.playbackSpeed ?? 1))
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
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                Label("Timeline", systemImage: "rectangle.3.group")
                    .font(.caption.bold())
                Text("\(model.clips.count) clip")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(timecode(model.timelineSecond) + " / " + timecode(model.totalDuration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.cyan)
            }

            if model.clips.isEmpty {
                Text("Bấm Thêm để nhập video hoặc ảnh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 58)
            } else {
                Slider(value: Binding(
                    get: { min(model.totalDuration, max(0, model.timelineSecond)) },
                    set: { scrubTimeline(to: $0) }
                ), in: 0...max(0.1, model.totalDuration), step: 0.04)
                    .tint(.cyan)
                    .accessibilityLabel("Tua tới vị trí trên timeline")

                if !model.timelineBeatMarkers.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "metronome")
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                        BeatTimelineStrip(
                            beatPositions: model.timelineBeatMarkers,
                            totalDuration: model.totalDuration
                        )
                        .frame(height: 12)
                        Text(String(format: "~%.0f BPM", model.detectedTempoBPM))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.cyan)
                    }
                    .frame(height: 16)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(model.clips.enumerated()), id: \.element.id) { index, clip in
                            Button {
                                selectClip(clip, at: index)
                                activeTool = .clip
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.white.opacity(0.09))
                                        TimelineThumbnail(clip: clip)
                                            .frame(width: timelineClipWidth(clip), height: 35)
                                            .clipped()
                                    }
                                    .frame(width: timelineClipWidth(clip), height: 35)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text("\(index + 1) · " +
                                         String(format: "%.1fs", clip.renderedDuration))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.white)
                                }
                                .padding(3)
                                .background(
                                    selectedClipID == clip.id ?
                                        Color.cyan.opacity(0.22) : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(
                                            selectedClipID == clip.id ? Color.cyan : .clear,
                                            lineWidth: 1.3
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .draggable(clip.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                guard let first = items.first,
                                      let dragged = UUID(uuidString: first) else {
                                    return false
                                }
                                model.reorderClip(draggedID: dragged, before: clip.id)
                                return true
                            }
                        }
                    }
                }
            }
            if !model.soundEffects.isEmpty {
                HStack(spacing: 6) {
                    Text("FX")
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.cyan.opacity(0.08))
                            ForEach(model.soundEffects) { item in
                                Button {
                                    selectedSoundID = item.id
                                    activeTool = .sfx
                                    scrubTimeline(to: item.start)
                                } label: {
                                    Text("♫ " + item.filename)
                                        .font(.system(size: 8))
                                        .lineLimit(1)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 3)
                                        .frame(maxWidth: .infinity,
                                               maxHeight: .infinity)
                                        .background(
                                            selectedSoundID == item.id ?
                                                Color.cyan.opacity(0.63) :
                                                Color.blue.opacity(0.55),
                                            in: RoundedRectangle(cornerRadius: 4)
                                        )
                                }
                                .buttonStyle(.plain)
                                .frame(
                                    width: max(14, geo.size.width *
                                        CGFloat(min(1, item.duration /
                                            max(0.1, model.totalDuration)))),
                                    height: 24
                                )
                                .offset(
                                    x: geo.size.width * CGFloat(
                                        min(1, max(0, item.start /
                                            max(0.1, model.totalDuration)))
                                    )
                                )
                            }
                        }
                        .clipped()
                    }
                    .frame(height: 24)
                }
                .frame(height: 27)
            }
            HStack(spacing: 9) {
                Button {
                    model.undoEdit()
                    scrubTimeline(to: model.timelineSecond)
                } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)

                Button {
                    model.redoEdit()
                    scrubTimeline(to: model.timelineSecond)
                } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)

                Spacer(minLength: 2)

                Text("Zoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $model.timelineZoom, in: 0.5...3.0, step: 0.25)
                    .frame(width: 88)
                    .tint(.cyan)

                Button {
                    if let id = model.splitClip(at: model.timelineSecond) {
                        selectedClipID = id
                        scrubTimeline(to: model.timelineSecond)
                    }
                } label: {
                    Label("Tách", systemImage: "scissors")
                }
                .disabled(model.clips.isEmpty)
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .frame(height: (model.soundEffects.isEmpty ? 154 : 186) +
               (model.timelineBeatMarkers.isEmpty ? 0 : 17),
               alignment: .top)
    }

    private func timecode(_ second: Double) -> String {
        let centiseconds = Int((max(0, second) * 100).rounded())
        return String(format: "%02d:%02d.%02d",
                      centiseconds / 6000, (centiseconds / 100) % 60,
                      centiseconds % 100)
    }

    private func timelineClipWidth(_ clip: TimelineClip) -> CGFloat {
        CGFloat(min(180, max(48, clip.renderedDuration * 14 * model.timelineZoom)))
    }

    private func selectClip(_ clip: TimelineClip, at index: Int) {
        model.timelineSecond = model.timelineStart(of: index)
        selectedClipID = clip.id
        localSecond = 0
    }

    private func scrubTimeline(to time: Double) {
        previewPlayer?.pause()
        isPlaying = false
        let seconds = min(model.totalDuration, max(0, time))
        model.timelineSecond = seconds
        guard let position = model.clipAtTimeline(seconds) else { return }
        let clip = model.clips[position.index]
        if selectedClipID != clip.id {
            selectedClipID = clip.id
            updatePreview()
        }
        localSecond = position.local
        if clip.kind == .video {
            let seek = clip.startTime + position.local * clip.playbackSpeed
            previewPlayer?.seek(to: CMTime(seconds: seek, preferredTimescale: 600),
                                toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private var toolPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EditorTool.allCases) { tool in
                    Button {
                        activeTool = tool
                        previewPlayer?.pause()
                        isPlaying = false
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 15))
                            Text(tool.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(activeTool == tool ? .black : .white)
                        .frame(width: 82, height: 49)
                        .background(
                            activeTool == tool ? accent : Color.white.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 54)
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch activeTool {
        case .clip: clipPanel
        case .frame: framePanel
        case .vfx: VFXLibraryPanel(model: model)
        case .captions: subtitlePanel
        case .audio: audioPanel
        case .effects: effectsPanel
        case .ai: highlightPanel
        case .narration: NarrationStudioPanel(model: model, recorder: recorder) {
            activeFilePicker = .voice
            showDocumentImporter = true
        }
        case .metadata: MetadataPanel(model: model)
        case .overlay: OverlayStudioPanel(model: model,
                                           selectedOverlayID: $selectedOverlayID,
                                           pickedOverlay: $pickedOverlay)
        case .pip: VideoPIPStudioPanel(model: model,
                                       selectedID: $selectedPIPID,
                                       pickerItem: $pickedPIP)
        case .title: TextOverlayStudioPanel(model: model,
                                            selectedID: $selectedTextID)
        case .sfx: SoundEffectsStudioPanel(model: model,
                                          selectedID: $selectedSoundID) {
            activeFilePicker = .soundEffect
            showDocumentImporter = true
        }
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
                    Button {
                        if let id = model.duplicateClip(id: clip.id) {
                            selectedClipID = id
                            activeTool = .clip
                        }
                    } label: { Image(systemName: "plus.square.on.square") }
                    .accessibilityLabel("Nhân bản clip")
                    Button(role: .destructive) {
                        model.removeClip(id: clip.id)
                        scrubTimeline(to: model.timelineSecond)
                    } label: { Image(systemName: "trash") }
                }

                HStack(spacing: 8) {
                    Button {
                        toggleFlip(clip.id, horizontal: true)
                    } label: {
                        Label("Lật ngang", systemImage: "arrow.left.and.right")
                    }
                    .tint(clip.flipHorizontal ? .cyan : .gray)
                    Button {
                        toggleFlip(clip.id, horizontal: false)
                    } label: {
                        Label("Lật dọc", systemImage: "arrow.up.and.down")
                    }
                    .tint(clip.flipVertical ? .cyan : .gray)
                }
                .font(.caption)
                .buttonStyle(.bordered)

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

    private var effectsPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Button {
                model.applyCinematicPreset()
            } label: {
                HStack {
                    Image(systemName: "sparkles.rectangle.stack")
                    VStack(alignment: .leading) {
                        Text("Dựng phong cách điện ảnh")
                            .font(.subheadline.bold())
                        Text("Tự chọn chuyển cảnh và chuyển động cho ảnh")
                            .font(.caption2)
                            .opacity(0.85)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(model.clips.isEmpty)

            Text("Chuyển cảnh giữa các đoạn")
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                ForEach(VideoTransition.allCases) { type in
                    Button {
                        model.transition = type
                    } label: {
                        Label(type.rawValue, systemImage: type.iconName)
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(model.transition == type ? .black : .white)
                            .background(
                                model.transition == type ? accent : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            if model.transition == .dissolve {
                HStack {
                    Text("Thời lượng hòa tan")
                    Spacer()
                    Text(String(format: "%.2fs", model.transitionSeconds))
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(value: $model.transitionSeconds, in: 0.2...0.8, step: 0.05)
                    .tint(accent)
                Text("Hai đoạn chồng hình và hòa tan thực sự khi xuất video. Thời lượng cuối được tự điều chỉnh.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            if let clip = selectedClip {
                Text("Hiệu ứng đoạn đang chọn")
                    .font(.subheadline.bold())
                Text(clip.filename)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                if clip.kind == .video {
                    HStack {
                        Text("Tốc độ")
                        Spacer()
                        Text(String(format: "%.1fx · %.1f giây", clip.playbackSpeed,
                                    clip.renderedDuration))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    HStack(spacing: 6) {
                        ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { speed in
                            Button(String(format: "%.1fx", speed)) {
                                updateSpeed(clip.id, to: speed)
                            }
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(abs(clip.playbackSpeed - speed) < 0.01 ?
                                             .black : .white)
                            .background(
                                abs(clip.playbackSpeed - speed) < 0.01 ?
                                    accent : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Tốc độ không làm méo khung hình; giọng gốc có thể đổi cao độ ở một số codec.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("Chuyển động ảnh kiểu Ken Burns")
                        .font(.caption.bold())
                    imageMotionGrid(clip: clip)

                    Text("Màu sắc ảnh")
                        .font(.caption.bold())
                    imageLookGrid(clip: clip)

                    Text("Hiệu ứng chuyển động và màu được xử lý bằng Core Image khi xuất MP4. Màu áp dụng cho ảnh tĩnh, chưa áp dụng cho clip video.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Hãy chọn một ảnh hoặc video trên timeline để chỉnh tốc độ, hiệu ứng và màu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private func imageMotionGrid(clip: TimelineClip) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                  spacing: 7) {
            ForEach(ImageMotion.allCases) { motion in
                Button(motion.rawValue) {
                    updateImageMotion(clip.id, to: motion)
                }
                .font(.caption2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(clip.imageMotion == motion ? .black : .white)
                .background(
                    clip.imageMotion == motion ? accent : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .buttonStyle(.plain)
            }
        }
    }

    private func imageLookGrid(clip: TimelineClip) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                  spacing: 7) {
            ForEach(ImageLook.allCases) { look in
                Button(look.rawValue) {
                    updateImageLook(clip.id, to: look)
                }
                .font(.caption2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(clip.imageLook == look ? .black : .white)
                .background(
                    clip.imageLook == look ? accent : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .buttonStyle(.plain)
            }
        }
    }

    private func updateSpeed(_ id: UUID, to speed: Double) {
        guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
        model.clips[index].playbackSpeed = speed
        if isPlaying, let player = previewPlayer {
            player.rate = Float(speed)
        }
    }

    private func updateImageMotion(_ id: UUID, to motion: ImageMotion) {
        guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
        model.clips[index].imageMotion = motion
    }

    private func updateImageLook(_ id: UUID, to look: ImageLook) {
        guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
        model.clips[index].imageLook = look
    }

    private func toggleFlip(_ id: UUID, horizontal: Bool) {
        guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
        if horizontal {
            model.clips[index].flipHorizontal.toggle()
        } else {
            model.clips[index].flipVertical.toggle()
        }
    }

    private var highlightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
                Text("Smart Highlights – xử lý trên iPhone")
                    .font(.subheadline.bold())
            }
            Text("AI Vision nhận diện khuôn mặt, vùng gây chú ý và thay đổi cảnh. Highlight nhạc dựa trên tín hiệu âm lượng, không hiểu lời bài hát.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()
            Text("Video nổi bật")
                .font(.subheadline.bold())

            if let clip = selectedClip, clip.kind == .video {
                Text("Nguồn: \(clip.filename)")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Button {
                    model.suggestVideoHighlights(for: clip)
                } label: {
                    Label(model.isAnalyzingVideoHighlights ?
                          "Đang tìm cảnh nổi bật…" : "Phân tích video",
                          systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isAnalyzingVideoHighlights)

                if model.isAnalyzingVideoHighlights {
                    ProgressView("Đang phân tích các khung hình bằng Vision…")
                        .font(.caption2)
                }

                if model.analyzedClipID == clip.id && !model.videoHighlights.isEmpty {
                    ForEach(model.videoHighlights) { sample in
                        HStack(spacing: 7) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.1fs – %.1fs",
                                            sample.start,
                                            sample.start + sample.duration))
                                    .font(.caption.monospacedDigit())
                                Text(sample.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Lấy đoạn") {
                                if let id = model.applyVideoHighlights(
                                    clipID: clip.id, selected: [sample]
                                ) {
                                    selectedClipID = id
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(6)
                        .background(Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 8))
                    }
                    Button {
                        if let id = model.applyVideoHighlights(
                            clipID: clip.id,
                            selected: model.videoHighlights
                        ) {
                            selectedClipID = id
                        }
                    } label: {
                        Label("Tạo montage từ các highlight", systemImage: "film.stack")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Chọn một clip video trên Timeline để AI đề xuất đoạn nổi bật.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.previousTimeline != nil {
                Button {
                    model.undoHighlights()
                    selectedClipID = model.clips.first?.id
                } label: {
                    Label("Hoàn tác lần lấy highlight gần nhất",
                          systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
            }

            Divider()
            Text("Nhạc MP3 nổi bật")
                .font(.subheadline.bold())
            if model.musicURL == nil {
                Button {
                    activeFilePicker = .music
                    showDocumentImporter = true
                } label: {
                    Label("Chọn nhạc MP3 hoặc M4A", systemImage: "music.note")
                }
                .buttonStyle(.bordered)
            } else {
                Text(model.musicURL?.lastPathComponent ?? "Đã chọn nhạc")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Picker("Độ dài", selection: $model.musicHighlightLength) {
                    Text("15 giây").tag(15.0)
                    Text("20 giây").tag(20.0)
                    Text("30 giây").tag(30.0)
                }
                .pickerStyle(.segmented)

                Button {
                    model.suggestMusicHighlights()
                } label: {
                    Label(model.isAnalyzingMusicHighlights ?
                          "Đang phân tích nhạc…" : "Tìm đoạn nhạc cao trào",
                          systemImage: "waveform.path")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isAnalyzingMusicHighlights || model.isImportingAudio)

                if model.isAnalyzingMusicHighlights {
                    ProgressView("Đang phân tích mức âm lượng và độ biến thiên…")
                        .font(.caption2)
                }

                ForEach(model.musicHighlights) { highlight in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(String(format: "%.1fs – %.1fs",
                                        highlight.start,
                                        highlight.start + highlight.duration))
                                .font(.caption.monospacedDigit())
                            Text(String(format: "Điểm tín hiệu %.0f%%",
                                        highlight.score * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Lấy đoạn") {
                            model.useMusicHighlight(highlight)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if model.musicHighlightDuration > 0 {
                    Button {
                        model.exportMusicHighlight()
                    } label: {
                        Label(model.isExportingMusicHighlight ?
                              "Đang xuất M4A…" :
                              "Cắt và lưu highlight thành M4A",
                              systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isExportingMusicHighlight)
                    if let output = model.exportedMusicHighlightURL {
                        ShareLink(item: output) {
                            Label("Chia sẻ highlight M4A đã cắt",
                                  systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(String(format: "Đang dùng %.1f giây nhạc từ mốc %.1fs",
                                model.musicHighlightDuration,
                                model.musicStartSeconds))
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }
            }
            Text("Đây là gợi ý tự động, không xóa file nguồn. Các video dài được lấy mẫu giới hạn nên có thể bỏ lỡ cảnh hay.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
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
            Divider()
            Toggle("Không giữ metadata của video gốc", isOn: $model.stripMetadata)
                .font(.caption)
            Text("Lọc GPS, camera, tác giả, tiêu đề và thông tin nguồn khi xuất. Tệp MP4 vẫn có metadata kỹ thuật do iOS tạo.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Khung viền xanh trong phần xem trước chính là tỷ lệ sẽ được xuất. Phủ đầy cắt phần ngoài khung; Vừa khung giữ trọn hình.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var subtitlePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            AutoCaptionStudioPanel(model: model, selectedClipID: selectedClipID)
            SubtitleStylePanel(model: model)
            Divider()
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
                        if cue.hasAlignedWords {
                            Text("\(cue.words.count) từ")
                                .font(.caption2)
                                .foregroundStyle(.cyan)
                        }
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

                    if !cue.words.isEmpty {
                        KaraokeWordEditor(cue: $cue)
                    }
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

                Button {
                    activeTool = .sfx
                } label: {
                    Label("Âm FX", systemImage: "waveform")
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
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack {
                    Text("Giọng bắt đầu tại")
                    Spacer()
                    Text(String(format: "%.1fs", model.voiceoverOffset))
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(value: $model.voiceoverOffset,
                       in: 0...max(0.1, model.totalDuration - 0.1),
                       step: 0.1)
                    .tint(.cyan)
                HStack {
                    Text("Âm lượng thuyết minh")
                    Spacer()
                    Text("\(Int(model.voiceoverVolume * 100))%")
                }
                .font(.caption)
                Slider(value: $model.voiceoverVolume, in: 0...1)
                    .tint(.cyan)
            }
            Divider()
            Text("Tạo thuyết minh từ văn bản")
                .font(.caption.bold())
            TextField("Nhập lời thuyết minh tiếng Việt…",
                      text: $model.narrationText, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            Button {
                model.generateNarrationFromText()
            } label: {
                Label(model.isGeneratingNarration ? "Đang tạo giọng…" :
                      "Tạo giọng đọc tiếng Việt", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .disabled(model.isGeneratingNarration ||
                      model.narrationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if model.isGeneratingNarration {
                ProgressView().controlSize(.small)
            }
            Text("Dùng giọng đọc iOS có sẵn, không gửi văn bản lên máy chủ.")
                .font(.caption2)
                .foregroundStyle(.secondary)

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
                if model.musicHighlightDuration > 0 {
                    Text(String(format: "Highlight nhạc: %.1fs đến %.1fs",
                                model.musicStartSeconds,
                                model.musicStartSeconds + model.musicHighlightDuration))
                        .font(.caption)
                        .foregroundStyle(.cyan)
                    Button("Bỏ giới hạn đoạn nhạc") {
                        model.musicHighlightDuration = 0
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                Button {
                    activeTool = .ai
                } label: {
                    Label("AI tìm highlight MP3", systemImage: "sparkles")
                }
                .font(.caption)
                .buttonStyle(.bordered)
                HStack {
                    Text("Nhạc mở đầu mượt")
                    Spacer()
                    Text(String(format: "%.1fs", model.musicFadeIn))
                }
                .font(.caption)
                Slider(value: $model.musicFadeIn, in: 0...3, step: 0.1)
                    .tint(accent)

                HStack {
                    Text("Nhạc kết thúc mượt")
                    Spacer()
                    Text(String(format: "%.1fs", model.musicFadeOut))
                }
                .font(.caption)
                Slider(value: $model.musicFadeOut, in: 0...5, step: 0.1)
                    .tint(accent)

                Text("Tùy chỉnh fade-in / fade-out khi xuất và tự giảm nhạc trong lúc có giọng đọc.")
                    .font(.caption2).foregroundStyle(.secondary)

                MusicMasteringPanel(model: model)
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
            if model.isRenderingPreview {
                HStack {
                    ProgressView()
                    Text("Đang dựng bản nháp 720p đầy đủ hình và tiếng…")
                        .font(.caption)
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
                model.renderSynchronizedPreview()
            } label: {
                HStack {
                    Spacer()
                    Label("Xem thử toàn bộ · 720p",
                          systemImage: "play.rectangle.fill")
                        .font(.subheadline.bold())
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.clips.isEmpty || model.isImporting ||
                      model.isExporting || model.isRenderingPreview)

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
            .disabled(model.clips.isEmpty || model.isImporting ||
                      model.isExporting || model.isRenderingPreview)
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
