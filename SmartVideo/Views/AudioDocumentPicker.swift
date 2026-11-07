import SwiftUI
import UniformTypeIdentifiers
import UIKit

// A single UIKit picker avoids conflicts from attaching several SwiftUI
// fileImporter presentations to the same editor view.
enum EditorDocumentKind: String, Identifiable {
    case music, voice, subtitles
    var id: String { rawValue }

    var allowedTypes: [UTType] {
        switch self {
        case .music, .voice:
            return [.audio,
                    UTType(filenameExtension: "mp3") ?? .audio,
                    UTType(filenameExtension: "m4a") ?? .audio,
                    UTType(filenameExtension: "wav") ?? .audio]
        case .subtitles:
            return [.plainText, .text,
                    UTType(filenameExtension: "srt") ?? .plainText]
        }
    }
}

struct AudioDocumentPicker: UIViewControllerRepresentable {
    let kind: EditorDocumentKind
    let completion: (Result<URL, Error>?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: kind.allowedTypes, asCopy: true
        )
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<URL, Error>?) -> Void

        init(completion: @escaping (Result<URL, Error>?) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            if let selected = urls.first {
                completion(.success(selected))
            } else {
                completion(nil)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(nil)
        }
    }
}
