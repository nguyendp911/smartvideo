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
