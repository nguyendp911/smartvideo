import SwiftUI

extension MusicVideoStudio {
    /// The picture at the playhead. It draws from `TimelineEngine.renderItems`
    /// at the clock's FRAME time, the same function and rounding the exporter
    /// will use, so what plays here is what gets rendered.
    struct VideoPreviewView: View {
        @ObservedObject var model: MusicVideoEditorModel
        @ObservedObject var playback: PlaybackEngine

        var body: some View {
            GeometryReader { geo in
                let canvas = Self.fitted(ratio: model.project.aspect.ratio, in: geo.size)
                let items = TimelineEngine.renderItems(in: model.project, at: playback.state.frameTime)
                ZStack {
                    Color(white: 0.03)
                    ZStack {
                        Color.black
                        ForEach(items) { item in
                            LayerRenderView(item: item, canvas: canvas, time: playback.state.frameTime,
                                            selected: model.selection.contains(item.id),
                                            model: model)
                        }
                        TransformGuidesView(guides: model.transformGuides, showSafeArea: model.showSafeArea, canvas: canvas)
                        TransformOverlay(model: model, canvas: canvas, items: items)
                        if model.project.layerCount == 0 {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus").font(.title)
                                Text("Thêm ảnh để bắt đầu").font(.footnote)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: canvas.width, height: canvas.height)
                    .clipped()
                    .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onChange(of: Int(playback.state.time.seconds * 2)) { _ in
                model.prefetch(around: playback.state.frameTime)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Xem trước video")
        }

        static func fitted(ratio: Double, in available: CGSize) -> CGSize {
            guard ratio > 0, available.width > 8, available.height > 8 else { return CGSize(width: 1, height: 1) }
            let pad: CGFloat = 8
            let box = CGSize(width: available.width - pad * 2, height: available.height - pad * 2)
            let height = min(box.height, box.width / CGFloat(ratio))
            return CGSize(width: height * CGFloat(ratio), height: height)
        }
    }

    struct LayerRenderView: View {
        let item: RenderItem
        let canvas: CGSize
        let time: ProjectTime
        let selected: Bool
        let model: MusicVideoEditorModel

        var body: some View {
            switch item {
            case .photo(let layer):
                PhotoLayerView(layer: layer, url: model.mediaURL(for: layer), canvas: canvas, time: time, selected: selected)
            case .text(let layer):
                TextLayerView(layer: layer, canvas: canvas, selected: selected)
            case .lyrics(let layer):
                KaraokeLyricsView(layer: layer, canvas: canvas,
                                  sourceTime: LyricsTiming.sourceTime(layer, in: model.project, at: time), selected: selected)
            case .visualizer(let layer):
                let source = VisualizerTiming.sourceTime(layer, in: model.project, at: time)
                VisualizerLayerView(layer: layer, canvas: canvas,
                                    frame: VisualizerFrame.make(layer: layer, spectrum: model.spectrum(for: layer), sourceTime: source),
                                    time: time.seconds, selected: selected)
            case .vinyl(let layer):
                VinylLayerView(layer: layer, canvas: canvas, time: time,
                               coverURL: layer.coverFile.map { model.manager.mediaURL(projectID: model.project.id, file: $0) },
                               selected: selected)
            }
        }
    }

    struct PhotoLayerView: View {
        let layer: PhotoLayer
        let url: URL
        let canvas: CGSize
        let time: ProjectTime
        let selected: Bool
        @State private var image: UIImage?

        init(layer: PhotoLayer, url: URL, canvas: CGSize, time: ProjectTime, selected: Bool) {
            self.layer = layer
            self.url = url
            self.canvas = canvas
            self.time = time
            self.selected = selected
            _image = State(initialValue: PhotoImageCache.shared.cached(
                url, maxPixel: PhotoImageCache.bucket(max(canvas.width, canvas.height) * UIScreen.main.scale)))
        }

        private var pixels: Int { PhotoImageCache.bucket(max(canvas.width, canvas.height) * UIScreen.main.scale) }

        var body: some View {
            let t = layer.core.transform
            // Both are pure functions of the clock's frame time, so they look
            // identical after a seek, a pause or in the exported file.
            let kb = KenBurnsEffect.transform(
                layer.motion,
                progress: KenBurnsEffect.progress(start: layer.core.start, duration: layer.core.duration, at: time))
            let tr = PhotoTransitionEngine.effect(for: layer, at: time)
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: layer.fit == .fill ? .fill : .fit)
                        .frame(width: canvas.width, height: canvas.height)
                        .scaleEffect(kb.scale)
                        .offset(x: CGFloat(kb.offsetX) * canvas.width, y: CGFloat(kb.offsetY) * canvas.height)
                        .frame(width: canvas.width, height: canvas.height)
                        .clipped()
                }
                if selected { Rectangle().strokeBorder(Color.cyan, lineWidth: 2) }
            }
            .frame(width: canvas.width, height: canvas.height)
            .scaleEffect(t.scale * tr.scale)
            .rotationEffect(.degrees(t.rotation))
            .offset(x: CGFloat(t.x - 0.5 + tr.offsetX) * canvas.width, y: CGFloat(t.y - 0.5 + tr.offsetY) * canvas.height)
            .opacity(t.opacity * tr.opacity)
            .task(id: url) {
                if image == nil { image = PhotoImageCache.shared.cached(url, maxPixel: pixels) }
                if image == nil { image = await PhotoImageCache.shared.load(url, maxPixel: pixels) }
            }
        }
    }

    struct TextLayerView: View {
        let layer: TextLayer
        let canvas: CGSize
        let selected: Bool

        private var weight: Font.Weight {
            switch layer.weight {
            case .regular: return .regular
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            }
        }

        private var alignment: TextAlignment {
            switch layer.alignment {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }

        var body: some View {
            let t = layer.core.transform
            let rgb = HexColor.components(layer.colorHex) ?? (1, 1, 1)
            ZStack {
                Text(layer.text.isEmpty ? " " : layer.text)
                    .font(.system(size: max(4, CGFloat(layer.fontSize) * canvas.height), weight: weight))
                    .foregroundColor(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                    .multilineTextAlignment(alignment)
                    .frame(maxWidth: canvas.width * 0.92)
                    .shadow(color: layer.hasShadow ? Color.black.opacity(0.65) : .clear,
                            radius: max(1, CGFloat(layer.fontSize) * canvas.height * 0.06), x: 0, y: 2)
                    .padding(4)
                    .overlay { if selected { Rectangle().strokeBorder(Color.cyan, lineWidth: 2) } }
                    .scaleEffect(t.scale)
                    .rotationEffect(.degrees(t.rotation))
                    .position(x: canvas.width * CGFloat(t.x), y: canvas.height * CGFloat(t.y))
                    .opacity(t.opacity)
            }
            .frame(width: canvas.width, height: canvas.height)
        }
    }
}
