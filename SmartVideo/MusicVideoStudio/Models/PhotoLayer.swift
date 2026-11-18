import Foundation

extension MusicVideoStudio {
    enum PhotoFit: String, Codable, CaseIterable, Identifiable {
        /// Fills the canvas and crops the overflow.
        case fill = "Lấp đầy"
        /// Shows the whole photo with bars.
        case fit = "Vừa khung"
        var id: String { rawValue }
    }

    /// A photo on the photo track. `mediaFile` is a file name inside the
    /// project's media folder (the original bytes are kept).
    struct PhotoLayer: StudioLayer {
        var core: LayerCore
        var mediaFile: String
        var pixelWidth: Int
        var pixelHeight: Int
        var fit: PhotoFit = .fill
        var motion = PhotoMotion()
        var transitionIn = PhotoTransition()

        var aspectRatio: Double { Double(max(1, pixelWidth)) / Double(max(1, pixelHeight)) }

        init(core: LayerCore, mediaFile: String, pixelWidth: Int, pixelHeight: Int,
             fit: PhotoFit = .fill, motion: PhotoMotion = PhotoMotion(),
             transitionIn: PhotoTransition = PhotoTransition()) {
            self.core = core
            self.mediaFile = mediaFile
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.fit = fit
            self.motion = motion
            self.transitionIn = transitionIn
        }

        private enum CodingKeys: String, CodingKey {
            case core, mediaFile, pixelWidth, pixelHeight, fit, motion, transitionIn
        }

        /// Projects saved before Ken Burns / transitions existed still open.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            core = try c.decode(LayerCore.self, forKey: .core)
            mediaFile = try c.decode(String.self, forKey: .mediaFile)
            pixelWidth = try c.decodeIfPresent(Int.self, forKey: .pixelWidth) ?? 1
            pixelHeight = try c.decodeIfPresent(Int.self, forKey: .pixelHeight) ?? 1
            fit = try c.decodeIfPresent(PhotoFit.self, forKey: .fit) ?? .fill
            motion = try c.decodeIfPresent(PhotoMotion.self, forKey: .motion) ?? PhotoMotion()
            transitionIn = try c.decodeIfPresent(PhotoTransition.self, forKey: .transitionIn) ?? PhotoTransition()
        }
    }
}
