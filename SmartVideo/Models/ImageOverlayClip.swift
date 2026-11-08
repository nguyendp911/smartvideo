import Foundation
import CoreGraphics

/// Independent image overlay track: normalized coordinates are in the
/// video canvas, with (0,0) at top-left. Non-destructive project metadata.
struct ImageOverlayClip: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var fileURL: URL
    var start: Double = 0
    var duration: Double = 3

    var startX: Double = 0.5
    var startY: Double = 0.5
    var endX: Double = 0.5
    var endY: Double = 0.5

    /// Normalized width relative to canvas width, 0.1 through 1.
    var scale: Double = 0.45
    var opacity: Double = 1
    var rotationDegrees: Double = 0
    var chromaEnabled: Bool = false
    var chromaColor: ChromaKeyColor = .green
    var chromaTolerance: Double = 0.22
    var chromaSoftness: Double = 0.14
    var easing: OverlayEasing = .easeInOut
    /// Empty means the original two-point position animation is retained.
    var keyframes: [OverlayKeyframe] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private enum CodingKeys: String, CodingKey {
        case id, fileURL, start, duration, startX, startY, endX, endY,
             scale, opacity, rotationDegrees, chromaEnabled, chromaColor,
             chromaTolerance, chromaSoftness, easing, keyframes
    }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        id = try keyed.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileURL = try keyed.decode(URL.self, forKey: .fileURL)
        start = try keyed.decodeIfPresent(Double.self, forKey: .start) ?? 0
        duration = try keyed.decodeIfPresent(Double.self, forKey: .duration) ?? 3
        startX = try keyed.decodeIfPresent(Double.self, forKey: .startX) ?? 0.5
        startY = try keyed.decodeIfPresent(Double.self, forKey: .startY) ?? 0.5
        endX = try keyed.decodeIfPresent(Double.self, forKey: .endX) ?? 0.5
        endY = try keyed.decodeIfPresent(Double.self, forKey: .endY) ?? 0.5
        scale = try keyed.decodeIfPresent(Double.self, forKey: .scale) ?? 0.45
        opacity = try keyed.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        rotationDegrees = try keyed.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        chromaEnabled = try keyed.decodeIfPresent(Bool.self, forKey: .chromaEnabled) ?? false
        chromaColor = try keyed.decodeIfPresent(ChromaKeyColor.self,
                                               forKey: .chromaColor) ?? .green
        chromaTolerance = try keyed.decodeIfPresent(Double.self,
                                                     forKey: .chromaTolerance) ?? 0.22
        chromaSoftness = try keyed.decodeIfPresent(Double.self,
                                                   forKey: .chromaSoftness) ?? 0.14
        easing = try keyed.decodeIfPresent(OverlayEasing.self, forKey: .easing) ?? .easeInOut
        keyframes = try keyed.decodeIfPresent([OverlayKeyframe].self,
                                              forKey: .keyframes) ?? []
    }

    var end: Double { start + duration }
    var filename: String { fileURL.lastPathComponent }
}
