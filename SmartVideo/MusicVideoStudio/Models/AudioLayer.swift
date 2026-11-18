import Foundation

extension MusicVideoStudio {
    /// A music / voice clip. `core.start` and `core.duration` place it on the
    /// timeline; `sourceStart` is the trim point inside the FILE, so moving the
    /// clip never changes which part of the song plays.
    struct AudioLayer: StudioLayer {
        var core: LayerCore
        var mediaFile: String
        var originalName: String
        /// Length of the whole file in seconds.
        var sourceDuration: Double
        var sourceStart = 0.0
        var volume = 1.0
        var fadeIn = 0.0
        var fadeOut = 0.0
        /// Repeat the trimmed part until the clip ends.
        var loops = false

        static let volumeRange = 0.0...1.5
        static let fadeRange = 0.0...30.0

        /// Seconds of the file available from `sourceStart` to its end.
        var availableSource: Double { max(0, sourceDuration - sourceStart) }

        init(core: LayerCore, mediaFile: String, originalName: String, sourceDuration: Double,
             sourceStart: Double = 0, volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0, loops: Bool = false) {
            self.core = core
            self.mediaFile = mediaFile
            self.originalName = originalName
            self.sourceDuration = sourceDuration
            self.sourceStart = sourceStart
            self.volume = volume
            self.fadeIn = fadeIn
            self.fadeOut = fadeOut
            self.loops = loops
        }

        private enum CodingKeys: String, CodingKey {
            case core, mediaFile, originalName, sourceDuration, sourceStart, volume, fadeIn, fadeOut, loops
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            core = try c.decode(LayerCore.self, forKey: .core)
            mediaFile = try c.decode(String.self, forKey: .mediaFile)
            originalName = try c.decodeIfPresent(String.self, forKey: .originalName) ?? "Nhạc"
            sourceDuration = try c.decodeIfPresent(Double.self, forKey: .sourceDuration) ?? core.duration.seconds
            sourceStart = try c.decodeIfPresent(Double.self, forKey: .sourceStart) ?? 0
            volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
            fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0
            fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 0
            loops = try c.decodeIfPresent(Bool.self, forKey: .loops) ?? false
        }
    }
}
