import SwiftUI

extension MusicVideoStudio {
    /// One block on a lane. Photo blocks show the real photo as a thumbnail;
    /// tapping selects, and the context menu offers the layer actions.
    struct ClipBlockView: View {
        let clip: TimelineClip
        let track: TrackKind
        @ObservedObject var model: MusicVideoEditorModel
        let height: CGFloat
        @State private var session: MusicVideoEditorModel.ClipEditSession?

        var body: some View {
            let selected = model.selection.contains(clip.id)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.35))
                if track == .photo, let layer = model.project.photos.first(where: { $0.core.id == clip.id }) {
                    PhotoThumbnailView(url: model.mediaURL(for: layer))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(clip.isVisible ? 0.9 : 0.3)
                }
                if track == .audio, let layer = model.project.audios.first(where: { $0.core.id == clip.id }) {
                    AudioWaveformView(layer: layer, url: model.manager.mediaURL(projectID: model.project.id, file: layer.mediaFile))
                        .padding(.vertical, 2)
                        .opacity(clip.isVisible ? 1 : 0.3)
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
            .overlay { if selected && !clip.isLocked { trimHandles } }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture { model.select(clip.id, additive: false) }
            // Only a SELECTED clip drags, so an unselected one still lets the
            // timeline scroll when the finger starts on it.
            .gesture(moveGesture, including: selected && !clip.isLocked ? .all : .subviews)
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

        private var moveGesture: some Gesture {
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if session == nil { session = model.beginClipEdit(clip.id) }
                    guard let session else { return }
                    model.moveClips(session, deltaSeconds: Double(value.translation.width) / model.scale.pixelsPerSecond)
                }
                .onEnded { _ in
                    model.endClipEdit()
                    session = nil
                }
        }

        private var trimHandles: some View {
            HStack(spacing: 0) {
                handle(.start)
                Spacer(minLength: 0)
                handle(.end)
            }
        }

        private func handle(_ edge: TrimEdge) -> some View {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.cyan)
                .frame(width: 8)
                .overlay(Capsule().fill(Color.black.opacity(0.55)).frame(width: 2, height: 14))
                .frame(width: 22)                                    // generous touch target
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if session == nil { session = model.beginClipEdit(clip.id) }
                            guard let session else { return }
                            model.trimClip(session, edge: edge,
                                           deltaSeconds: Double(value.translation.width) / model.scale.pixelsPerSecond)
                        }
                        .onEnded { _ in
                            model.endClipEdit()
                            session = nil
                        })
                .accessibilityLabel(edge == .start ? "Cắt đầu clip" : "Cắt cuối clip")
        }

        private func select() {
            if !model.selection.contains(clip.id) { model.selection = [clip.id] }
        }

        private var color: Color {
            switch track {
            case .photo: return .blue
            case .audio: return .green
            case .text: return .orange
            case .vinyl: return .pink
            case .lyrics: return .yellow
            case .visualizer: return .purple
            case .effects: return .mint
            }
        }
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
