import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

extension MusicVideoStudio {
    /// Bottom toolbar. Every button acts on the project right now; tracks that
    /// are not built yet (music, lyrics, vinyl, visualizer, effects) have no
    /// button until their phase ships.
    struct LayerToolbarView: View {
        @ObservedObject var model: MusicVideoEditorModel
        @Binding var showInspector: Bool
        @State private var pickerItems: [PhotosPickerItem] = []
        @State private var showAudioImporter = false

        var body: some View {
            let hasSelection = !model.selection.isEmpty
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 100, matching: .images) {
                        item(model.isImporting ? model.importProgress : "Ảnh", "photo.badge.plus")
                    }
                    .disabled(model.isImporting)
                    .onChange(of: pickerItems) { items in
                        guard !items.isEmpty else { return }
                        Task {
                            await model.importPhotos(items)
                            pickerItems = []
                        }
                    }
                    Button { showAudioImporter = true } label: { item("Nhạc", "music.note") }
                        .disabled(model.isImporting)
                    Button { model.addLyrics() } label: { item("Lời", "music.mic") }
                    Button { model.addVisualizer() } label: { item("Visualizer", "chart.bar.fill") }
                    Button { model.addVinyl() } label: { item("Đĩa than", "opticaldisc") }
                    Button { model.addText() } label: { item("Chữ", "textformat") }
                    Divider().frame(height: 28)
                    Button { model.splitAtPlayhead() } label: { item("Cắt", "scissors") }
                    Button { model.rippleDeleteSelection() } label: { item("Xóa dồn", "arrow.left.to.line") }
                        .disabled(model.editableSelection.isEmpty)
                    Button { model.packPhotos() } label: { item("Nối tiếp", "rectangle.split.3x1") }
                        .disabled(model.project.photos.isEmpty)
                    Divider().frame(height: 28)
                    Button { model.selectAll() } label: { item("Chọn hết", "checklist") }
                        .disabled(model.project.layerCount == 0)
                    Button { model.multiSelect.toggle() } label: {
                        item("Chọn nhiều", model.multiSelect ? "checkmark.circle.fill" : "checkmark.circle", highlight: model.multiSelect)
                    }
                    Button { model.duplicateSelection() } label: { item("Nhân bản", "plus.square.on.square") }
                        .disabled(!hasSelection)
                    Button { model.resetTransformOfSelection() } label: { item("Đặt lại", "arrow.counterclockwise") }
                        .disabled(!hasSelection)
                    Button { model.showSafeArea.toggle() } label: {
                        item("Lưới", "grid", highlight: model.showSafeArea)
                    }
                    Button(role: .destructive) { model.deleteSelection() } label: { item("Xóa", "trash") }
                        .disabled(model.editableSelection.isEmpty)
                    Divider().frame(height: 28)
                    Button { showInspector.toggle() } label: {
                        item(hasSelection ? "Thuộc tính (\(model.selection.count))" : "Dự án", "slider.horizontal.3", highlight: showInspector)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(Color.white.opacity(0.05))
            .fileImporter(isPresented: $showAudioImporter, allowedContentTypes: [.audio]) { result in
                guard let url = try? result.get() else { return }
                Task { await model.importAudio(from: url) }
            }
        }

        private func item(_ title: String, _ symbol: String, highlight: Bool = false) -> some View {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(title).font(.system(size: 10)).lineLimit(1)
            }
            .foregroundStyle(highlight ? Color.cyan : .primary)
            .frame(minWidth: 56)
            .padding(.vertical, 4).padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
    }
}
