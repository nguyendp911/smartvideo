import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Portable JSON backup for user-created photo looks.
/// Import is validated and clipped before it enters UserDefaults.
struct PhotoPresetTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    var presets: [PhotoPreset]

    init(presets: [PhotoPreset]) {
        self.presets = presets
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              data.count <= 256_000 else {
            throw NSError(
                domain: "ViePNPhotoPresets", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Tệp preset JSON không hợp lệ hoặc lớn hơn 256 KB."]
            )
        }
        let decoded = try JSONDecoder().decode([PhotoPreset].self, from: data)
        presets = Self.sanitized(decoded)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(presets)
        return FileWrapper(regularFileWithContents: data)
    }

    static func sanitized(_ imported: [PhotoPreset]) -> [PhotoPreset] {
        func limited(_ value: Double, _ lower: Double, _ upper: Double,
                     fallback: Double = 0) -> Double {
            guard value.isFinite else { return fallback }
            return min(upper, max(lower, value))
        }
        var result: [PhotoPreset] = []
        for original in imported.prefix(40) {
            var item = original
            let name = original.name.trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            item.id = "custom-" + UUID().uuidString
            item.name = String(name.prefix(42))
            item.exposureEV = limited(item.exposureEV, -0.65, 0.8)
            item.contrast = limited(item.contrast, 0.75, 1.3, fallback: 1)
            item.saturation = limited(item.saturation, 0.7, 1.4, fallback: 1)
            item.warmth = limited(item.warmth, -0.35, 0.35)
            item.noiseReduction = limited(item.noiseReduction, 0, 0.045)
            item.sharpness = limited(item.sharpness, 0, 0.75)
            item.highlightSoftness = limited(item.highlightSoftness, 0, 0.35)
            item.shadowLift = limited(item.shadowLift, -0.2, 0.35)
            item.vignette = limited(item.vignette, 0, 0.3)
            item.vibrance = limited(item.vibrance, -0.3, 0.3)
            result.append(item)
        }
        return result
    }
}
