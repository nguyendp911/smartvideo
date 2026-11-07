import Foundation
import UniformTypeIdentifiers

/// The file type selection for the single system Files importer.
enum EditorDocumentKind: String, Identifiable {
    case music, voice, subtitles

    var id: String { rawValue }

    var allowedTypes: [UTType] {
        switch self {
        case .music, .voice:
            return [
                .audio,
                UTType(filenameExtension: "mp3") ?? .audio,
                UTType(filenameExtension: "m4a") ?? .audio,
                UTType(filenameExtension: "wav") ?? .audio
            ]
        case .subtitles:
            return [
                .plainText,
                UTType(filenameExtension: "srt") ?? .plainText
            ]
        }
    }
}
