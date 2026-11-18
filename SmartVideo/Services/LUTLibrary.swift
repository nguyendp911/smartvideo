import Foundation
import CoreImage

/// User-imported `.cube` LUTs stored in Documents/LUTs and applied through
/// Core Image. Cubes are parsed once and cached, so per-frame grading in the
/// preview and in export stays cheap.
enum LUTLibrary {
    static let maxLibraryCount = 40

    private final class Box {
        let lut: CubeLUT
        let data: Data
        init(_ lut: CubeLUT) {
            self.lut = lut
            self.data = lut.rgba.withUnsafeBytes { Data($0) }
        }
    }
    private static let cache = NSCache<NSString, Box>()

    static var directory: URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("LUTs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// File names (with extension) sorted alphabetically.
    static func list() -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "cube" }
            .map(\.lastPathComponent)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Validates and copies a user-picked file. Returns the stored name.
    @discardableResult
    static func importLUT(from url: URL) throws -> String {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        _ = try CubeLUT.parse(data)           // reject bad files before storing
        guard list().count < maxLibraryCount else {
            throw SmartVideoError.invalidMedia(
                "Thư viện LUT đã đủ \(maxLibraryCount) tệp; hãy xóa bớt."
            )
        }
        var base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if base.isEmpty { base = "LUT" }
        var name = base + ".cube"
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(base) \(counter).cube"
            counter += 1
        }
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent((name as NSString).lastPathComponent)
        )
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(
            atPath: directory.appendingPathComponent((name as NSString).lastPathComponent).path
        )
    }

    private static func entry(named name: String) -> Box? {
        // Never let a project file name escape the LUT folder.
        let safe = (name as NSString).lastPathComponent
        if let hit = cache.object(forKey: safe as NSString) { return hit }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(safe)),
              let lut = try? CubeLUT.parse(data) else { return nil }
        let created = Box(lut)
        cache.setObject(created, forKey: safe as NSString)
        return created
    }

    /// Missing or invalid LUT files leave the image untouched.
    static func apply(_ image: CIImage, name: String, intensity: Double) -> CIImage {
        let amount = intensity.isFinite ? min(1, max(0, intensity)) : 1
        guard amount > 0.001, let box = entry(named: name) else { return image }
        let graded = image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": box.lut.size,
            "inputCubeData": box.data,
            // Creative LUTs are authored for display-referred (sRGB/Rec.709) values.
            "inputColorSpace": CGColorSpace(name: CGColorSpace.sRGB) as Any
        ]).cropped(to: image.extent)
        guard amount < 0.999 else { return graded }
        return image.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: graded,
            kCIInputTimeKey: amount
        ]).cropped(to: image.extent)
    }
}
