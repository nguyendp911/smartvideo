import Foundation
import UIKit
import UniformTypeIdentifiers
import CoreTransferable

enum MediaStorage {
    static var mediaDirectory: URL {
        directory(named: "Media")
    }

    static var exportsDirectory: URL {
        directory(named: "Exports")
    }

    static var temporaryDirectory: URL {
        directory(named: "RenderTemp")
    }

    private static func directory(named name: String) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let result = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    static func storeImage(data: Data) throws -> URL {
        guard let image = UIImage(data: data) else {
            throw SmartVideoError.invalidMedia("Tệp ảnh không được hỗ trợ.")
        }
        // Flatten EXIF orientation so that photos display correctly in the encoder.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let painter = UIGraphicsImageRenderer(size: image.size, format: format)
        let jpeg = painter.jpegData(withCompressionQuality: 0.90) { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        let destination = mediaDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try jpeg.write(to: destination, options: .atomic)
        return destination
    }

    /// Preserve the alpha channel of logos, stickers and transparent PNGs.
    /// Unlike the JPEG flattening path used for timeline photographs, this
    /// path does NOT draw over an opaque background.
    static func storeOverlayImage(data: Data) throws -> URL {
        guard let image = UIImage(data: data) else {
            throw SmartVideoError.invalidMedia("Ảnh overlay không hợp lệ.")
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let output = UIGraphicsImageRenderer(size: image.size, format: format)
            .pngData { context in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        let target = mediaDirectory.appendingPathComponent(
            "Overlay-\(UUID().uuidString).png"
        )
        try output.write(to: target, options: .atomic)
        return target
    }

    static func copyToMedia(_ file: URL, fallbackExtension: String) throws -> URL {
        let suffix = file.pathExtension.isEmpty ? fallbackExtension : file.pathExtension
        let destination = mediaDirectory.appendingPathComponent(UUID().uuidString + "." + suffix)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    static func newExportURL() -> URL {
        exportsDirectory.appendingPathComponent("SmartVideo-\(UUID().uuidString.prefix(8)).mp4")
    }

    static func newTemporaryVideoURL() -> URL {
        temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
    }
}

/// Files provided by PhotosPicker are ephemeral; copy them during import.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let local = try MediaStorage.copyToMedia(received.file, fallbackExtension: "mov")
            return PickedMovie(url: local)
        }
    }
}
