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

        var aspectRatio: Double { Double(max(1, pixelWidth)) / Double(max(1, pixelHeight)) }
    }
}
