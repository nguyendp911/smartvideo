import Foundation

extension MusicVideoStudio {
    /// An animated record. The picture is a pure function of time
    /// (`VinylMath.angle`), so pausing, seeking and exporting can never desync.
    struct VinylLayer: StudioLayer {
        var core: LayerCore
        /// Media file (a project photo) shown on the label, nil = plain label colour.
        var coverFile: String?
        var rpm = 33.33
        /// Diameter as a fraction of the SHORT side of the canvas.
        var size = 0.55
        /// Label diameter as a fraction of the record.
        var labelScale = 0.38
        var shadow = 0.5
        var glow = 0.3
        var glowColorHex = "#4DD0E1"
        var reflection = 0.45
        var labelColorHex = "#C0392B"
        /// Seconds already spun when this layer starts (set by Split so both halves stay continuous).
        var phase = 0.0

        static let rpmRange = 0.0...120.0
        static let sizeRange = 0.15...1.4

        init(core: LayerCore, coverFile: String? = nil) {
            self.core = core
            self.coverFile = coverFile
        }

        private enum CodingKeys: String, CodingKey {
            case core, coverFile, rpm, size, labelScale, shadow, glow, glowColorHex, reflection, labelColorHex, phase
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            core = try c.decode(LayerCore.self, forKey: .core)
            coverFile = try c.decodeIfPresent(String.self, forKey: .coverFile)
            rpm = try c.decodeIfPresent(Double.self, forKey: .rpm) ?? 33.33
            size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0.55
            labelScale = try c.decodeIfPresent(Double.self, forKey: .labelScale) ?? 0.38
            shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? 0.5
            glow = try c.decodeIfPresent(Double.self, forKey: .glow) ?? 0.3
            glowColorHex = try c.decodeIfPresent(String.self, forKey: .glowColorHex) ?? "#4DD0E1"
            reflection = try c.decodeIfPresent(Double.self, forKey: .reflection) ?? 0.45
            labelColorHex = try c.decodeIfPresent(String.self, forKey: .labelColorHex) ?? "#C0392B"
            phase = try c.decodeIfPresent(Double.self, forKey: .phase) ?? 0
        }
    }
}
