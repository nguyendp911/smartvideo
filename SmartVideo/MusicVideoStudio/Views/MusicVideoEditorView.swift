import SwiftUI

extension MusicVideoStudio {
    /// The Music Photo Video Studio screen: top bar, preview, transport,
    /// timeline, bottom toolbar and the inspector. Phone portrait stacks them;
    /// landscape and iPad put the inspector beside the preview.
    struct MusicVideoEditorView: View {
        @StateObject private var model: MusicVideoEditorModel
        @Environment(\.dismiss) private var dismiss
        @Environment(\.scenePhase) private var scenePhase
        @State private var showInspector = false
        @State private var showExport = false

        init(manager: ProjectManager = ProjectManager()) {
            _model = StateObject(wrappedValue: MusicVideoEditorModel(manager: manager))
        }

        var body: some View {
            GeometryReader { geo in
                let sideBySide = geo.size.width >= 820
                VStack(spacing: 0) {
                    topBar
                    Divider().overlay(Color.white.opacity(0.08))
                    if sideBySide {
                        HStack(spacing: 0) {
                            previewColumn
                            Divider().overlay(Color.white.opacity(0.08))
                            PropertiesInspectorView(model: model, playback: model.playback)
                                .frame(width: min(340, geo.size.width * 0.32))
                        }
                    } else {
                        previewColumn
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    TimelineTracksView(model: model, playback: model.playback)
                        .frame(height: model.timelineHeight)
                    LayerToolbarView(model: model, showInspector: sideBySide ? Binding<Bool>.constant(true) : $showInspector)
                }
                .sheet(isPresented: Binding(
                    get: { showInspector && !sideBySide },
                    set: { showInspector = $0 })) {
                    PropertiesInspectorView(model: model, playback: model.playback)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .preferredColorScheme(.dark)
                }
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.075).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .sheet(item: Binding(
                get: { model.lyricsEditorLayerID.map { LyricsSheetID(id: $0) } },
                set: { model.lyricsEditorLayerID = $0?.id })) { sheet in
                LyricsEditorView(model: model, layerID: sheet.id)
                    .presentationDetents([.fraction(0.55), .large])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showExport) {
                ExportSheetView(model: model)
                    .presentationDetents([.large])
                    .preferredColorScheme(.dark)
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active { model.playback.pause(); model.saveNow() }
            }
            .onDisappear {
                model.playback.pause()
                model.saveNow()
            }
        }

        private var previewColumn: some View {
            VStack(spacing: 0) {
                VideoPreviewView(model: model, playback: model.playback)
                    .frame(minHeight: 160)
                if let message = model.statusMessage {
                    Text(message).font(.caption2).foregroundStyle(.orange).padding(.bottom, 2)
                }
                PlaybackControlsView(playback: model.playback)
            }
        }

        private var topBar: some View {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Đóng")
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.project.name).font(.subheadline.bold()).lineLimit(1)
                    Text("Music Photo Video Studio")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo).accessibilityLabel("Hoàn tác")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo).accessibilityLabel("Làm lại")
                Menu {
                    ForEach(AspectRatio.allCases) { aspect in
                        Button {
                            model.setAspect(aspect)
                        } label: {
                            if model.project.aspect == aspect { Label(aspect.rawValue, systemImage: "checkmark") }
                            else { Text(aspect.rawValue) }
                        }
                    }
                } label: {
                    Text(model.project.aspect.rawValue).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .accessibilityLabel("Tỉ lệ khung hình")
                Button { model.saveNow() } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Lưu dự án")
                Button { showExport = true } label: {
                    Text("Xuất").font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.cyan, in: Capsule()).foregroundStyle(.black)
                }
                .accessibilityLabel("Xuất video")
            }
            .font(.system(size: 16, weight: .semibold))
            .buttonStyle(.borderless)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    struct LyricsSheetID: Identifiable { let id: UUID }

    /// Entry card shown in the main editor's tool tab.
    struct MusicVideoStudioLauncherPanel: View {
        @State private var show = false

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label("Music Photo Video Studio", systemImage: "music.note.tv").font(.headline)
                Text("Biến ảnh thành video nhạc trong một trình dựng riêng: ảnh, nhạc, lời karaoke, đĩa than, visualizer, hiệu ứng và chữ trên nhiều track; kéo, phóng to, xoay ngay trên khung; một đồng hồ chung theo khung hình cho xem trước và xuất video 720p đến 4K (H.264/HEVC, MP4/MOV).")
                    .font(.caption).foregroundStyle(.secondary)
                Button { show = true } label: {
                    Label("Mở Music Video Studio", systemImage: "play.rectangle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.cyan)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .fullScreenCover(isPresented: $show) { MusicVideoEditorView() }
        }
    }
}
