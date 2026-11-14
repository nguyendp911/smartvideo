import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable

enum MediaStorage {
    static var mediaDirectory: URL {
        directory(named: "Media")
    }

    static var exportsDirectory: URL {
        directory(named: "Exports")
    }

    /// Dedicated local video downloads. Editing projects copy footage from
    /// here into Media, so deleting a vault entry never breaks saved edits.
    static var downloadsDirectory: URL {
        directory(named: "DownloadLibrary")
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
        // Preserve original full-resolution HEIC/JPEG/PNG bytes instead
        // of flattening every image into a re-encoded 90% quality JPEG.
        // Original metadata is retained in Media; export defaults to
        // stripping it unless the user opts to preserve it.
        guard let source = CGImageSourceCreateWithData(
            data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let typeID = CGImageSourceGetType(source) else {
            throw SmartVideoError.invalidMedia("Ảnh nhập không hợp lệ.")
        }
        let type = UTType(typeID as String)
        let suffix: String
        if type?.conforms(to: .heic) == true ||
           type?.conforms(to: .heif) == true {
            suffix = "heic"
        } else if type?.conforms(to: .png) == true {
            suffix = "png"
        } else if type?.conforms(to: .jpeg) == true {
            suffix = "jpg"
        } else {
            // Preserve support for PhotosPicker images such as TIFF by
            // normalizing only when the format is not natively supported.
            guard let input = UIImage(data: data),
                  let normalized = input.jpegData(
                    compressionQuality: 0.96) else {
                throw SmartVideoError.invalidMedia(
                    "Định dạng ảnh chưa được hỗ trợ.")
            }
            let destination = mediaDirectory.appendingPathComponent(
                UUID().uuidString + ".jpg")
            try normalized.write(to: destination, options: .atomic)
            return destination
        }
        let target = mediaDirectory.appendingPathComponent(
            UUID().uuidString + "." + suffix)
        try data.write(to: target, options: .atomic)
        return target
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
