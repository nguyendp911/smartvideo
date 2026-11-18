import Foundation

extension MusicVideoStudio {
    enum VisualizerStyle: String, Codable, CaseIterable, Identifiable {
        case bars = "Cột"
        case mirror = "Cột đối xứng"
        case wave = "Sóng"
        case area = "Vùng phổ"
        case dots = "Chấm"
        case circle = "Vòng tia"
        case ring = "Vòng sóng"
        case pulse = "Nhịp đập"
        case particles = "Hạt"
        case peakBars = "Cột có đỉnh rơi"
        case sineWaves = "Sóng sin"
        case flower = "Hoa"
        case bubbles = "Bong bóng"
        case starfield = "Sao bay"
        case ledMatrix = "Ma trận LED"
        var id: String { rawValue }
    }

    /// A two-colour look in one tap.
    struct VisualizerPalette: Identifiable, Equatable {
        let name: String
        let first: String
        let second: String
        var id: String { name }

        static let all: [VisualizerPalette] = [
            VisualizerPalette(name: "Neon", first: "#4DD0E1", second: "#E040FB"),
            VisualizerPalette(name: "Hoàng hôn", first: "#FF9800", second: "#E91E63"),
            VisualizerPalette(name: "Đại dương", first: "#00E5FF", second: "#2979FF"),
            VisualizerPalette(name: "Lửa", first: "#FFEB3B", second: "#F44336"),
            VisualizerPalette(name: "Matcha", first: "#B2FF59", second: "#00BFA5"),
            VisualizerPalette(name: "Tím mộng mơ", first: "#7C4DFF", second: "#FF4081"),
            VisualizerPalette(name: "Trắng bạc", first: "#FFFFFF", second: "#9E9E9E"),
        ]
    }

    /// An audio visualizer. Its picture is a pure function of (spectrum, clock time):
    /// the spectrum is analysed ONCE and offline, so preview, seek and export agree.
    struct VisualizerLayer: StudioLayer {
        var core: LayerCore
        /// The audio clip whose spectrum is drawn. nil = silent (idle shape).
        var audioLayerID: UUID?
        var style = VisualizerStyle.bars
        var colorHex = "#4DD0E1"
        var secondColorHex = "#E040FB"
        var barCount = 48
        /// Bar / dot / line thickness as a fraction of its slot.
        var thickness = 0.6
        var rounded = true
        /// Gain applied to the analysed level.
        var sensitivity = 1.2
        /// Fall-off per frame, 0 = jumpy ... 0.95 = very smooth.
        var smoothing = 0.7
        /// Size of the drawing area as fractions of the canvas.
        var width = 0.8
        var height = 0.25
        var glow = 0.4
        /// How much the whole shape swells on a beat.
        var beatPulse = 0.5

        static let barRange = 8...128
        static let thicknessRange = 0.1...1.0
        static let sensitivityRange = 0.3...3.0
        static let smoothingRange = 0.0...0.95
        static let widthRange = 0.2...1.0
        static let heightRange = 0.05...0.8

        init(core: LayerCore, audioLayerID: UUID?) {
            self.core = core
            self.audioLayerID = audioLayerID
        }

        private enum CodingKeys: String, CodingKey {
            case core, audioLayerID, style, colorHex, secondColorHex, barCount, thickness, rounded
            case sensitivity, smoothing, width, height, glow, beatPulse
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            core = try c.decode(LayerCore.self, forKey: .core)
            audioLayerID = try c.decodeIfPresent(UUID.self, forKey: .audioLayerID)
            style = try c.decodeIfPresent(VisualizerStyle.self, forKey: .style) ?? .bars
            colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#4DD0E1"
            secondColorHex = try c.decodeIfPresent(String.self, forKey: .secondColorHex) ?? "#E040FB"
            let bars = try c.decodeIfPresent(Int.self, forKey: .barCount) ?? 48
            barCount = min(Self.barRange.upperBound, max(Self.barRange.lowerBound, bars))
            thickness = try c.decodeIfPresent(Double.self, forKey: .thickness) ?? 0.6
            rounded = try c.decodeIfPresent(Bool.self, forKey: .rounded) ?? true
            sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1.2
            smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0.7
            width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0.8
            height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0.25
            glow = try c.decodeIfPresent(Double.self, forKey: .glow) ?? 0.4
            beatPulse = try c.decodeIfPresent(Double.self, forKey: .beatPulse) ?? 0.5
        }
    }
}
