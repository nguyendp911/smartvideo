import Foundation
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

extension MusicVideoStudio {
    struct ProjectSummary: Identifiable, Hashable {
        let id: UUID
        let name: String
        let modifiedAt: Date
        let layerCount: Int
    }

    enum ProjectError: LocalizedError {
        case invalidImage
        case writeFailed
        case notAudio

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Tệp không phải ảnh hợp lệ."
            case .writeFailed: return "Không ghi được tệp vào dự án."
            case .notAudio: return "Tệp không có âm thanh đọc được."
            }
        }
    }

    /// Projects live in `Documents/MusicVideoProjects/<id>/` as `project.json`
    /// plus a `media/` folder holding the ORIGINAL bytes of every imported
    /// photo, so a project never depends on the Photos library.
    final class ProjectManager {
        let root: URL

        init(root: URL? = nil) {
            if let root {
                self.root = root
            } else {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                self.root = docs.appendingPathComponent("MusicVideoProjects", isDirectory: true)
            }
            try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        }

        func directory(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
        func mediaDirectory(for id: UUID) -> URL { directory(for: id).appendingPathComponent("media", isDirectory: true) }
        private func projectFile(for id: UUID) -> URL { directory(for: id).appendingPathComponent("project.json") }

        /// A file name can never escape the project's media folder.
        func mediaURL(projectID: UUID, file: String) -> URL {
            mediaDirectory(for: projectID).appendingPathComponent((file as NSString).lastPathComponent)
        }

        private var encoder: JSONEncoder {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            e.dateEncodingStrategy = .iso8601
            return e
        }

        private var decoder: JSONDecoder {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return d
        }

        func save(_ project: VideoProject) throws {
            try FileManager.default.createDirectory(at: mediaDirectory(for: project.id), withIntermediateDirectories: true)
            try encoder.encode(project).write(to: projectFile(for: project.id), options: .atomic)
        }

        func load(_ id: UUID) throws -> VideoProject {
            try decoder.decode(VideoProject.self, from: Data(contentsOf: projectFile(for: id)))
        }

        func list() -> [ProjectSummary] {
            let folders = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil)) ?? []
            return folders.compactMap { folder -> ProjectSummary? in
                guard let id = UUID(uuidString: folder.lastPathComponent),
                      let project = try? load(id) else { return nil }
                return ProjectSummary(id: id, name: project.name, modifiedAt: project.modifiedAt, layerCount: project.layerCount)
            }.sorted { $0.modifiedAt > $1.modifiedAt }
        }

        func latestProjectID() -> UUID? { list().first?.id }

        func delete(_ id: UUID) throws {
            try FileManager.default.removeItem(at: directory(for: id))
        }

        struct ImportedAudio: Equatable {
            var mediaFile: String
            var originalName: String
            var duration: Double
        }

        /// Copies an audio file (from the document picker) into the project and
        /// validates that it really contains audio.
        func storeAudio(from source: URL, projectID: UUID) async throws -> ImportedAudio {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let directory = mediaDirectory(for: projectID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased()
            let name = UUID().uuidString + "." + ext
            let destination = directory.appendingPathComponent(name)
            do { try FileManager.default.copyItem(at: source, to: destination) } catch { throw ProjectError.writeFailed }
            let asset = AVURLAsset(url: destination)
            guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
                  let seconds = try? await asset.load(.duration).seconds, seconds.isFinite, seconds > 0.05 else {
                try? FileManager.default.removeItem(at: destination)
                throw ProjectError.notAudio
            }
            return ImportedAudio(mediaFile: name, originalName: source.deletingPathExtension().lastPathComponent, duration: seconds)
        }

        /// Stores the original bytes (HEIC/PNG/JPEG) and reads the real pixel
        /// size, honouring EXIF orientation. Other formats become JPEG.
        func storeImage(data: Data, projectID: UUID) throws -> TimelineEngine.ImportedPhoto {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0,
                  let typeID = CGImageSourceGetType(source),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  var width = props[kCGImagePropertyPixelWidth] as? Int,
                  var height = props[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0 else { throw ProjectError.invalidImage }
            let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
            if orientation >= 5 { swap(&width, &height) }

            let type = UTType(typeID as String)
            var payload = data
            let ext: String
            if type?.conforms(to: .heic) == true || type?.conforms(to: .heif) == true {
                ext = "heic"
            } else if type?.conforms(to: .png) == true {
                ext = "png"
            } else if type?.conforms(to: .jpeg) == true {
                ext = "jpg"
            } else {
                guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let output = CFDataCreateMutable(nil, 0),
                      let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw ProjectError.invalidImage
                }
                CGImageDestinationAddImage(destination, image, [
                    kCGImageDestinationLossyCompressionQuality: 0.92,
                    kCGImagePropertyOrientation: orientation
                ] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw ProjectError.writeFailed }
                payload = output as Data
                ext = "jpg"
            }
            let directory = mediaDirectory(for: projectID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = UUID().uuidString + "." + ext
            do {
                try payload.write(to: directory.appendingPathComponent(name), options: .atomic)
            } catch {
                throw ProjectError.writeFailed
            }
            return TimelineEngine.ImportedPhoto(mediaFile: name, pixelWidth: width, pixelHeight: height)
        }
    }
}
