import Foundation

extension MusicVideoStudio {
    enum AspectRatio: String, Codable, CaseIterable, Identifiable {
        case portrait9x16 = "9:16"
        case landscape16x9 = "16:9"
        case square = "1:1"
        case portrait4x5 = "4:5"
        case portrait3x4 = "3:4"

        var id: String { rawValue }

        /// width / height
        var ratio: Double {
            switch self {
            case .portrait9x16: return 9.0 / 16.0
            case .landscape16x9: return 16.0 / 9.0
            case .square: return 1
            case .portrait4x5: return 4.0 / 5.0
            case .portrait3x4: return 3.0 / 4.0
            }
        }

        /// Output size whose SHORT side is `shortSide` pixels (even numbers).
        func pixelSize(shortSide: Int) -> (width: Int, height: Int) {
            let short = max(2, shortSide)
            func even(_ v: Double) -> Int { max(2, Int((v / 2).rounded()) * 2) }
            return ratio >= 1
                ? (even(Double(short) * ratio), even(Double(short)))
                : (even(Double(short)), even(Double(short) / ratio))
        }
    }

    /// The whole document. A plain value type so undo/redo is a snapshot swap
    /// and saving is a JSON encode.
    struct VideoProject: Codable, Hashable, Identifiable {
        static let currentSchema = 1
        static let minimumDuration = ProjectTime(seconds: 3)
        static let maxLayers = 400

        var schema = VideoProject.currentSchema
        var id = UUID()
        var name = "Music Video"
        var createdAt = Date()
        var modifiedAt = Date()
        var aspect = AspectRatio.portrait9x16
        var fps = 30
        var photos: [PhotoLayer] = []
        var texts: [TextLayer] = []
        var audios: [AudioLayer] = []
        var vinyls: [VinylLayer] = []
        var lyrics: [LyricsLayer] = []
        var visualizers: [VisualizerLayer] = []
        var effects: [EffectLayer] = []

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? Self.currentSchema
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Music Video"
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? Date()
            aspect = try c.decodeIfPresent(AspectRatio.self, forKey: .aspect) ?? .portrait9x16
            let rawFPS = try c.decodeIfPresent(Int.self, forKey: .fps) ?? 30
            fps = ProjectTime.supportedFrameRates.contains(rawFPS) ? rawFPS : 30
            photos = try c.decodeIfPresent([PhotoLayer].self, forKey: .photos) ?? []
            texts = try c.decodeIfPresent([TextLayer].self, forKey: .texts) ?? []
            audios = try c.decodeIfPresent([AudioLayer].self, forKey: .audios) ?? []
            vinyls = try c.decodeIfPresent([VinylLayer].self, forKey: .vinyls) ?? []
            lyrics = try c.decodeIfPresent([LyricsLayer].self, forKey: .lyrics) ?? []
            visualizers = try c.decodeIfPresent([VisualizerLayer].self, forKey: .visualizers) ?? []
            effects = try c.decodeIfPresent([EffectLayer].self, forKey: .effects) ?? []
        }

        /// End of the last layer, never shorter than the minimum.
        var duration: ProjectTime {
            let end = allCores.map(\.end).max() ?? .zero
            return max(Self.minimumDuration, end)
        }

        var layerCount: Int { photos.count + texts.count + audios.count + vinyls.count + lyrics.count + visualizers.count + effects.count }

        var allCores: [LayerCore] {
            photos.map(\.core) + texts.map(\.core) + audios.map(\.core) + vinyls.map(\.core) + lyrics.map(\.core) + visualizers.map(\.core) + effects.map(\.core)
        }

        func core(for id: UUID) -> LayerCore? { allCores.first { $0.id == id } }

        /// Applies `change` to the core of the layer `id`. Returns false when missing.
        @discardableResult
        mutating func updateCore(_ id: UUID, _ change: (inout LayerCore) -> Void) -> Bool {
            Self.update(&photos, id, change) || Self.update(&texts, id, change) ||
                Self.update(&audios, id, change) || Self.update(&vinyls, id, change) || Self.update(&lyrics, id, change) || Self.update(&visualizers, id, change) || Self.update(&effects, id, change)
        }

        private static func update<L: StudioLayer>(_ layers: inout [L], _ id: UUID,
                                                   _ change: (inout LayerCore) -> Void) -> Bool {
            guard let i = layers.firstIndex(where: { $0.core.id == id }) else { return false }
            change(&layers[i].core)
            layers[i].core.transform = layers[i].core.transform.sanitized
            return true
        }

        mutating func removeLayers(_ ids: Set<UUID>) {
            photos.removeAll { ids.contains($0.core.id) }
            texts.removeAll { ids.contains($0.core.id) }
            audios.removeAll { ids.contains($0.core.id) }
            vinyls.removeAll { ids.contains($0.core.id) }
            lyrics.removeAll { ids.contains($0.core.id) }
            visualizers.removeAll { ids.contains($0.core.id) }
            effects.removeAll { ids.contains($0.core.id) }
        }

        /// Highest z-index in use + 1 (new layers go on top of their track's base).
        func nextZIndex(for track: TrackKind) -> Int {
            let used = allCores.filter { $0.track == track }.map(\.zIndex)
            return (used.max() ?? (track.baseZIndex - 1)) + 1
        }
    }
}
