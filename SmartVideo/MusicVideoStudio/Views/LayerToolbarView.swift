import SwiftUI
import PhotosUI

extension MusicVideoStudio {
    /// Bottom toolbar. Every button acts on the project right now; tracks that
    /// are not built yet (music, lyrics, vinyl, visualizer, effects) have no
    /// button until their phase ships.
    struct LayerToolbarView: View {
        @ObservedObject var model: MusicVideoEditorModel
        @Binding var showInspector: Bool
        @State private var pickerItems: [PhotosPickerItem] = []

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
                    Button { model.addText() } label: { item("Chữ", "textformat") }
                    Divider().frame(height: 28)
                    Button { model.multiSelect.toggle() } label: {
                        item("Chọn nhiều", model.multiSelect ? "checkmark.circle.fill" : "checkmark.circle", highlight: model.multiSelect)
                    }
                    Button { model.duplicateSelection() } label: { item("Nhân bản", "plus.square.on.square") }
                        .disabled(!hasSelection)
                    Button { model.resetTransformOfSelection() } label: { item("Đặt lại", "arrow.counterclockwise") }
                        .disabled(!hasSelection)
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
