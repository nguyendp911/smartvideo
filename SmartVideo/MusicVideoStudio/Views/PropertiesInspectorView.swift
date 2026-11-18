import SwiftUI

extension MusicVideoStudio {
    /// Observes the clock on its own so the rest of the inspector stays still.
    struct LoopToggleView: View {
        @ObservedObject var playback: PlaybackEngine
        var body: some View {
            Toggle("Lặp khi phát hết", isOn: Binding(get: { playback.state.loops }, set: { playback.setLoops($0) }))
                .font(.caption)
        }
    }

    /// Project settings when nothing is selected, layer properties otherwise.
    /// Controls write straight into the project, so the preview, timeline,
    /// undo history and autosave all follow immediately.
    struct PropertiesInspectorView: View {
        @ObservedObject var model: MusicVideoEditorModel
        /// Not observed here: playback ticks must not re-render the inspector.
        let playback: PlaybackEngine
        @State private var recents: [ProjectSummary] = []

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if model.selection.isEmpty { projectSection } else { layerSection }
                }
                .padding(12)
            }
            .onAppear { recents = model.recentProjects() }
        }

        // MARK: Project

        private var projectSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                header("Dự án")
                TextField("Tên dự án", text: Binding(
                    get: { model.project.name },
                    set: { model.rename($0) }))
                    .textFieldStyle(.roundedBorder)
                row("Tỉ lệ khung hình") {
                    Picker("Tỉ lệ", selection: Binding(get: { model.project.aspect }, set: { model.setAspect($0) })) {
                        ForEach(AspectRatio.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                row("Tốc độ khung hình") {
                    Picker("FPS", selection: Binding(get: { model.project.fps }, set: { model.setFPS($0) })) {
                        ForEach(ProjectTime.supportedFrameRates, id: \.self) { Text("\($0) fps").tag($0) }
                    }.pickerStyle(.segmented)
                }
                LoopToggleView(playback: playback)
                photoDurationRow
                infoLine("Thời lượng", model.project.duration.timecode(fps: model.project.fps))
                infoLine("Số lớp", "\(model.project.layerCount)")
                let size = model.project.aspect.pixelSize(shortSide: 1080)
                infoLine("Khung xuất mặc định", "\(size.width)×\(size.height)")
                Text("Chạm một clip trên timeline để chỉnh thuộc tính của lớp.")
                    .font(.caption2).foregroundStyle(.secondary)
                projectsMenu
            }
        }

        @State private var allPhotoSeconds = 3.0

        private var photoDurationRow: some View {
            VStack(alignment: .leading, spacing: 4) {
                slider("Thời lượng chung của ảnh", $allPhotoSeconds, 0.5...15) { String(format: "%.1f s", $0) }
                Button { model.setAllPhotoDurations(allPhotoSeconds) } label: {
                    Label("Áp dụng cho mọi ảnh và nối tiếp", systemImage: "equal.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).font(.caption)
                .disabled(model.project.photos.isEmpty)
            }
        }

        private var projectsMenu: some View {
            Menu {
                Button { model.newProject() } label: { Label("Dự án mới", systemImage: "plus") }
                let others = recents.filter { $0.id != model.project.id }.prefix(8)
                if !others.isEmpty {
                    Divider()
                    ForEach(Array(others)) { summary in
                        Button { model.open(summary.id) } label: {
                            Text("\(summary.name) · \(summary.layerCount) lớp")
                        }
                    }
                }
            } label: {
                Label("Dự án khác…", systemImage: "folder")
            }
            .font(.caption)
        }

        // MARK: Layers

        private var layerSection: some View {
            let cores = model.selectedCores
            let locked = cores.allSatisfy(\.isLocked)
            let single = cores.count == 1 ? cores.first : nil
            return VStack(alignment: .leading, spacing: 12) {
                header(cores.count == 1 ? (single?.name ?? "Lớp") : "\(cores.count) lớp đã chọn")
                HStack {
                    Toggle("Hiển thị", isOn: model.flagBinding(\.isVisible))
                    Toggle("Khóa", isOn: model.flagBinding(\.isLocked))
                }.font(.caption)
                if locked {
                    Label("Lớp đang khóa: mở khóa để chỉnh sửa.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                Group {
                    group("Biến đổi") {
                        slider("Độ mờ đục", model.coreBinding(\.transform.opacity, fallback: 1), 0...1) { "\(Int($0 * 100))%" }
                        slider("Tỉ lệ", model.coreBinding(\.transform.scale, fallback: 1), LayerTransform.scaleRange) { String(format: "%.2f×", $0) }
                        slider("Góc xoay", model.coreBinding(\.transform.rotation, fallback: 0), -180...180) { "\(Int($0))°" }
                        slider("Vị trí X", model.coreBinding(\.transform.x, fallback: 0.5), LayerTransform.positionRange) { String(format: "%.2f", $0) }
                        slider("Vị trí Y", model.coreBinding(\.transform.y, fallback: 0.5), LayerTransform.positionRange) { String(format: "%.2f", $0) }
                    }
                    if single != nil {
                        group("Thời gian") {
                            slider("Bắt đầu", model.timeBinding(\.start, minimum: 0), 0...max(1, model.project.duration.seconds)) { Self.seconds($0) }
                            slider("Thời lượng", model.timeBinding(\.duration, minimum: LayerCore.minimumDuration.seconds), 0.1...max(2, model.project.duration.seconds)) { Self.seconds($0) }
                        }
                    }
                    if let photo = model.selectedPhotoLayer(), single?.track == .photo {
                        group("Ảnh") {
                            row("Khung") {
                                Picker("Khung", selection: model.photoBinding(\.fit, fallback: .fill)) {
                                    ForEach(PhotoFit.allCases) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                            }
                            infoLine("Kích thước gốc", "\(photo.pixelWidth)×\(photo.pixelHeight)")
                        }
                        group("Chuyển động Ken Burns") {
                            Picker("Kiểu", selection: model.photoBinding(\.motion.preset, fallback: .none)) {
                                ForEach(PhotoMotionPreset.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                            if photo.motion.isActive {
                                slider("Mức", model.photoBinding(\.motion.intensity, fallback: 0.15), PhotoMotion.intensityRange) { "\(Int($0 * 100))%" }
                            }
                        }
                        group("Chuyển cảnh vào") {
                            Picker("Kiểu", selection: model.photoBinding(\.transitionIn.kind, fallback: .none)) {
                                ForEach(PhotoTransitionKind.allCases) { Text($0.rawValue).tag($0) }
                            }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                            if photo.transitionIn.isActive {
                                slider("Thời lượng", model.photoBinding(\.transitionIn.duration, fallback: 0.8), PhotoTransition.durationRange) { String(format: "%.1f s", $0) }
                                Button { model.packPhotos() } label: {
                                    Label("Nối tiếp ảnh để chồng chuyển cảnh", systemImage: "rectangle.split.3x1").frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                        group("Thứ tự ảnh") {
                            HStack {
                                Button { model.movePhotoInOrder(-1) } label: { Label("Đưa lên trước", systemImage: "arrow.left") }
                                Button { model.movePhotoInOrder(1) } label: { Label("Đưa ra sau", systemImage: "arrow.right") }
                            }.font(.caption).buttonStyle(.bordered)
                        }
                    }
                    if single?.track == .text, model.selectedTextLayer() != nil {
                        textSection
                    }
                    if single?.track == .audio, let audio = model.selectedAudioLayer() {
                        audioSection(audio)
                    }
                    if single?.track == .effects, let effect = model.selectedEffectLayer() {
                        effectSection(effect)
                    }
                    if single?.track == .visualizer, let visualizer = model.selectedVisualizerLayer() {
                        visualizerSection(visualizer)
                    }
                    if single?.track == .lyrics, let lyrics = model.selectedLyricsLayer() {
                        lyricsSection(lyrics)
                    }
                    if single?.track == .vinyl, let vinyl = model.selectedVinylLayer() {
                        group("Đĩa than") { VinylCustomizationView(model: model, layer: vinyl) }
                    }
                }
                .disabled(locked)
                Button { model.resetTransformOfSelection() } label: {
                    Label("Đặt lại biến đổi", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).disabled(locked)
            }
        }

        private func effectSection(_ layer: EffectLayer) -> some View {
            group("Hiệu ứng: \(layer.kind.rawValue)") {
                Picker("Loại", selection: model.effectBinding(\.kind, fallback: .vignette)) {
                    ForEach(EffectKind.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                slider("Cường độ", model.effectBinding(\.intensity, fallback: 0.6), EffectLayer.intensityRange) { "\(Int($0 * 100))%" }
                if layer.kind == .shake || layer.kind == .lightLeak {
                    slider("Tốc độ", model.effectBinding(\.speed, fallback: 1), EffectLayer.speedRange) { String(format: "%.1fx", $0) }
                }
                if layer.kind == .lightLeak || layer.kind == .flash {
                    ColorPicker("Màu", selection: MusicVideoStudio.colorBinding(model.effectBinding(\.colorHex, fallback: "#FFB74D"), beginEdit: model.beginEdit)).font(.caption)
                }
                if layer.kind == .fadeBlack {
                    slider("Mờ vào", model.effectBinding(\.fadeIn, fallback: 1), EffectLayer.fadeRange) { String(format: "%.1f s", $0) }
                    slider("Mờ ra", model.effectBinding(\.fadeOut, fallback: 1), EffectLayer.fadeRange) { String(format: "%.1f s", $0) }
                }
                if layer.kind.needsAudio {
                    Stepper("Dùng mỗi \(layer.everyBeats) nhịp", value: model.effectBinding(\.everyBeats, fallback: 1), in: EffectLayer.beatsRange).font(.caption)
                    row("Nhạc") {
                        Picker("Nhạc", selection: model.effectBinding(\.audioLayerID, fallback: nil)) {
                            Text("Không gắn").tag(UUID?.none)
                            ForEach(model.project.audios) { Text($0.originalName).tag(Optional($0.core.id)) }
                        }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if model.effectBeats(for: layer).isEmpty {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Đang tìm nhịp (hoặc bài không có nhịp rõ)…").font(.caption2) }
                    }
                }
                Text("Kéo mép lớp trên dòng thời gian để chọn đoạn áp dụng.").font(.caption2).foregroundStyle(.secondary)
            }
        }

        private func visualizerSection(_ layer: VisualizerLayer) -> some View {
            group("Visualizer") {
                Picker("Kiểu", selection: model.visualizerBinding(\.style, fallback: .bars)) {
                    ForEach(VisualizerStyle.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                if !model.project.audios.isEmpty {
                    row("Nhạc") {
                        Picker("Nhạc", selection: model.visualizerBinding(\.audioLayerID, fallback: nil)) {
                            Text("Không gắn").tag(UUID?.none)
                            ForEach(model.project.audios) { Text($0.originalName).tag(Optional($0.core.id)) }
                        }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(VisualizerPalette.all) { palette in
                            Button { model.applyVisualizerPalette(palette) } label: {
                                Text(palette.name).font(.caption2.bold()).foregroundStyle(.black)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(LinearGradient(colors: [VisualizerExtraStyles.color(palette.first), VisualizerExtraStyles.color(palette.second)],
                                                               startPoint: .leading, endPoint: .trailing), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                ColorPicker("Màu đầu", selection: MusicVideoStudio.colorBinding(model.visualizerBinding(\.colorHex, fallback: "#4DD0E1"), beginEdit: model.beginEdit)).font(.caption)
                ColorPicker("Màu cuối", selection: MusicVideoStudio.colorBinding(model.visualizerBinding(\.secondColorHex, fallback: "#E040FB"), beginEdit: model.beginEdit)).font(.caption)
                slider("Số cột", Binding(get: { Double(layer.barCount) }, set: { model.visualizerBinding(\.barCount, fallback: 48).wrappedValue = Int($0.rounded()) }),
                       Double(VisualizerLayer.barRange.lowerBound)...Double(VisualizerLayer.barRange.upperBound)) { "\(Int($0))" }
                slider("Độ dày", model.visualizerBinding(\.thickness, fallback: 0.6), VisualizerLayer.thicknessRange) { "\(Int($0 * 100))%" }
                slider("Độ nhạy", model.visualizerBinding(\.sensitivity, fallback: 1.2), VisualizerLayer.sensitivityRange) { String(format: "%.1fx", $0) }
                slider("Độ mượt", model.visualizerBinding(\.smoothing, fallback: 0.7), VisualizerLayer.smoothingRange) { "\(Int($0 * 100))%" }
                slider("Rộng", model.visualizerBinding(\.width, fallback: 0.8), VisualizerLayer.widthRange) { "\(Int($0 * 100))%" }
                slider("Cao", model.visualizerBinding(\.height, fallback: 0.25), VisualizerLayer.heightRange) { "\(Int($0 * 100))%" }
                slider("Phát sáng", model.visualizerBinding(\.glow, fallback: 0.4), 0...1) { "\(Int($0 * 100))%" }
                slider("Phồng theo nhịp", model.visualizerBinding(\.beatPulse, fallback: 0.5), 0...1) { "\(Int($0 * 100))%" }
                Toggle("Bo tròn", isOn: model.visualizerBinding(\.rounded, fallback: true)).font(.caption)
                if model.spectrum(for: layer) == nil && layer.audioLayerID != nil {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Đang phân tích âm thanh…").font(.caption2) }
                }
            }
        }

        private func lyricsSection(_ lyrics: LyricsLayer) -> some View {
            group("Lời karaoke") {
                infoLine("Số dòng / từ", "\(lyrics.lines.count) / \(lyrics.wordCount)")
                Button { model.lyricsEditorLayerID = lyrics.core.id } label: {
                    Label("Nhập lời & chỉnh thời gian…", systemImage: "slider.horizontal.below.rectangle").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.cyan).font(.caption)
                Picker("Hiệu ứng", selection: model.lyricsBinding(\.animation, fallback: .fill)) {
                    ForEach(LyricAnimation.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                slider("Cỡ chữ", model.lyricsBinding(\.fontSize, fallback: 0.06), LyricsLayer.sizeRange) { String(format: "%.1f%%", $0 * 100) }
                row("Độ đậm") {
                    Picker("Độ đậm", selection: model.lyricsBinding(\.weight, fallback: .bold)) {
                        ForEach(TextWeight.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).labelsHidden()
                }
                ColorPicker("Màu từ đang hát", selection: MusicVideoStudio.colorBinding(model.lyricsBinding(\.highlightColorHex, fallback: "#FFD54F"), beginEdit: model.beginEdit)).font(.caption)
                ColorPicker("Màu chữ thường", selection: MusicVideoStudio.colorBinding(model.lyricsBinding(\.normalColorHex, fallback: "#FFFFFF"), beginEdit: model.beginEdit)).font(.caption)
                Toggle("Hiện dòng kế tiếp", isOn: model.lyricsBinding(\.showNextLine, fallback: true)).font(.caption)
                Toggle("Đổ bóng", isOn: model.lyricsBinding(\.hasShadow, fallback: true)).font(.caption)
                if !model.project.audios.isEmpty {
                    row("Gắn với nhạc (thời gian từ đi theo clip nhạc)") {
                        Picker("Nhạc", selection: model.lyricsBinding(\.audioLayerID, fallback: nil)) {
                            Text("Không gắn").tag(UUID?.none)
                            ForEach(model.project.audios) { Text($0.originalName).tag(Optional($0.core.id)) }
                        }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }

        private func audioSection(_ audio: AudioLayer) -> some View {
            group("Nhạc") {
                infoLine("Tệp", audio.originalName)
                infoLine("Độ dài tệp", ProjectTime(seconds: audio.sourceDuration).timecode(fps: model.project.fps))
                infoLine("Đang phát", "\(String(format: "%.2f", audio.sourceStart))s → \(String(format: "%.2f", audio.sourceStart + min(audio.availableSource, audio.core.duration.seconds)))s")
                AudioTrimmerView(model: model, layer: audio)
                slider("Âm lượng", model.audioBinding(\.volume, fallback: 1), AudioLayer.volumeRange) { "\(Int($0 * 100))%" }
                slider("Mờ dần vào", model.audioBinding(\.fadeIn, fallback: 0), 0...min(30, max(0.5, audio.core.duration.seconds / 2))) { String(format: "%.1f s", $0) }
                slider("Mờ dần ra", model.audioBinding(\.fadeOut, fallback: 0), 0...min(30, max(0.5, audio.core.duration.seconds / 2))) { String(format: "%.1f s", $0) }
                Toggle("Lặp lại đến hết clip", isOn: model.audioBinding(\.loops, fallback: false)).font(.caption)
                BeatCutControl(model: model)
                Button { model.fitPhotosToAudio() } label: {
                    Label("Chia đều ảnh theo độ dài nhạc", systemImage: "rectangle.split.3x1").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).font(.caption).disabled(model.project.photos.isEmpty)
                Text("Nút \"Hiển thị\" của lớp nhạc bật/tắt tiếng. Kéo clip để dời nhạc, kéo mép để cắt.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }

        private var textSection: some View {
            group("Chữ") {
                TextField("Nội dung", text: model.textBinding(\.text, fallback: ""), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .simultaneousGesture(TapGesture().onEnded { model.beginEdit() })
                slider("Cỡ chữ", model.textBinding(\.fontSize, fallback: 0.07), TextLayer.sizeRange) { String(format: "%.0f%%", $0 * 100) }
                row("Độ đậm") {
                    Picker("Độ đậm", selection: model.textBinding(\.weight, fallback: .bold)) {
                        ForEach(TextWeight.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).labelsHidden()
                }
                row("Căn lề") {
                    Picker("Căn lề", selection: model.textBinding(\.alignment, fallback: .center)) {
                        ForEach(TextAlignmentOption.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                ColorPicker("Màu chữ", selection: colorBinding).font(.caption)
                Toggle("Đổ bóng", isOn: model.textBinding(\.hasShadow, fallback: true)).font(.caption)
            }
        }

        private var colorBinding: Binding<Color> {
            let hex = model.textBinding(\.colorHex, fallback: "#FFFFFF")
            return Binding(
                get: {
                    let c = HexColor.components(hex.wrappedValue) ?? (1, 1, 1)
                    return Color(red: c.r, green: c.g, blue: c.b)
                },
                set: { color in
                    var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
                    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
                    model.beginEdit()
                    hex.wrappedValue = HexColor.string(r: Double(r), g: Double(g), b: Double(b))
                })
        }

        // MARK: Building blocks

        private func header(_ title: String) -> some View {
            Text(title).font(.subheadline.bold()).lineLimit(1)
        }

        private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }

        private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                content()
            }
        }

        private func infoLine(_ title: String, _ value: String) -> some View {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(value).monospacedDigit()
            }.font(.caption)
        }

        private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                            display: @escaping (Double) -> String) -> some View {
            VStack(spacing: 2) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(display(value.wrappedValue)).monospacedDigit().foregroundStyle(.cyan)
                }.font(.caption)
                Slider(value: value, in: range, onEditingChanged: { editing in
                    if editing { model.beginEdit() }
                }).tint(.cyan)
            }
        }

        private static func seconds(_ value: Double) -> String { String(format: "%.2f s", value) }
    }
}
