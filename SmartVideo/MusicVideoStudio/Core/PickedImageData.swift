import SwiftUI
import UniformTypeIdentifiers

extension MusicVideoStudio {
    /// Raw image bytes from the photo picker, for formats `Data` alone does not cover.
    struct PickedImageData: Transferable {
        let data: Data

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: .image) { PickedImageData(data: $0) }
        }
    }
}
