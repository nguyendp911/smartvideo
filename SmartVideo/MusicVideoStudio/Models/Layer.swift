import Foundation

extension MusicVideoStudio {
    /// Every kind of track the studio will have. A track only appears in the
    /// editor once its feature phase is implemented (`isAvailable`).
    enum TrackKind: String, Codable, CaseIterable, Identifiable {
        case photo, audio, lyrics, vinyl, visualizer, text, effects

        var id: String { rawValue }

        var title: String {
            switch self {
            case .photo: return "Ảnh"
            case .audio: return "Nhạc"
            case .lyrics: return "Lời"
            case .vinyl: return "Đĩa than"
            case .visualizer: return "Visualizer"
            case .text: return "Chữ"
            case .effects: return "Hiệu ứng"
            }
        }

        var symbol: String {
            switch self {
            case .photo: return "photo.on.rectangle"
            case .audio: return "waveform"
            case .lyrics: return "music.mic"
            case .vinyl: return "opticaldisc"
            case .visualizer: return "chart.bar.fill"
            case .text: return "textformat"
            case .effects: return "sparkles"
            }
        }

        /// Tracks that exist in the editor today.
        var isAvailable: Bool { true }

        /// Always shown, even when empty (so there is somewhere to drop things).
        var alwaysVisible: Bool { self == .photo || self == .audio || self == .text }

        /// Layers of higher tracks draw over lower ones by default.
        var baseZIndex: Int {
            switch self {
            case .photo: return 0
            case .vinyl: return 1_000
            case .visualizer: return 2_000
            case .effects: return 3_000
            case .lyrics: return 4_000
            case .text: return 5_000
            case .audio: return 0
            }
        }
    }

    /// Position (normalised, origin top-left, centre of the layer), uniform
    /// scale, rotation in degrees and opacity: shared by every visual layer.
    struct LayerTransform: Codable, Hashable {
        var x = 0.5
        var y = 0.5
        var scale = 1.0
        var rotation = 0.0
        var opacity = 1.0

        static let identity = LayerTransform()

        static let scaleRange = 0.1...4.0
        static let positionRange = -0.5...1.5

        /// Everything within valid ranges and finite.
        var sanitized: LayerTransform {
            func fin(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? v : fallback }
            return LayerTransform(
                x: min(Self.positionRange.upperBound, max(Self.positionRange.lowerBound, fin(x, 0.5))),
                y: min(Self.positionRange.upperBound, max(Self.positionRange.lowerBound, fin(y, 0.5))),
                scale: min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, fin(scale, 1))),
                rotation: fin(rotation, 0).truncatingRemainder(dividingBy: 360),
                opacity: min(1, max(0, fin(opacity, 1)))
            )
        }
    }

    /// What every layer has: identity, placement in time and space, and state.
    struct LayerCore: Codable, Hashable, Identifiable {
        var id = UUID()
        var name: String
        var track: TrackKind
        var start: ProjectTime
        var duration: ProjectTime
        var transform = LayerTransform()
        var isVisible = true
        var isLocked = false
        var zIndex: Int

        var range: TimeRange { TimeRange(start: start, duration: duration) }
        var end: ProjectTime { start + duration }

        static let minimumDuration = ProjectTime(seconds: 0.1)

        func isActive(at time: ProjectTime) -> Bool { isVisible && range.contains(time) }
    }

    protocol StudioLayer: Identifiable, Codable, Hashable {
        var core: LayerCore { get set }
    }
}

extension MusicVideoStudio.StudioLayer {
    var id: UUID { core.id }
}
