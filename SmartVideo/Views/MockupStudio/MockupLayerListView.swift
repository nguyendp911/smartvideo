import SwiftUI

/// Layers on the current photo, top-most first: select, show/hide, lock,
/// reorder, duplicate and delete.
struct MockupLayerListView: View {
    @ObservedObject var session: MockupStudioSession
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LỚP").font(.caption2.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.mockupOverlays.count)/\(MockupStudioSession.maxLayers)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            let layers = Array(session.clipLayers.reversed())
            if layers.isEmpty {
                Text("Chưa có lớp nào. Chạm hoặc kéo một mẫu từ thư viện vào ảnh.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(layers) { layer in row(layer) }
            }
            HStack {
                Button { session.moveSelected(up: true) } label: { Label("Lên", systemImage: "arrow.up") }
                Button { session.moveSelected(up: false) } label: { Label("Xuống", systemImage: "arrow.down") }
            }
            .font(.caption).buttonStyle(.bordered).disabled(session.selectedID == nil)
        }
    }

    private func row(_ layer: MockupOverlayClip) -> some View {
        let selected = session.selectedID == layer.id
        let asset = MockupStudioCatalog.asset(layer.assetID)
        return HStack(spacing: 8) {
            Group {
                if let asset { MockupThumbnailView(asset: asset) } else { Color.white.opacity(0.08) }
            }
            .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(MockupOverlayRenderer.displayName(for: layer.assetID)).font(.caption).lineLimit(1)
                Text(session.kindOf(layer).title).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button { session.toggleHidden(layer.id) } label: {
                Image(systemName: layer.isHidden ? "eye.slash" : "eye")
            }.accessibilityLabel(layer.isHidden ? "Hiện lớp" : "Ẩn lớp")
            Button { session.toggleLocked(layer.id) } label: {
                Image(systemName: layer.locked ? "lock.fill" : "lock.open")
                    .foregroundStyle(layer.locked ? Color.orange : .secondary)
            }.accessibilityLabel(layer.locked ? "Mở khóa lớp" : "Khóa lớp")
            Button(role: .destructive) { session.delete(layer.id) } label: { Image(systemName: "trash") }
                .accessibilityLabel("Xóa lớp")
        }
        .font(.system(size: 13)).buttonStyle(.borderless)
        .padding(6)
        .background(selected ? Color.cyan.opacity(0.2) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
        .opacity(layer.isHidden ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { session.selectedID = layer.id }
    }
}
