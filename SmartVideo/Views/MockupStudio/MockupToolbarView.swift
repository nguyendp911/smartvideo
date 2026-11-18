import SwiftUI

/// Top bar: close, source clip, undo/redo, layer actions, save and export.
struct MockupToolbarView: View {
    @ObservedObject var session: MockupStudioSession
    @ObservedObject var model: EditorViewModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onClose) { Image(systemName: "xmark") }
                .accessibilityLabel("Đóng Mockup Studio")
            VStack(alignment: .leading, spacing: 1) {
                Text("Mockup Studio").font(.subheadline.bold())
                Text(session.clipTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)

            Group {
                Button { session.goToClip(offset: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled((session.context?.index ?? 0) <= 0)
                    .accessibilityLabel("Ảnh/clip trước")
                Button { session.goToClip(offset: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled((session.context?.index ?? 0) >= model.clips.count - 1)
                    .accessibilityLabel("Ảnh/clip sau")
                Divider().frame(height: 18)
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                    .accessibilityLabel("Hoàn tác")
                Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                    .accessibilityLabel("Làm lại")
                Divider().frame(height: 18)
                Button { session.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(session.selectedID == nil)
                    .accessibilityLabel("Nhân bản lớp")
                Button(role: .destructive) { session.deleteSelected() } label: { Image(systemName: "trash") }
                    .disabled(session.selectedID == nil)
                    .accessibilityLabel("Xóa lớp")
                Button { session.resetSelected() } label: { Image(systemName: "arrow.counterclockwise") }
                    .disabled(session.selectedID == nil)
                    .accessibilityLabel("Đặt lại lớp")
                Divider().frame(height: 18)
                Button { session.saveProject() } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Lưu dự án")
                exportMenu
            }
            .font(.system(size: 15, weight: .semibold))
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    private var exportMenu: some View {
        Menu {
            ForEach(MockupStudioRenderer.ExportFormat.allCases) { format in
                Button("Xuất ảnh \(format.rawValue) (độ phân giải gốc)") { session.export(format) }
            }
            if let url = session.exportedURL {
                Divider()
                ShareLink(item: url) { Label("Chia sẻ ảnh vừa xuất", systemImage: "square.and.arrow.up") }
                Button { session.saveExportToPhotos() } label: {
                    Label("Lưu vào thư viện Ảnh", systemImage: "photo.badge.plus")
                }
            }
        } label: {
            if session.isExporting { ProgressView().controlSize(.small) }
            else { Image(systemName: "square.and.arrow.up.on.square") }
        }
        .disabled(session.isExporting || !session.hasSource)
        .accessibilityLabel("Xuất ảnh")
    }
}
