import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct EditorView: View {
    @StateObject private var model = EditorViewModel()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showAudioImporter = false
    @State private var selectedClipID: UUID?
    @State private var previewPlayer: AVPlayer?

    private var selectedClip: TimelineClip? {
        model.clips.first { $0.id == selectedClipID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    preview
                } header: {
                    Label("Màn hình xem trước", systemImage: "play.rectangle")
                }

                Section {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 30,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("Thêm ảnh hoặc video", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(.cyan)
                    }
                    .disabled(model.isImporting || model.isExporting)

                    if model.isImporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Đang nhập dữ liệu vào iPhone…")
                        }
                    }

                    if model.clips.isEmpty {
                        Text("Chưa có clip. Hãy thêm ảnh hoặc video từ thư viện.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(model.clips) { clip in
                        Button {
                            selectedClipID = clip.id
                        } label: {
                            HStack(spacing: 12) {
                                clipIcon(clip)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(clip.kind == .image ? "Ảnh" : "Video")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(clip.filename)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Text(timeLabel(clip.duration))
                                    .monospacedDigit()
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if selectedClipID == clip.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.cyan)
                                }
                            }
                        }
                        .listRowBackground(selectedClipID == clip.id
                                           ? Color.cyan.opacity(0.10)
                                           : Color.clear)
                    }
                    .onMove(perform: model.move)
                    .onDelete(perform: model.remove)
                } header: {
                    HStack {
                        Text("Timeline · \(model.clips.count) clip")
                        Spacer()
                        Text(timeLabel(model.totalDuration))
                    }
                } footer: {
                    Text("Chạm vào clip để chỉnh thời lượng. Bấm Sửa để kéo sắp xếp hoặc xóa clip.")
                }

                if let selectedClip {
                    Section("Chỉnh đoạn đang chọn") {
                        if selectedClip.kind == .video {
                            HStack {
                                Text("Bắt đầu từ")
                                Spacer()
                                Text(timeLabel(selectedClip.startTime))
                            }
                            Slider(
                                value: clipStartBinding(for: selectedClip.id),
                                in: 0...max(0, selectedClip.originalDuration - 0.1),
                                step: 0.1
                            )
                        }
                        HStack {
                            Text("Độ dài đoạn")
                            Spacer()
                            Text(timeLabel(selectedClip.duration))
                        }
                        Slider(
                            value: clipDurationBinding(for: selectedClip.id),
                            in: 0.1...max(0.1, selectedClip.availableDuration),
                            step: 0.1
                        )
                        .tint(.cyan)
                    }
                }

                Section("Âm thanh") {
                    Button {
                        showAudioImporter = true
                    } label: {
                        Label(
                            model.musicURL == nil ? "Thêm nhạc nền" : "Thay nhạc nền",
                            systemImage: "music.note"
                        )
                    }

                    if let url = model.musicURL {
                        HStack {
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                model.musicURL = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("Âm lượng nhạc nền \(Int(model.musicVolume * 100))%")
                            Slider(value: $model.musicVolume, in: 0...1)
                                .tint(.cyan)
                        }
                    }
                    Toggle("Giữ âm thanh của video gốc", isOn: $model.keepOriginalAudio)
                }

                Section("Thiết lập xuất video") {
                    Picker("Khung hình", selection: $model.canvas) {
                        ForEach(CanvasFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    Picker("Độ phân giải", selection: $model.quality) {
                        ForEach(RenderQuality.allCases) { setting in
                            Text(setting.rawValue).tag(setting)
                        }
                    }
                    HStack {
                        Text("Tốc độ khung hình")
                        Spacer()
                        Text("30 FPS")
                            .foregroundStyle(.secondary)
                    }
                    Text("Dùng GPU và bộ mã hóa phần cứng của iPhone; ảnh và clip được căn giữa, không méo hình.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        previewPlayer?.pause()
                        model.export()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Xuất video MP4", systemImage: "square.and.arrow.up")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .disabled(model.clips.isEmpty || model.isExporting || model.isImporting)
                    .tint(.cyan)

                    if model.isExporting {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Đang render trên iPhone")
                                    .font(.subheadline.bold())
                                Text("Vui lòng giữ ứng dụng ở màn hình trước.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let url = model.exportedURL {
                        Label("Đã tạo: \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline)

                        Button {
                            Task { await model.saveToPhotos() }
                        } label: {
                            Label(
                                model.didSaveToPhotos ? "Đã lưu vào Ảnh" : "Lưu vào thư viện Ảnh",
                                systemImage: "square.and.arrow.down"
                            )
                        }
                        .disabled(model.didSaveToPhotos)

                        ShareLink(item: url) {
                            Label("Chia sẻ / Lưu vào Tệp", systemImage: "square.and.arrow.up.on.square")
                        }
                    }
                } footer: {
                    Text("Bản MVP: nối clip dạng cắt thẳng, căn tỷ lệ, ghép nhạc. Chưa hỗ trợ crossfade, chữ động hoặc xuất nền.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.055, green: 0.067, blue: 0.09))
            .navigationTitle("SmartVideo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .disabled(model.clips.isEmpty || model.isExporting)
                }
            }
            .onChange(of: pickerItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    await model.importSelections(items)
                    pickerItems = []
                }
            }
            .onChange(of: selectedClipID) { _ in
                updatePreview()
            }
            .onChange(of: model.clips.count) { _ in
                if !model.clips.contains(where: { $0.id == selectedClipID }) {
                    selectedClipID = model.clips.first?.id
                }
            }
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { outcome in
                switch outcome {
                case .success(let urls):
                    if let url = urls.first { model.importMusic(from: url) }
                case .failure(let error):
                    model.errorText = error.localizedDescription
                }
            }
            .alert("SmartVideo", isPresented: Binding(
                get: { model.errorText != nil },
                set: { if !$0 { model.errorText = nil } }
            )) {
                Button("Đóng", role: .cancel) { model.errorText = nil }
            } message: {
                Text(model.errorText ?? "")
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black)

            if let clip = selectedClip {
                if clip.kind == .image,
                   let image = UIImage(contentsOfFile: clip.fileURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else if clip.kind == .video, let previewPlayer {
                    VideoPlayer(player: previewPlayer)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 40))
                    Text("Thêm media để bắt đầu dựng video")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Xem trước clip đang chọn")
    }

    @ViewBuilder
    private func clipIcon(_ clip: TimelineClip) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.white.opacity(0.06))
            if clip.kind == .image, let photo = UIImage(contentsOfFile: clip.fileURL.path) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipped()
            } else {
                Image(systemName: "film")
                    .foregroundStyle(.cyan)
                    .font(.title2)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func clipStartBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { model.clips.first(where: { $0.id == id })?.startTime ?? 0 },
            set: { value in
                guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
                model.clips[index].startTime = value
                model.clips[index].duration = min(
                    model.clips[index].duration,
                    model.clips[index].availableDuration
                )
            }
        )
    }

    private func clipDurationBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { model.clips.first(where: { $0.id == id })?.duration ?? 1 },
            set: { value in
                guard let index = model.clips.firstIndex(where: { $0.id == id }) else { return }
                model.clips[index].duration = max(0.1, min(value, model.clips[index].availableDuration))
            }
        )
    }

    private func updatePreview() {
        previewPlayer?.pause()
        if let clip = selectedClip, clip.kind == .video {
            let player = AVPlayer(url: clip.fileURL)
            player.seek(to: CMTime(seconds: clip.startTime, preferredTimescale: 600))
            previewPlayer = player
        } else {
            previewPlayer = nil
        }
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0.0s" }
        return String(format: "%.1fs", seconds)
    }
}
