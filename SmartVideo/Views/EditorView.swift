import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

private enum EditorTool: String, CaseIterable, Identifiable {
    case clip = "Đoạn"
    case frame = "Khung"
    case vfx = "VFX"
    case mockup = "Mockup"
    case presets = "Preset Pro"
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
    case vault = "Kho video"
    case inspector = "Media Inspector"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .clip: return "scissors"
        case .frame: return "aspectratio"
        case .vfx: return "wand.and.stars"
        case .mockup: return "sun.horizon.fill"
        case .presets: return "square.grid.3x3.topleft.filled"
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
        case .vault: return "square.and.arrow.down.on.square"
        case .inspector: return "waveform.path.ecg"
        }
    }
}

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @StateObject private var recorder = VoiceRecorder()
    @StateObject private var audioMonitor = LiveAudioPreview()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var selectedClipID: UUID?
    @State private var activeTool: EditorTool = .clip
    @State private var activeFilePicker: EditorDocumentKind?
    @State private var showDocumentImporter = false
    @State private var subtitleFileForShare: URL?
    @State private var previewPlayer: AVPlayer?
    @State private var previewRequestID = UUID()
    @State private var previewTask: Task<Void, Never>?
    @State private var localSecond = 0.0
    @State private var isPlaying = false
    @State private var autoResumeClipID: UUID?
    @State private var lastStillFrameTick: Date?
    @State private var showProjects = false
    @State private var showRenderedPreview = false
    @State private var showThumbnailStudio = false
    @State private var pickedOverlay: PhotosPickerItem?
    @State private var selectedOverlayID: UUID?
    @State private var pickedPIP: PhotosPickerItem?
    @State private var selectedPIPID: UUID?
    @State private var selectedTextID: UUID?
    @State private var selectedSoundID: UUID?
    @State private var selectedMusicRegionID: UUID?
    @State private var compareOriginalFootage = false
    /// A stable two-zone editing workspace: preview and timeline never live
    /// inside the vertically scrolling tool panel.
    @AppStorage("ViePN.Editor.ExpandedTimeline")
    private var isTimelineExpanded = false
    @AppStorage("ViePN.Editor.LargePreview")
    private var prefersLargePreview = false
    @AppStorage("ViePN.Editor.LiveAudioEnabled")
    private var liveAudioEnabled = true

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
            VStack(spacing: 5) {
                topBar
                    .padding(.top, 2)

                // Always visible while adjusting long filters, captions,
                // Voice/AI panels and keyframes. Never put this in ScrollView.
                videoPreview
                    .frame(height: previewHeight(for: geometry.size.height))
                    .zIndex(1)

                if isTimelineExpanded {
                    timeline
                } else {
                    compactTimeline
                }
                toolPicker

                // Only the parameter panel scrolls. Switching tool tabs
                // restores its top instead of retaining an unrelated offset.
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: 1)
                                .id("editor-panel-top")
                            toolPanel
                                .padding(.horizontal, 3)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity,
                                       alignment: .topLeading)
                        }
                    }
                    .onChange(of: activeTool) { _ in
                        withAnimation(.easeOut(duration: 0.15)) {
                            scrollProxy.scrollTo("editor-panel-top",
                                                 anchor: .top)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
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
        .sheet(isPresented: $showThumbnailStudio) {
            ThumbnailStudioPanel(videoURL: model.exportedURL)
        }
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
        .onChange(of: selectedClipID) { newID in
            let resume = autoResumeClipID == newID
            autoResumeClipID = nil
            compareOriginalFootage = false
            updatePreview(preservingClock: true, resumePlayback: resume)
        }
        .onChange(of: compareOriginalFootage) { _ in
            refreshColorPreview()
        }
        .onChange(of: selectedClip?.imageLook) { _ in
            refreshColorPreview()
        }
        .onChange(of: selectedClip?.lookIntensity) { _ in
            refreshColorPreview()
        }
        .onChange(of: selectedClip?.colorAdjustments) { _ in
            refreshColorPreview()
        }
        .onChange(of: selectedClip?.autoEnhance) { _ in
            refreshColorPreview()
        }
        .onChange(of: selectedClip?.personBackground) { _ in
            refreshColorPreview()
        }
        .onChange(of: selectedClip?.speedCurve) { _ in
            refreshColorPreview()
        }
        .task(id: model.voiceoverURL?.path ?? "") {
            model.voiceoverDuration = 0
            if let url = model.voiceoverURL,
               let seconds = try? await AVURLAsset(url: url)
                .load(.duration).seconds,
               seconds.isFinite, seconds > 0 {
                model.voiceoverDuration = seconds
            }
        }
        .onChange(of: model.keepOriginalAudio) { _ in
            updateClipAudioPreview()
        }
        .onChange(of: selectedClip?.sourceAudioVolume) { _ in
            updateClipAudioPreview()
        }
        .onChange(of: selectedClip?.sourceAudioMuted) { _ in
            updateClipAudioPreview()
        }
        .onChange(of: selectedClip?.sourceAudioFadeIn) { _ in
            updateClipAudioPreview()
        }
        .onChange(of: selectedClip?.sourceAudioFadeOut) { _ in
            updateClipAudioPreview()
        }
        .onChange(of: liveAudioEnabled) { enabled in
            if !enabled { audioMonitor.pause() }
        }
        .onChange(of: model.projectID) { _ in
            pauseContinuousPlayback()
            audioMonitor.invalidate()
        }
        .onReceive(Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()) { _ in
            updateContinuousPlaybackClock()
        }
        .onDisappear {
            previewTask?.cancel()
            pauseContinuousPlayback()
            audioMonitor.invalidate()
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
                case .musicRegion: model.importMusicRegion(from: url)
                case .voice: model.importVoiceover(from: url)
                case .subtitles: model.importSubtitles(from: url)
                case .soundEffect:
                    model.importSoundEffect(from: url)
                case .textFillImage:
                    if let selectedTextID {
                        model.importTextFill(
                            from: url, for: selectedTextID, video: false
                        )
                    }
                case .textFillVideo:
                    if let selectedTextID {
                        model.importTextFill(
                            from: url, for: selectedTextID, video: true
                        )
                    }
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
        // GeometryReader already excludes the pinned export bar and safe
        // areas. Reserve an actual editing area even on smaller iPhones.
        let timelineHeight: CGFloat = isTimelineExpanded ?
            expandedTimelineHeight : 105
        let reserved = 42 + 54 + timelineHeight + 155 + 28
        let room = max(120, availableHeight - reserved)
        let target = availableHeight * (prefersLargePreview ? 0.39 : 0.30)
        return min(prefersLargePreview ? 285 : 225,
                   max(120, min(target, room)))
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
                        pauseContinuousPlayback()
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
                    if clip.kind == .image {
                        StudioLookPhotoPreview(
                            fileURL: clip.fileURL,
                            look: clip.imageLook,
                            intensity: compareOriginalFootage ? 0 : clip.lookIntensity,
                            adjustments: compareOriginalFootage ? .neutral : clip.colorAdjustments,
                            autoEnhance: compareOriginalFootage ? .off : clip.autoEnhance,
                            photoPreset: compareOriginalFootage ? nil : clip.photoPreset,
                            photoPresetIntensity: clip.photoPresetIntensity,
                            portraitFocus: compareOriginalFootage ? .off : clip.portraitFocus,
                            personBackground: compareOriginalFootage ? .original : clip.personBackground,
                            contentMode: model.contentMode
                        )
                            .frame(width: canvasWidth, height: canvasHeight)
                            .scaleEffect(photoMotionScale(clip))
                            .offset(x: photoMotionShift(clip,
                                                        canvasWidth: canvasWidth))
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

                MockupCanvasPreview(
                    mockups: model.mockupOverlays,
                    second: playheadSecond,
                    canvas: CGSize(
                        width: canvasWidth, height: canvasHeight
                    )
                )

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

                // Draw interpolated multi-point image keyframes at the
                // current playhead. Drag translates the whole motion path.
                ForEach(model.imageOverlays) { overlay in
                    if playheadSecond >= overlay.start &&
                       playheadSecond <= overlay.end &&
                       FileManager.default.fileExists(atPath: overlay.fileURL.path) {
                        let progress = min(1, max(0,
                            (playheadSecond - overlay.start) /
                            max(0.1, overlay.duration)
                        ))
                        let current = OverlayKeyframeSampler.sample(
                            overlay, atProgress: progress
                        )
                        KeyedOverlayImage(overlay: overlay)
                            .frame(width: canvasWidth * CGFloat(current.scale))
                            .opacity(current.opacity)
                            .rotationEffect(.degrees(current.rotationDegrees))
                            .position(
                                x: canvasWidth * CGFloat(current.x),
                                y: canvasHeight * CGFloat(current.y)
                            )
                            .overlay {
                                if activeTool == .overlay &&
                                    selectedOverlayID == overlay.id {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.cyan, lineWidth: 1.5)
                                        .frame(width: canvasWidth *
                                            CGFloat(current.scale))
                                        .position(
                                            x: canvasWidth * CGFloat(current.x),
                                            y: canvasHeight * CGFloat(current.y)
                                        )
                                }
                            }
                            .gesture(
                                DragGesture(
                                    minimumDistance: 0,
                                    coordinateSpace: .named("captionCanvas")
                                ).onChanged { value in
                                    guard activeTool == .overlay,
                                          canvasWidth > 0, canvasHeight > 0 else {
                                        return
                                    }
                                    selectedOverlayID = overlay.id
                                    let targetX = min(0.97, max(0.03,
                                        Double(value.location.x / canvasWidth)))
                                    let targetY = min(0.97, max(0.03,
                                        Double(value.location.y / canvasHeight)))
                                    model.translateImageOverlay(
                                        overlay.id,
                                        dx: targetX - current.x,
                                        dy: targetY - current.y
                                    )
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
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        prefersLargePreview.toggle()
                    }
                } label: {
                    Image(systemName: prefersLargePreview ?
                          "arrow.down.right.and.arrow.up.left" :
                          "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(prefersLargePreview ?
                                    "Thu nhỏ video xem trước" :
                                    "Phóng to video xem trước")
                .padding(5)
            }
            .overlay(alignment: .bottomTrailing) {
                if selectedClip != nil {
                    Button {
                        toggleContinuousPlayback()
                    } label: {
                        Image(systemName: isPlaying ?
                              "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .shadow(radius: 3)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ?
                                        "Tạm dừng dự án" :
                                        "Phát liên tục toàn dự án")
                    .padding(5)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !model.clips.isEmpty {
                    Text(isPlaying ? "▶ Phát nhanh · \(model.clips.count) clip" :
                         "Xem nhanh · \(model.clips.count) clip")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .allowsHitTesting(false)
                        .padding(7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: model.canvas)
        }
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 13))
    }

    /// Keep the video and parameter workspace usable even when the user
    /// adds 12 FX tracks: the audio lanes scroll vertically within a cap.
    private var expandedTimelineHeight: CGFloat {
        let lanes = model.soundEffects.count +
            (model.musicRegionMode ?
                model.musicRegions.count :
                (model.musicURL == nil ? 0 : 1)) +
            (model.voiceoverURL == nil ? 0 : 1)
        let tracks = lanes > 0 ? min(CGFloat(lanes) * 47, 132) : 0
        let selectedOverlayStrip =
            (activeTool == .overlay && selectedOverlayID != nil) ||
            (activeTool == .pip && selectedPIPID != nil) ||
            (activeTool == .title && selectedTextID != nil)
        return 188 + tracks +
            (model.timelineBeatMarkers.isEmpty ? 0 : 17) +
            (selectedOverlayStrip ? 24 : 0)
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
                Button {
                    liveAudioEnabled.toggle()
                } label: {
                    Image(systemName: liveAudioEnabled ?
                          "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundStyle(liveAudioEnabled ? accent : .gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(liveAudioEnabled ?
                    "Tắt nghe thử nhạc giọng và FX" :
                    "Bật nghe thử nhạc giọng và FX")
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isTimelineExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                }
                .accessibilityLabel("Thu gọn timeline")
                .buttonStyle(.plain)
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

                if activeTool == .pip, let selectedPIPID,
                   let item = model.videoOverlays.first(where: {
                       $0.id == selectedPIPID
                   }) {
                    MultiTrackKeyframeTimelineStrip(
                        frames: OverlayKeyframeSampler.frames(for: item),
                        start: item.start, duration: item.duration,
                        totalDuration: model.totalDuration,
                        onScrub: { scrubTimeline(to: $0) }
                    )
                    .frame(height: 24)
                }

                if activeTool == .title, let selectedTextID,
                   let item = model.textOverlays.first(where: {
                       $0.id == selectedTextID
                   }) {
                    MultiTrackKeyframeTimelineStrip(
                        frames: OverlayKeyframeSampler.frames(for: item),
                        start: item.start, duration: item.duration,
                        totalDuration: model.totalDuration,
                        onScrub: { scrubTimeline(to: $0) }
                    )
                    .frame(height: 24)
                }

                if let selectedOverlayID,
                   let overlay = model.imageOverlays.first(where: {
                       $0.id == selectedOverlayID
                   }), activeTool == .overlay {
                    HStack(spacing: 5) {
                        Image(systemName: "diamond.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        OverlayKeyframeTimelineStrip(
                            overlay: overlay,
                            totalDuration: model.totalDuration,
                            onScrub: { scrubTimeline(to: $0) }
                        )
                    }
                    .frame(height: 23)
                }

                MultiTrackStudioTimeline(
                    model: model,
                    selectedClipID: selectedClipID,
                    selectedSoundID: $selectedSoundID,
                    selectedMusicRegionID: $selectedMusicRegionID,
                    onSelectMusicRegion: { region in
                        selectedMusicRegionID = region.id
                        activeTool = .audio
                    },
                    onSelectClip: { clip, index in
                        selectClip(clip, at: index)
                        activeTool = .clip
                    },
                    onSelectSound: { effect in
                        selectedSoundID = effect.id
                        activeTool = .sfx
                    },
                    onSelectProjectAudio: { _ in
                        activeTool = .audio
                    },
                    onScrub: { scrubTimeline(to: $0) }
                )
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
        .frame(height: expandedTimelineHeight, alignment: .top)
    }

    /// A 100pt always-available timeline for everyday editing. The full
    /// multi-track timeline can be expanded on demand without hiding preview.
    private var compactTimeline: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Label("Timeline", systemImage: "rectangle.3.group")
                    .font(.caption.bold())
                Spacer(minLength: 1)
                Text(timecode(model.timelineSecond) + " / " +
                     timecode(model.totalDuration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)

                Button {
                    model.undoEdit()
                    scrubTimeline(to: model.timelineSecond)
                } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                    .accessibilityLabel("Hoàn tác")

                Button {
                    model.redoEdit()
                    scrubTimeline(to: model.timelineSecond)
                } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                    .accessibilityLabel("Làm lại")

                Button {
                    liveAudioEnabled.toggle()
                } label: {
                    Image(systemName: liveAudioEnabled ?
                          "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundStyle(liveAudioEnabled ? accent : .gray)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .accessibilityLabel(liveAudioEnabled ?
                    "Tắt nhạc, giọng đọc và âm FX khi xem nhanh" :
                    "Bật nhạc, giọng đọc và âm FX khi xem nhanh")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isTimelineExpanded = true
                    }
                } label: { Image(systemName: "chevron.down.circle.fill") }
                    .accessibilityLabel("Mở rộng timeline đa track")
            }
            .font(.caption)
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button {
                    stepPreviewClip(-1)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)
                .disabled(model.clips.isEmpty)
                .accessibilityLabel("Clip trước")

                Slider(value: Binding(
                    get: { min(model.totalDuration,
                               max(0, model.timelineSecond)) },
                    set: { scrubTimeline(to: $0) }
                ), in: 0...max(0.1, model.totalDuration), step: 0.04)
                    .tint(accent)
                    .accessibilityLabel("Tua video, xem trước luôn cố định")

                Button {
                    stepPreviewClip(1)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)
                .disabled(model.clips.isEmpty)
                .accessibilityLabel("Clip tiếp theo")

                Button {
                    if let id = model.splitClip(at: model.timelineSecond) {
                        selectedClipID = id
                        scrubTimeline(to: model.timelineSecond)
                    }
                } label: {
                    Label("Tách", systemImage: "scissors")
                        .font(.caption2.bold())
                }
                .buttonStyle(.bordered)
                .disabled(model.clips.isEmpty)
            }
            .frame(height: 27)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if model.clips.isEmpty {
                        Text("Bấm Thêm để nhập ảnh hoặc video")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.clips.enumerated()),
                            id: \.element.id) { index, clip in
                        Button {
                            selectClip(clip, at: index)
                            activeTool = .clip
                        } label: {
                            Text("\(index + 1) · " +
                                 String(format: "%.1fs", clip.renderedDuration))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(selectedClipID == clip.id ?
                                                 .black : .white)
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(
                                    selectedClipID == clip.id ?
                                        accent : Color.white.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 28)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(height: 105)
        .background(Color.white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 11))
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
        let time = model.timelineStart(of: index)
        // Re-selecting the same clip must actually seek it to frame zero;
        // selectedClipID.onChange would not fire for an identical UUID.
        scrubTimeline(to: time)
    }

    private func stepPreviewClip(_ delta: Int) {
        guard !model.clips.isEmpty else { return }
        let current = model.clips.firstIndex(where: {
            $0.id == selectedClipID
        }) ?? 0
        let target = min(model.clips.count - 1, max(0, current + delta))
        scrubTimeline(to: model.timelineStart(of: target))
    }

    private func scrubTimeline(to time: Double) {
        pauseContinuousPlayback()
        let seconds = min(model.totalDuration, max(0, time))
        model.timelineSecond = seconds
        guard let position = model.clipAtTimeline(seconds) else { return }
        let clip = model.clips[position.index]
        localSecond = position.local
        if selectedClipID != clip.id {
            // A new selectedClipID triggers the correct preview exactly
            // once through onChange, including async Speed Curve setup.
            previewTask?.cancel()
            previewPlayer?.pause()
            previewPlayer = nil
            selectedClipID = clip.id
        } else if clip.kind == .video {
            let seek = ProjectPreviewTiming.sourceTime(
                localTime: position.local,
                trimStart: clip.startTime,
                playbackSpeed: clip.playbackSpeed,
                speedCurveEnabled: !clip.speedCurve.isEmpty
            )
            previewPlayer?.seek(
                to: CMTime(seconds: seek, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero
            )
        }
    }

    private var toolPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EditorTool.allCases) { tool in
                        Button {
                            activeTool = tool
                            pauseContinuousPlayback()
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tool.symbol)
                                    .font(.system(size: 15))
                                Text(tool.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(activeTool == tool ? .black : .white)
                            .frame(width: 78, height: 48)
                            .background(
                                activeTool == tool ? accent :
                                    Color.white.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(tool.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: activeTool) { tool in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(tool.id, anchor: .center)
                }
            }
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private var toolPanel: some View {
        switch activeTool {
        case .clip: clipPanel
        case .frame: framePanel
        case .vfx: VFXLibraryPanel(model: model)
        case .mockup: MockupStudioPanel(model: model)
        case .presets: PresetStudioPanel(model: model) { id in
            selectedTextID = id
            activeTool = .title
            scrubTimeline(to: model.textOverlays.first(where: { $0.id == id })?.start ?? 0)
        }
        case .captions: subtitlePanel
        case .audio: audioPanel
        case .effects: effectsPanel
        case .ai:
            VStack(alignment: .leading, spacing: 12) {
                AIAutoVideoCreatorPanel(model: model)
                Hook3sStudioPanel(
                    model: model,
                    selectedClipID: selectedClipID,
                    onInserted: { id in
                        selectedClipID = id
                        scrubTimeline(to: 0)
                    },
                    onUndo: {
                        selectedClipID = model.clips.first?.id
                        scrubTimeline(to: model.timelineSecond)
                    },
                    onPreview: { second in
                        scrubTimeline(to: second)
                    }
                )
                AutoEnhanceStudioPanel(
                    model: model, selectedClipID: selectedClipID,
                    compareOriginal: $compareOriginalFootage
                )
                AIVideoDirectorPanel(
                    model: model, selectedClipID: selectedClipID
                )
                AIVocalSeparationPanel(
                    model: model, selectedClipID: selectedClipID
                )
                GeminiRevoiceStudioPanel(
                    model: model, selectedClipID: selectedClipID
                )
                highlightPanel
            }
        case .narration: NarrationStudioPanel(model: model, recorder: recorder) {
            activeFilePicker = .voice
            showDocumentImporter = true
        }
        case .metadata: MetadataPanel(model: model)
        case .overlay: OverlayStudioPanel(model: model,
                                           selectedOverlayID: $selectedOverlayID,
                                           pickedOverlay: $pickedOverlay,
                                           onScrub: { scrubTimeline(to: $0) })
        case .pip: VideoPIPStudioPanel(model: model,
                                       selectedID: $selectedPIPID,
                                       pickerItem: $pickedPIP,
                                       onScrub: { scrubTimeline(to: $0) })
        case .title: TextOverlayStudioPanel(
            model: model,
            selectedID: $selectedTextID,
            onScrub: { scrubTimeline(to: $0) },
            importTextFill: { video in
                activeFilePicker = video ? .textFillVideo : .textFillImage
                showDocumentImporter = true
            },
            autoPosition: { id in
                model.autoPositionText(id, clip: selectedClip)
            }
        )
        case .sfx: SoundEffectsStudioPanel(model: model,
                                          selectedID: $selectedSoundID) {
            activeFilePicker = .soundEffect
            showDocumentImporter = true
        }
        case .inspector: MediaInspectorPanel(clip: selectedClip)
        case .vault: VideoLibraryPanel(model: model) { id in
            selectedClipID = id
            activeTool = .clip
            updatePreview()
            scrubTimeline(to: model.timelineSecond)
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
                    HStack(spacing: 8) {
                        Button {
                            previewPlayer?.pause()
                            isPlaying = false
                            Task {
                                if let newID = await model.freezeFrame(
                                    clipID: clip.id, atLocalSecond: localSecond
                                ) {
                                    selectedClipID = newID
                                    activeTool = .clip
                                    scrubTimeline(to: model.timelineSecond)
                                }
                            }
                        } label: {
                            Label("Đóng băng 1,5s", systemImage: "snowflake")
                        }
                        .disabled(model.isCreatingFreezeFrame)
                        if model.isCreatingFreezeFrame {
                            ProgressView().controlSize(.small)
                            Text("Đang lấy khung hình…")
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)

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

                    Divider()
                    clipAudioControls(clip)
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

    /// Live volume, mute and fade controls are scoped to the selected video,
    /// unlike the project's global source-audio switch.
    private func clipAudioControls(_ clip: TimelineClip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Âm thanh gốc của đoạn", systemImage: "waveform")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    model.setClipAudioMuted(clip.id,
                                            muted: !clip.sourceAudioMuted)
                } label: {
                    Label(clip.sourceAudioMuted ? "Bật tiếng" : "Tắt tiếng",
                          systemImage: clip.sourceAudioMuted ?
                            "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(clip.sourceAudioMuted ? .orange : accent)
            }

            HStack {
                Text("Âm lượng đoạn")
                Spacer()
                Text("\(Int(clip.sourceAudioVolume * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: sourceAudioVolumeBinding(clip.id),
                   in: 0...1, step: 0.05,
                   onEditingChanged: { editing in
                       if editing { model.beginClipAudioEdit() }
                   })
                .tint(accent)
                .disabled(clip.sourceAudioMuted)
            HStack(spacing: 5) {
                ForEach([0, 25, 50, 100], id: \.self) { level in
                    Button("\(level)%") {
                        model.beginClipAudioEdit()
                        if let index = model.clips.firstIndex(
                            where: { $0.id == clip.id }
                        ) {
                            model.clips[index].sourceAudioVolume =
                                Float(level) / 100
                        }
                    }
                    .font(.caption2.bold())
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                    .disabled(clip.sourceAudioMuted)
                }
            }

            HStack {
                Label("Fade vào", systemImage: "arrow.up.right")
                Spacer()
                Text(String(format: "%.2fs", clip.sourceAudioFadeIn))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: sourceAudioFadeBinding(clip.id, fadeIn: true),
                   in: 0...3, step: 0.05,
                   onEditingChanged: { editing in
                       if editing { model.beginClipAudioEdit() }
                   })
                .tint(accent)

            HStack {
                Label("Fade ra", systemImage: "arrow.down.right")
                Spacer()
                Text(String(format: "%.2fs", clip.sourceAudioFadeOut))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: sourceAudioFadeBinding(clip.id, fadeIn: false),
                   in: 0...3, step: 0.05,
                   onEditingChanged: { editing in
                       if editing { model.beginClipAudioEdit() }
                   })
                .tint(accent)
            HStack {
                Text("Áp dụng riêng cho clip đã chọn, cả preview và MP4.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Đặt lại") {
                    model.resetClipAudio(clip.id)
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }
            if !model.keepOriginalAudio {
                Label("Đang tắt toàn bộ tiếng gốc trong Âm thanh. Bật lại để nghe riêng clip này.",
                      systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func sourceAudioVolumeBinding(_ id: UUID) -> Binding<Double> {
        Binding {
            Double(model.clips.first(where: { $0.id == id })?
                .sourceAudioVolume ?? 1)
        } set: { value in
            guard let index = model.clips.firstIndex(
                where: { $0.id == id }
            ) else { return }
            model.clips[index].sourceAudioVolume =
                ClipAudioEnvelope.safeVolume(Float(value))
        }
    }

    private func sourceAudioFadeBinding(
        _ id: UUID, fadeIn: Bool
    ) -> Binding<Double> {
        Binding {
            guard let clip = model.clips.first(where: { $0.id == id })
            else { return 0 }
            return fadeIn ? clip.sourceAudioFadeIn : clip.sourceAudioFadeOut
        } set: { value in
            guard let index = model.clips.firstIndex(
                where: { $0.id == id }
            ) else { return }
            let safe = ClipAudioEnvelope.safeFade(value)
            if fadeIn {
                model.clips[index].sourceAudioFadeIn = safe
            } else {
                model.clips[index].sourceAudioFadeOut = safe
            }
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
            if model.transition != .cut {
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
                        Text(clip.speedCurve.isEmpty
                            ? String(format: "%.2fx · %.1f giây",
                                     clip.playbackSpeed, clip.renderedDuration)
                            : String(format: "Speed Curve · %.1f giây",
                                     clip.renderedDuration))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    HStack(spacing: 6) {
                        ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { speed in
                            Button(String(format: "%gx", speed)) {
                                updateSpeed(clip.id, to: speed)
                            }
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(clip.speedCurve.isEmpty &&
                                abs(clip.playbackSpeed - speed) < 0.01 ?
                                             .black : .white)
                            .background(
                                clip.speedCurve.isEmpty &&
                                abs(clip.playbackSpeed - speed) < 0.01 ?
                                    accent : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    Slider(value: Binding(
                        get: {
                            model.clips.first(where: { $0.id == clip.id })?
                                .playbackSpeed ?? 1
                        },
                        set: { updateSpeed(clip.id, to: $0) }
                    ), in: 0.25...4, step: 0.05)
                    .tint(.cyan)
                    .accessibilityLabel("Tốc độ video")
                    Text("Chọn tốc độ cố định sẽ tắt Speed Curve. Âm thanh gốc có thể thay đổi cao độ.")
                        .font(.caption2).foregroundStyle(.secondary)

                    Divider()
                    SpeedCurveStudioPanel(model: model, clip: clip)
                } else {
                    Text("Chuyển động ảnh kiểu Ken Burns")
                        .font(.caption.bold())
                    imageMotionGrid(clip: clip)
                    PhotoPresetStudioPanel(
                        model: model,
                        selectedClipID: selectedClipID,
                        compareOriginal: $compareOriginalFootage
                    )
                    PhotoPortraitFocusPanel(
                        model: model,
                        selectedClipID: selectedClipID,
                        compareOriginal: $compareOriginalFootage
                    )

                }

                Divider()
                Text("AI tách nền người · Vision trên iPhone")
                    .font(.subheadline.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PersonBackground.allCases) { mode in
                            Button {
                                if let index = model.clips.firstIndex(
                                    where: { $0.id == clip.id }
                                ) {
                                    model.clips[index].personBackground = mode
                                }
                            } label: {
                                Label(mode.rawValue, systemImage: mode.symbol)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(
                                        clip.personBackground == mode ?
                                            .black : .white
                                    )
                                    .background(
                                        clip.personBackground == mode ?
                                            accent : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Tách người khỏi nền bằng Vision trên thiết bị; chọn nền mờ, đen, trắng hoặc xanh. Chỉ hỗ trợ chủ thể người. Clip dài có thể xuất chậm hơn; bản gốc được giữ nguyên.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Bộ lọc màu Core Image · Ảnh & Video")
                    .font(.caption.bold())
                imageLookGrid(clip: clip)

                HStack {
                    Text("Cường độ màu")
                    Spacer()
                    Text("\(Int(clip.lookIntensity * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.cyan)
                }
                .font(.caption)
                Slider(value: Binding(
                    get: {
                        model.clips.first(where: { $0.id == clip.id })?
                            .lookIntensity ?? 1
                    },
                    set: { value in
                        if let index = model.clips.firstIndex(where: {
                            $0.id == clip.id
                        }) {
                            model.clips[index].lookIntensity = value
                        }
                    }
                ), in: 0...1, step: 0.05)
                    .tint(.cyan)
                manualColorControls(clip: clip)

                Toggle("So sánh trước / sau · chỉ thay đổi preview",
                       isOn: $compareOriginalFootage)
                    .font(.caption)
                    .tint(.cyan)
                                Text("Màu áp trực tiếp lên từng khung hình của video khi xuất MP4. Giữ tiếng gốc; xử lý footage dài có thể tốn thời gian.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    private func manualColorControls(clip: TimelineClip) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Chỉnh màu thủ công")
                    .font(.caption.bold())
                Spacer()
                Button("Đặt lại") {
                    guard let index = model.clips.firstIndex(where: {
                        $0.id == clip.id
                    }) else { return }
                    model.clips[index].colorAdjustments = .neutral
                }
                .font(.caption2)
                .disabled(clip.colorAdjustments.isNeutral)
            }

            colorSlider("Phơi sáng", value: colorAdjustmentBinding(
                clip.id, keyPath: \.exposureEV
            ), range: -2...2, display: String(
                format: "%+.1f EV", clip.colorAdjustments.exposureEV
            ))
            colorSlider("Tương phản", value: colorAdjustmentBinding(
                clip.id, keyPath: \.contrast
            ), range: 0.5...1.5, display: String(
                format: "%.2f", clip.colorAdjustments.contrast
            ))
            colorSlider("Bão hòa", value: colorAdjustmentBinding(
                clip.id, keyPath: \.saturation
            ), range: 0...2, display: String(
                format: "%.2f", clip.colorAdjustments.saturation
            ))
            colorSlider("Ấm / lạnh", value: colorAdjustmentBinding(
                clip.id, keyPath: \.warmth
            ), range: -1...1, display: clip.colorAdjustments.warmth < -0.01
                ? "Lạnh" : clip.colorAdjustments.warmth > 0.01 ? "Ấm" : "0")
        }
        .padding(8)
        .background(Color.white.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 9))
    }

    private func colorSlider(_ title: String, value: Binding<Double>,
                             range: ClosedRange<Double>,
                             display: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display).monospacedDigit().foregroundStyle(.cyan)
            }
            .font(.caption2)
            Slider(value: value, in: range)
                .tint(.cyan)
        }
    }

    private func colorAdjustmentBinding(
        _ id: UUID, keyPath: WritableKeyPath<ColorAdjustments, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                model.clips.first(where: { $0.id == id })?
                    .colorAdjustments[keyPath: keyPath] ?? 0
            },
            set: { value in
                guard let index = model.clips.firstIndex(where: {
                    $0.id == id
                }) else { return }
                model.clips[index].colorAdjustments[keyPath: keyPath] = value
            }
        )
    }

    private func updateSpeed(_ id: UUID, to speed: Double) {
        guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
        let safeSpeed = min(4, max(0.25, speed))
        model.clips[index].playbackSpeed = safeSpeed
        model.clips[index].speedCurve = []
        if isPlaying, let player = previewPlayer {
            player.rate = Float(safeSpeed)
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
                            for index in cue.words.indices {
                                cue.words[index].start -= distance
                                cue.words[index].end -= distance
                            }
                        }
                        Button("0.5s →") {
                            let distance = min(0.5, max(0, model.totalDuration - cue.end))
                            cue.start += distance
                            cue.end += distance
                            for index in cue.words.indices {
                                cue.words[index].start += distance
                                cue.words[index].end += distance
                            }
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
                    activeFilePicker = model.musicRegionMode ?
                        .musicRegion : .music
                    showDocumentImporter = true
                } label: {
                    Label(model.musicRegionMode ?
                          "Thêm nhạc" : "Nhạc MP3",
                          systemImage: "music.note")
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

            MusicRegionsStudioPanel(
                model: model,
                selectedID: $selectedMusicRegionID,
                importAudio: {
                    activeFilePicker = .musicRegion
                    showDocumentImporter = true
                },
                onScrub: { scrubTimeline(to: $0) }
            )

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
                       step: 0.1, onEditingChanged: { editing in
                           if editing { model.beginSoundEffectsEdit() }
                       })
                    .tint(.cyan)
                HStack {
                    Text("Âm lượng thuyết minh")
                    Spacer()
                    Text("\(Int(model.voiceoverVolume * 100))%")
                }
                .font(.caption)
                Slider(value: $model.voiceoverVolume, in: 0...1)
                    .tint(.cyan)
                ProjectAudioAutomationPanel(
                    model: model, lane: .narration
                )
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

            if !model.musicRegionMode,
               let music = model.musicURL {
                AudioWaveformTrimView(
                    url: music,
                    sourceDuration: model.musicDuration,
                    trimStart: musicTrimStart,
                    trimEnd: musicTrimEnd,
                    title: "Waveform · chọn đoạn nhạc",
                    playheadSource: model.musicStartSeconds +
                        model.timelineSecond
                )
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
                ProjectAudioAutomationPanel(
                    model: model, lane: .music
                )
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
            Text("Nghe thử theo timeline: dùng biểu tượng loa ở thanh timeline. Nhạc, thuyết minh và FX được phát cùng video khi nhấn Play; bản dựng 720p vẫn là chuẩn đối chiếu cuối.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let warning = audioMonitor.warning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
    }

    /// Waveform music trim bindings: right edge at the file end is
    /// represented by musicHighlightDuration == 0 (play all remaining).
    private var musicTrimStart: Binding<Double> {
        Binding {
            model.musicStartSeconds
        } set: { value in
            let end = model.musicHighlightDuration > 0 ?
                min(model.musicDuration, model.musicStartSeconds +
                    model.musicHighlightDuration) : model.musicDuration
            let start = min(max(0, value), max(0, end - 0.1))
            model.musicStartSeconds = start
            if model.musicHighlightDuration > 0 {
                model.musicHighlightDuration = max(0.1, end - start)
            }
        }
    }

    private var musicTrimEnd: Binding<Double> {
        Binding {
            model.musicHighlightDuration > 0 ?
                min(model.musicDuration, model.musicStartSeconds +
                    model.musicHighlightDuration) : model.musicDuration
        } set: { value in
            let from = model.musicStartSeconds
            let end = min(model.musicDuration,
                          max(from + 0.1, value))
            model.musicHighlightDuration =
                end >= model.musicDuration - 0.04 ?
                    0 : max(0.1, end - from)
        }
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
                    Button {
                        showThumbnailStudio = true
                    } label: {
                        Label("Chọn thumbnail", systemImage: "photo.on.rectangle")
                    }
                    ShareLink(item: result) {
                        Label("Chia sẻ MP4", systemImage: "square.and.arrow.up")
                    }
                }
                .font(.caption)
            }

            // One-row export dock frees about 45pt for the live controls.
            // It stays outside the editing ScrollView and above the home bar.
            HStack(spacing: 8) {
                Button {
                    pauseContinuousPlayback()
                    model.renderSynchronizedPreview()
                } label: {
                    Label("Xem thử 720p",
                          systemImage: "play.rectangle.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.clips.isEmpty || model.isImporting ||
                          model.isExporting || model.isRenderingPreview)

                Button {
                    pauseContinuousPlayback()
                    model.export()
                } label: {
                    Label("Xuất MP4", systemImage: "square.and.arrow.up.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(model.clips.isEmpty || model.isImporting ||
                          model.isExporting || model.isRenderingPreview)
            }
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

    // MARK: - Continuous project transport

    private func pauseContinuousPlayback() {
        previewPlayer?.pause()
        audioMonitor.pause()
        isPlaying = false
        autoResumeClipID = nil
        lastStillFrameTick = nil
    }

    private func toggleContinuousPlayback() {
        if isPlaying {
            pauseContinuousPlayback()
            return
        }
        guard !model.clips.isEmpty else { return }
        if ProjectPreviewTiming.isFinished(
            globalTime: model.timelineSecond,
            totalDuration: model.totalDuration
        ) {
            model.timelineSecond = 0
            localSecond = 0
            if let firstID = model.clips.first?.id,
               firstID != selectedClipID {
                autoResumeClipID = firstID
                selectedClipID = firstID
                return
            }
        }
        resumeContinuousPlayback()
    }

    private func resumeContinuousPlayback() {
        guard let clip = selectedClip else {
            if let firstID = model.clips.first?.id {
                autoResumeClipID = firstID
                selectedClipID = firstID
            }
            return
        }
        isPlaying = true
        lastStillFrameTick = Date()

        if clip.kind == .image {
            audioMonitor.sync(
                at: model.timelineSecond, model: model,
                enabled: liveAudioEnabled, actuallyPlaying: true
            )
            return
        }
        guard let player = previewPlayer else {
            // A nonlinear Speed Curve might still be preparing its item.
            // updatePreview resumes automatically once preparation finishes.
            updatePreview(preservingClock: true, resumePlayback: true)
            return
        }
        let requestID = previewRequestID
        let seekSecond = ProjectPreviewTiming.sourceTime(
            localTime: localSecond, trimStart: clip.startTime,
            playbackSpeed: clip.playbackSpeed,
            speedCurveEnabled: !clip.speedCurve.isEmpty
        )
        player.seek(
            to: CMTime(seconds: seekSecond, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { finished in
            Task { @MainActor in
                guard finished, isPlaying,
                      selectedClipID == clip.id,
                      previewRequestID == requestID,
                      previewPlayer === player else { return }
                player.playImmediately(atRate: clip.speedCurve.isEmpty ?
                    Float(max(0.25, clip.playbackSpeed)) : 1)
            }
        }
    }

    private func updateContinuousPlaybackClock() {
        guard isPlaying, let clip = selectedClip,
              let index = model.clips.firstIndex(where: { $0.id == clip.id })
        else {
            audioMonitor.pause()
            return
        }

        if clip.kind == .image {
            let now = Date()
            if let lastStillFrameTick {
                localSecond = min(clip.renderedDuration, localSecond +
                    ProjectPreviewTiming.clockDelta(
                        elapsed: now.timeIntervalSince(lastStillFrameTick)
                    ))
            }
            lastStillFrameTick = now
        } else {
            guard let player = previewPlayer,
                  player.currentItem?.status == .readyToPlay,
                  player.rate > 0 else {
                audioMonitor.pause()
                return
            }
            let sourceSecond = player.currentTime().seconds
            guard sourceSecond.isFinite else { return }
            let videoSecond = clip.speedCurve.isEmpty
                ? (sourceSecond - clip.startTime) /
                    max(0.25, clip.playbackSpeed)
                : sourceSecond
            localSecond = min(clip.renderedDuration, max(0, videoSecond))
        }

        model.timelineSecond = min(model.totalDuration,
            model.timelineStart(of: index) + localSecond)
        updateClipAudioPreview()
        audioMonitor.sync(
            at: model.timelineSecond, model: model,
            enabled: liveAudioEnabled, actuallyPlaying: isPlaying
        )
        let starts = model.clips.indices.map { model.timelineStart(of: $0) }
        if let next = ProjectPreviewTiming.nextClip(
            after: index,
            globalTime: model.timelineSecond,
            clipStarts: starts
        ) {
            previewPlayer?.pause()
            previewPlayer = nil
            previewTask?.cancel()
            localSecond = 0
            lastStillFrameTick = Date()
            model.timelineSecond = starts[next]
            // The selection onChange resumes automatically, including
            // photo-to-video and async Speed Curve video-to-video handoffs.
            autoResumeClipID = model.clips[next].id
            selectedClipID = model.clips[next].id
        } else if index == model.clips.count - 1 &&
                  ProjectPreviewTiming.isFinished(
                    globalTime: model.timelineSecond,
                    totalDuration: model.totalDuration
                  ) {
            model.timelineSecond = model.totalDuration
            localSecond = clip.renderedDuration
            pauseContinuousPlayback()
        }
    }

    private func photoMotionScale(_ clip: TimelineClip) -> CGFloat {
        let progress = ProjectPreviewTiming.normalizedProgress(
            localTime: localSecond, renderedDuration: clip.renderedDuration
        )
        switch clip.imageMotion {
        case .zoomIn: return CGFloat(1 + 0.12 * progress)
        case .zoomOut: return CGFloat(1.12 - 0.12 * progress)
        case .panLeft, .panRight: return 1.10
        case .none: return 1
        }
    }

    private func photoMotionShift(_ clip: TimelineClip,
                                  canvasWidth: CGFloat) -> CGFloat {
        let progress = ProjectPreviewTiming.normalizedProgress(
            localTime: localSecond, renderedDuration: clip.renderedDuration
        )
        switch clip.imageMotion {
        case .panLeft:
            return canvasWidth * CGFloat((0.5 - progress) * 0.065)
        case .panRight:
            return canvasWidth * CGFloat((progress - 0.5) * 0.065)
        default: return 0
        }
    }

    /// AVPlayer is responsible for just the current original source track.
    /// Overall music, voice and SFX are monitored separately by LiveAudioPreview.
    /// The fast preview deliberately omits transition overlap crossfades;
    /// rendered 720p preview shows the real audio-composition result.
    private func updateClipAudioPreview() {
        guard let player = previewPlayer, let clip = selectedClip else {
            return
        }
        player.isMuted = !model.keepOriginalAudio || clip.sourceAudioMuted
        player.volume = ClipAudioEnvelope.gain(
            at: min(max(0, localSecond), clip.renderedDuration),
            duration: clip.renderedDuration,
            volume: clip.sourceAudioVolume,
            muted: clip.sourceAudioMuted,
            fadeIn: clip.sourceAudioFadeIn,
            fadeOut: clip.sourceAudioFadeOut
        )
    }

    private func refreshColorPreview() {
        updatePreview(preservingClock: true, resumePlayback: isPlaying)
    }

    private func updatePreview(preservingClock: Bool = false,
                               resumePlayback: Bool = false) {
        previewTask?.cancel()
        previewPlayer?.pause()
        audioMonitor.pause()
        isPlaying = resumePlayback
        lastStillFrameTick = resumePlayback ? Date() : nil
        let clock = preservingClock ? max(0, localSecond) : 0
        localSecond = clock
        let requestID = UUID()
        previewRequestID = requestID
        guard let clip = selectedClip, clip.kind == .video else {
            previewPlayer = nil
            return
        }
        var previewClip = clip
        if compareOriginalFootage {
            previewClip.lookIntensity = 0
            previewClip.colorAdjustments = .neutral
            previewClip.autoEnhance = .off
            previewClip.personBackground = .original
        }

        if previewClip.speedCurve.isEmpty {
            let player = AVPlayer(playerItem:
                VideoFrameGrader.makePreviewItem(for: previewClip))
            previewPlayer = player
            updateClipAudioPreview()
            let seekSecond = ProjectPreviewTiming.sourceTime(
                localTime: clock, trimStart: clip.startTime,
                playbackSpeed: clip.playbackSpeed, speedCurveEnabled: false
            )
            player.seek(
                to: CMTime(seconds: seekSecond, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero
            ) { finished in
                Task { @MainActor in
                    guard finished, resumePlayback, isPlaying,
                          selectedClipID == clip.id,
                          previewRequestID == requestID,
                          previewPlayer === player else { return }
                    player.playImmediately(atRate: Float(
                        max(0.25, clip.playbackSpeed)
                    ))
                }
            }
        } else {
            // Build the same retimed AVComposition as the renderer.
            // Debounce curve slider edits and discard outdated results.
            previewPlayer = nil
            previewTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                    try Task.checkCancellation()
                    let item = try await SpeedCurveProcessor.previewItem(
                        for: previewClip
                    )
                    guard !Task.isCancelled,
                          previewRequestID == requestID,
                          selectedClipID == clip.id else { return }
                    let player = AVPlayer(playerItem: item)
                    previewPlayer = player
                    updateClipAudioPreview()
                    await player.seek(to: CMTime(
                        seconds: min(clock, clip.renderedDuration),
                        preferredTimescale: 600
                    ))
                    guard !Task.isCancelled,
                          previewRequestID == requestID,
                          selectedClipID == clip.id else { return }
                    if resumePlayback && isPlaying {
                        player.playImmediately(atRate: 1)
                    }
                } catch is CancellationError {
                    // A newer slider value or clip selection replaced this
                    // request. This is not an editing error.
                } catch {
                    guard previewRequestID == requestID else { return }
                    isPlaying = false
                    audioMonitor.pause()
                    model.errorText = "Không tạo được preview Speed Curve: " +
                        error.localizedDescription
                }
            }
        }
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
