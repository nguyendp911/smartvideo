import Foundation
import UniformTypeIdentifiers

/// The file type selection for the single system Files importer.
enum EditorDocumentKind: String, Identifiable {
    case music, musicRegion, voice, subtitles, soundEffect
    case textFillImage, textFillVideo

    var id: String { rawValue }

    var allowedTypes: [UTType] {
        switch self {
        case .music, .musicRegion, .voice, .soundEffect:
            return [
                .audio,
                UTType(filenameExtension: "mp3") ?? .audio,
                UTType(filenameExtension: "m4a") ?? .audio,
                UTType(filenameExtension: "wav") ?? .audio
            ]
        case .textFillImage:
            return [.image]
        case .textFillVideo:
            return [.movie, .video]
        case .subtitles:
            return [
                .plainText,
                UTType(filenameExtension: "srt") ?? .plainText
            ]
        }
    }
}
