import Foundation

extension MusicVideoStudio {
    enum VinylStyle: String, Codable, CaseIterable, Identifiable {
        case classic = "Cổ điển"
        case colored = "Đĩa màu"
        case splatter = "Vẩy màu"
        case picture = "Đĩa ảnh"
        case neon = "Neon"
        case gold = "Vàng"
        var id: String { rawValue }
    }

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
        var style = VinylStyle.classic
        /// Main colour of the coloured / splatter / neon discs.
        var discColorHex = "#7E57C2"
        /// Second colour (splatter blobs).
        var accentColorHex = "#FFD54F"
        /// A tonearm that lands on the record, tracks inward and lifts at the end.
        var tonearm = false
        /// Seconds the record takes to reach full speed at the start (0 = instantly).
        var spinUp = 0.0
        /// A turntable plinth behind the record.
        var turntable = false
        /// The audio clip whose beats and spectrum drive the swell and the ring.
        var audioLayerID: UUID?
        /// How much the record swells on a beat (0 = not at all).
        var beatPulse = 0.0
        /// Equalizer bars around the record.
        var equalizerRing = false
        var ringColorHex = "#4DD0E1"

        static let rpmRange = 0.0...120.0
        static let sizeRange = 0.15...1.4
        static let spinUpRange = 0.0...4.0

        init(core: LayerCore, coverFile: String? = nil) {
            self.core = core
            self.coverFile = coverFile
        }

        private enum CodingKeys: String, CodingKey {
            case core, coverFile, rpm, size, labelScale, shadow, glow, glowColorHex, reflection, labelColorHex, phase
            case style, discColorHex, accentColorHex, tonearm, spinUp, turntable, audioLayerID, beatPulse, equalizerRing, ringColorHex
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
            style = try c.decodeIfPresent(VinylStyle.self, forKey: .style) ?? .classic
            discColorHex = try c.decodeIfPresent(String.self, forKey: .discColorHex) ?? "#7E57C2"
            accentColorHex = try c.decodeIfPresent(String.self, forKey: .accentColorHex) ?? "#FFD54F"
            tonearm = try c.decodeIfPresent(Bool.self, forKey: .tonearm) ?? false
            spinUp = try c.decodeIfPresent(Double.self, forKey: .spinUp) ?? 0
            turntable = try c.decodeIfPresent(Bool.self, forKey: .turntable) ?? false
            audioLayerID = try c.decodeIfPresent(UUID.self, forKey: .audioLayerID)
            beatPulse = try c.decodeIfPresent(Double.self, forKey: .beatPulse) ?? 0
            equalizerRing = try c.decodeIfPresent(Bool.self, forKey: .equalizerRing) ?? false
            ringColorHex = try c.decodeIfPresent(String.self, forKey: .ringColorHex) ?? "#4DD0E1"
        }
    }
}
