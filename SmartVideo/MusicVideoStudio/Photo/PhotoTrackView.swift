import SwiftUI

extension MusicVideoStudio {
    /// One block on a lane. Photo blocks show the real photo as a thumbnail;
    /// tapping selects, and the context menu offers the layer actions.
    struct ClipBlockView: View {
        let clip: TimelineClip
        let track: TrackKind
        @ObservedObject var model: MusicVideoEditorModel
        let height: CGFloat

        var body: some View {
            let selected = model.selection.contains(clip.id)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.35))
                if track == .photo, let layer = model.project.photos.first(where: { $0.core.id == clip.id }) {
                    PhotoThumbnailView(url: model.mediaURL(for: layer))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(clip.isVisible ? 0.9 : 0.3)
                }
                HStack(spacing: 3) {
                    Text(clip.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    if clip.isLocked { Image(systemName: "lock.fill").font(.system(size: 8)) }
                    if !clip.isVisible { Image(systemName: "eye.slash").font(.system(size: 8)) }
                }
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 2)
                .padding(.horizontal, 5).padding(.top, 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.cyan : color.opacity(0.7), lineWidth: selected ? 2.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { model.select(clip.id, additive: false) }
            .contextMenu {
                Button { select(); model.duplicateSelection() } label: { Label("Nhân bản", systemImage: "plus.square.on.square") }
                Button { select(); model.toggleFlag(\.isLocked) } label: {
                    Label(clip.isLocked ? "Mở khóa" : "Khóa", systemImage: clip.isLocked ? "lock.open" : "lock")
                }
                Button { select(); model.toggleFlag(\.isVisible) } label: {
                    Label(clip.isVisible ? "Ẩn" : "Hiện", systemImage: clip.isVisible ? "eye.slash" : "eye")
                }
                Button { select(); model.resetTransformOfSelection() } label: { Label("Đặt lại biến đổi", systemImage: "arrow.counterclockwise") }
                Button(role: .destructive) { select(); model.deleteSelection() } label: { Label("Xóa", systemImage: "trash") }
            }
            .accessibilityLabel("\(track.title): \(clip.title)")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        }

        private func select() {
            if !model.selection.contains(clip.id) { model.selection = [clip.id] }
        }

        private var color: Color { track == .photo ? .blue : .orange }
    }

    /// Small decoded thumbnail, loaded off the main thread and cached.
    struct PhotoThumbnailView: View {
        let url: URL
        @State private var image: UIImage?

        var body: some View {
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .task(id: url) {
                image = PhotoImageCache.shared.cached(url, maxPixel: 256)
                if image == nil { image = await PhotoImageCache.shared.load(url, maxPixel: 256) }
            }
        }
    }
}

extension MusicVideoStudio.MusicVideoEditorModel {
    /// Flip a boolean flag on every selected layer (one undo step).
    func toggleFlag(_ keyPath: WritableKeyPath<MusicVideoStudio.LayerCore, Bool>) {
        let ids = selection
        let newValue = !(selectedCores.first?[keyPath: keyPath] ?? false)
        edit { project in
            for id in ids { project.updateCore(id) { $0[keyPath: keyPath] = newValue } }
        }
    }
}
