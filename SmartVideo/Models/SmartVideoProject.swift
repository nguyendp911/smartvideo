import Foundation

/// A lightweight offline edit decision list (EDL). Assets remain in the
/// app's Documents/Media directory. No copy of the source media is made
/// when saving a project; project JSON references the existing files.
struct SmartVideoProject: Codable {
    var id: UUID
    var name: String
    var savedAt: Date
    var clips: [TimelineClip]
    var subtitles: [SubtitleCue]
    var transition: String
    var transitionSeconds: Double
    var canvas: String
    var contentMode: String
    var quality: String
    var musicFileName: String?
    var voiceFileName: String?
    var musicVolume: Float
    var musicStartSeconds: Double
    var musicHighlightDuration: Double
    var musicFadeIn: Double
    var musicFadeOut: Double
    var musicRepeat: Bool
    var keepOriginalAudio: Bool
    var voiceOffset: Double
    var voiceVolume: Float
    var vfxPresets: [String]
    var vfxIntensity: Double
    var vfxCoverage: String
    var vfxStart: Double
    var vfxEnd: Double
    var subtitleX: Double
    var subtitleY: Double
    var stripMetadata: Bool
    var addMetadata: Bool
    var metadata: ExportMetadata
}

struct ProjectListItem: Identifiable {
    let id: UUID
    let name: String
    let savedAt: Date
    let clipCount: Int
}

enum ProjectStore {
    static var folder: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }

    private static func file(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json")
    }

    static func save(_ project: SmartVideoProject) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: file(for: project.id), options: .atomic)
    }

    static func load(_ id: UUID) throws -> SmartVideoProject {
        let data = try Data(contentsOf: file(for: id))
        return try JSONDecoder().decode(SmartVideoProject.self, from: data)
    }

    static func list() -> [ProjectListItem] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let project = try? JSONDecoder().decode(
                    SmartVideoProject.self, from: data
                  ) else { return nil }
            return ProjectListItem(id: project.id, name: project.name,
                                   savedAt: project.savedAt,
                                   clipCount: project.clips.count)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    static func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: file(for: id))
    }

    static func clipInMedia(_ clip: TimelineClip) -> TimelineClip {
        var result = clip
        result.fileURL = MediaStorage.mediaDirectory
            .appendingPathComponent(clip.fileURL.lastPathComponent)
        return result
    }

    static func audioInMedia(_ name: String?) -> URL? {
        guard let name else { return nil }
        return MediaStorage.mediaDirectory.appendingPathComponent(name)
    }
}
