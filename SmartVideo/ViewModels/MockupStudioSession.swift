import SwiftUI
import CoreImage
import AVFoundation

/// State and actions of one Mockup Studio editing session. The LAYERS live in
/// `EditorViewModel.mockupOverlays` (single source of truth shared with the
/// timeline, undo/redo, project saving and video export); this object adds
/// library browsing, selection, the live Core Image preview and still export.
@MainActor
final class MockupStudioSession: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case all = "Tất cả", favorites = "Yêu thích", recents = "Gần đây"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .favorites: return "star.fill"
            case .recents: return "clock.fill"
            }
        }
    }

    struct ClipContext {
        let index: Int
        let clip: TimelineClip
        let start: Double
        let local: Double
        /// Project time shown on the canvas (kept just inside the clip).
        var second: Double { start + local }
    }

    static let maxLayers = 12

    let model: EditorViewModel

    // Library
    @Published var section: Section = .all
    @Published var category: MockupStudioCategory?
    @Published var kind: MockupStudioKind?
    @Published var query = ""
    @Published private(set) var usage = MockupStudioUsageStore.load()

    // Canvas
    @Published var selectedID: UUID?
    @Published var ghostAssetID: String?
    @Published private(set) var rendered: UIImage?
    @Published private(set) var sourceSize = CGSize(width: 4, height: 5)
    @Published private(set) var isRendering = false
    @Published private(set) var hasSource = false

    // Feedback / export
    @Published private(set) var message = ""
    @Published private(set) var isExporting = false
    @Published private(set) var exportedURL: URL?

    private var source: CIImage?
    private var sourceKey = ""
    private var loadTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var quickCache: [String: UIImage] = [:]

    init(model: EditorViewModel) {
        self.model = model
    }

    // MARK: Library

    var visibleAssets: [MockupStudioAsset] {
        switch section {
        case .all:
            return MockupStudioCatalog.filtered(category: category, kind: kind, query: query)
        case .favorites:
            return MockupStudioCatalog.filtered(category: category, kind: kind, query: query, ids: usage.favorites)
        case .recents:
            return MockupStudioCatalog.filtered(category: category, kind: kind, query: query, ids: usage.recents)
        }
    }

    func isFavorite(_ asset: MockupStudioAsset) -> Bool { usage.isFavorite(asset.id) }

    func toggleFavorite(_ asset: MockupStudioAsset) {
        usage.toggleFavorite(asset.id)
        MockupStudioUsageStore.save(usage)
    }

    func count(in category: MockupStudioCategory) -> Int { MockupStudioCatalog.count(in: category) }

    // MARK: Clip context

    var context: ClipContext? {
        guard let position = model.clipAtTimeline(model.timelineSecond),
              model.clips.indices.contains(position.index) else { return nil }
        let clip = model.clips[position.index]
        let local = max(0, min(position.local, max(0, clip.renderedDuration - 0.02)))
        return ClipContext(index: position.index, clip: clip,
                           start: model.timelineStart(of: position.index), local: local)
    }

    var clipTitle: String {
        guard let ctx = context else { return "Chưa có ảnh/video" }
        return "\(ctx.index + 1)/\(model.clips.count) · \(ctx.clip.fileURL.lastPathComponent)"
    }

    func goToClip(offset: Int) {
        guard let ctx = context else { return }
        let target = ctx.index + offset
        guard model.clips.indices.contains(target) else { return }
        model.timelineSecond = model.timelineStart(of: target) + 0.02
        selectedID = nil
        refreshSource()
    }

    /// Layers that overlap the clip on screen (what the canvas shows).
    var clipLayers: [MockupOverlayClip] {
        guard let ctx = context else { return [] }
        let end = ctx.start + ctx.clip.renderedDuration
        return model.mockupOverlays.filter { $0.start < end && $0.end > ctx.start }
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return model.mockupOverlays.firstIndex { $0.id == selectedID }
    }

    var selectedLayer: MockupOverlayClip? { selectedIndex.map { model.mockupOverlays[$0] } }

    func kindOf(_ layer: MockupOverlayClip) -> MockupStudioKind {
        MockupStudioCatalog.asset(layer.assetID)?.kind ?? .overlay
    }

    // MARK: Layer operations (each is one undo step)

    static func makeLayer(_ asset: MockupStudioAsset, start: Double, duration: Double,
                          at point: CGPoint? = nil) -> MockupOverlayClip {
        var clip = MockupOverlayClip()
        clip.assetID = asset.id
        clip.start = max(0, start)
        clip.duration = max(0.25, duration)
        clip.opacity = asset.defaultOpacity
        clip.blendMode = asset.defaultBlendMode
        clip.centerX = Double(point?.x ?? 0.5)
        clip.centerY = Double(point?.y ?? 0.5)
        clip.scale = 1
        clip.rotationDegrees = 0
        clip.blurRadius = 0
        clip.feather = 0
        clip.brightness = 0
        clip.contrast = 1
        clip.saturation = 1
        clip.warmth = 0
        clip.mask = MockupMask()
        clip.animationStyle = .none
        clip.depthMode = .front
        clip.avoidFace = false
        clip.flipHorizontal = false
        clip.flipVertical = false
        return clip
    }

    /// Click or drop: adds the asset on the current photo.
    func add(_ asset: MockupStudioAsset, at point: CGPoint? = nil) {
        guard let ctx = context else {
            message = "Hãy thêm ảnh hoặc video vào dự án trước."
            return
        }
        let clipEnd = ctx.start + ctx.clip.renderedDuration
        model.checkpoint()
        if asset.kind != .overlay {
            // One frame/product and one background at a time.
            model.mockupOverlays.removeAll { layer in
                MockupStudioCatalog.asset(layer.assetID)?.kind == asset.kind &&
                    layer.start < clipEnd && layer.end > ctx.start
            }
        }
        guard model.mockupOverlays.count < Self.maxLayers else {
            message = "Tối đa \(Self.maxLayers) lớp mockup cho mỗi dự án."
            return
        }
        let layer = Self.makeLayer(
            asset, start: ctx.start, duration: ctx.clip.renderedDuration,
            at: asset.kind == .overlay ? point : nil
        )
        model.mockupOverlays.append(layer)
        selectedID = layer.id
        usage.recordUse(asset.id)
        MockupStudioUsageStore.save(usage)
        message = ""
    }

    func duplicateSelected() {
        guard let index = selectedIndex, model.mockupOverlays.count < Self.maxLayers else {
            if selectedIndex != nil { message = "Tối đa \(Self.maxLayers) lớp mockup." }
            return
        }
        model.checkpoint()
        var copy = model.mockupOverlays[index]
        copy.id = UUID()
        copy.centerX = min(1.2, copy.centerX + 0.04)
        copy.centerY = min(1.2, copy.centerY + 0.04)
        model.mockupOverlays.insert(copy, at: index + 1)
        selectedID = copy.id
    }

    func deleteSelected() {
        guard let index = selectedIndex else { return }
        model.checkpoint()
        model.mockupOverlays.remove(at: index)
        selectedID = nil
    }

    func delete(_ id: UUID) {
        guard let index = model.mockupOverlays.firstIndex(where: { $0.id == id }) else { return }
        model.checkpoint()
        model.mockupOverlays.remove(at: index)
        if selectedID == id { selectedID = nil }
    }

    func resetSelected() {
        guard let index = selectedIndex,
              let asset = MockupStudioCatalog.asset(model.mockupOverlays[index].assetID) else { return }
        model.checkpoint()
        let old = model.mockupOverlays[index]
        var fresh = Self.makeLayer(asset, start: old.start, duration: old.duration)
        fresh.id = old.id
        fresh.locked = old.locked
        fresh.isHidden = old.isHidden
        model.mockupOverlays[index] = fresh
    }

    func moveSelected(up: Bool) {
        guard let index = selectedIndex else { return }
        let target = up ? index + 1 : index - 1
        guard model.mockupOverlays.indices.contains(target) else { return }
        model.checkpoint()
        model.mockupOverlays.swapAt(index, target)
    }

    func toggleHidden(_ id: UUID) {
        guard let index = model.mockupOverlays.firstIndex(where: { $0.id == id }) else { return }
        model.checkpoint()
        model.mockupOverlays[index].isHidden.toggle()
    }

    func toggleLocked(_ id: UUID) {
        guard let index = model.mockupOverlays.firstIndex(where: { $0.id == id }) else { return }
        model.checkpoint()
        model.mockupOverlays[index].locked.toggle()
    }

    /// Binding by layer id (safe if the array changes under it, e.g. after undo).
    /// `undoable: true` records one undo step per change (toggles, pickers);
    /// sliders pass false and call `beginEdit()` once when the drag starts.
    func binding<T>(_ id: UUID, _ keyPath: WritableKeyPath<MockupOverlayClip, T>,
                    fallback: T, undoable: Bool = false) -> Binding<T> {
        Binding(
            get: { [model] in model.mockupOverlays.first { $0.id == id }?[keyPath: keyPath] ?? fallback },
            set: { [model] value in
                if let index = model.mockupOverlays.firstIndex(where: { $0.id == id }) {
                    if undoable { model.checkpoint() }
                    model.mockupOverlays[index][keyPath: keyPath] = value
                }
            }
        )
    }

    /// Call when a drag/slider/gesture starts so the whole interaction is one undo step.
    func beginEdit() { model.checkpoint() }

    func undo() { model.undoEdit(); validateSelection() }
    func redo() { model.redoEdit(); validateSelection() }

    private func validateSelection() {
        if let selectedID, !model.mockupOverlays.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }
    }

    func saveProject() {
        model.saveProject()
        message = model.lastSaveMessage ?? "Đã lưu dự án."
    }

    // MARK: Source + live preview

    func refreshSource() {
        guard let ctx = context else {
            source = nil; hasSource = false; rendered = nil
            return
        }
        let key = "\(ctx.clip.id)|\(Int(ctx.local * 4))|\(ctx.clip.imageLook)|\(ctx.clip.colorAdjustments.hashValue)"
        guard key != sourceKey || source == nil else { return }
        sourceKey = key
        quickCache.removeAll()
        loadTask?.cancel()
        let clip = ctx.clip, local = ctx.local
        loadTask = Task { [weak self] in
            do {
                let image = try await MockupStudioRenderer.loadSource(
                    clip: clip, local: local, maxSide: MockupStudioRenderer.previewLongSide
                )
                guard !Task.isCancelled, let self else { return }
                self.source = image
                self.sourceSize = image.extent.size
                self.hasSource = true
                self.scheduleRender()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.message = "Không tải được khung hình: \(error.localizedDescription)"
            }
        }
    }

    func scheduleRender() {
        guard let source, let ctx = context else { return }
        renderTask?.cancel()
        var layers = clipLayers
        if let ghostAssetID, let asset = MockupStudioCatalog.asset(ghostAssetID) {
            layers.removeAll { MockupStudioCatalog.asset($0.assetID)?.kind == asset.kind && asset.kind != .overlay }
            layers.append(Self.makeLayer(asset, start: ctx.start, duration: ctx.clip.renderedDuration))
        }
        let second = ctx.second
        isRendering = true
        renderTask = Task { [weak self] in
            // Coalesce bursts (sliders, gestures) into one render.
            try? await Task.sleep(nanoseconds: 14_000_000)
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                MockupStudioRenderer.renderPreview(source: source, layers: layers, second: second)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.rendered = image
            self.isRendering = false
        }
    }

    /// Small render of one asset on the current photo (library preview).
    func quickPreview(_ asset: MockupStudioAsset) async -> UIImage? {
        guard let source, let ctx = context else { return nil }
        let key = "\(asset.id)|\(sourceKey)"
        if let hit = quickCache[key] { return hit }
        let layer = Self.makeLayer(asset, start: ctx.start, duration: ctx.clip.renderedDuration)
        let second = ctx.second
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let scale = 560 / max(source.extent.width, source.extent.height)
            let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return MockupStudioRenderer.renderPreview(source: small, layers: [layer], second: second)
        }.value
        if let image {
            if quickCache.count > 40 { quickCache.removeAll() }
            quickCache[key] = image
        }
        return image
    }

    // MARK: Export

    func export(_ format: MockupStudioRenderer.ExportFormat) {
        guard let ctx = context, !isExporting else { return }
        let layers = clipLayers
        isExporting = true
        exportedURL = nil
        message = "Đang xuất ảnh \(format.rawValue)…"
        let clip = ctx.clip, local = ctx.local, second = ctx.second
        Task { [weak self] in
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try await MockupStudioRenderer.export(
                        clip: clip, local: local, layers: layers, second: second, format: format
                    )
                }.value
                self?.exportedURL = url
                self?.message = "Đã xuất \(url.lastPathComponent)"
            } catch {
                self?.message = "Xuất ảnh thất bại: \(error.localizedDescription)"
            }
            self?.isExporting = false
        }
    }

    func saveExportToPhotos() {
        guard let url = exportedURL else { return }
        Task { [weak self] in
            do {
                try await MockupStudioRenderer.saveToPhotos(url)
                self?.message = "Đã lưu vào thư viện Ảnh."
            } catch {
                self?.message = error.localizedDescription
            }
        }
    }
}
