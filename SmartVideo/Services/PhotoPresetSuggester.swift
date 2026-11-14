import Foundation
import Vision
import ImageIO
import CoreGraphics

struct PhotoPresetSuggestion {
    let presetID: String
    let reason: String
}

/// Classification is entirely local and is only a recommendation.
/// Do not assume a scene type if Vision is unsure.
enum PhotoPresetSuggester {
    static func suggest(fileURL: URL) async throws -> PhotoPresetSuggestion? {
        try await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(
                fileURL as CFURL, nil),
                  let frame = CGImageSourceCreateThumbnailAtIndex(
                    source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 512,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ] as CFDictionary) else {
                throw SmartVideoError.invalidMedia(
                    "Không đọc được ảnh để AI gợi ý preset.")
            }
            let classification = VNClassifyImageRequest()
            let faces = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: frame, options: [:])
            try handler.perform([classification, faces])

            // Some scenes include people but the main subject can be a beach.
            // Prefer confident environment labels before face heuristics.
            let labels = (classification.results ?? [])
                .filter { $0.confidence >= 0.15 }
                .prefix(12)
            let categories: [(String, String, [String])] = [
                ("beach", "Có biển hoặc bãi cát", ["beach", "ocean", "seashore", "sea", "coast"]),
                ("sunset", "Cảnh mặt trời lặn", ["sunset", "dusk", "twilight"]),
                ("sunrise", "Cảnh bình minh", ["sunrise", "dawn"]),
                ("forest", "Rừng hoặc cây xanh", ["forest", "woodland", "jungle", "tree"]),
                ("blue_sky", "Bầu trời xanh", ["sky", "cloud", "blue sky"]),
                ("food_fresh", "Món ăn", ["food", "meal", "dish", "cuisine"]),
                ("dessert_soft", "Bánh ngọt", ["dessert", "cake", "pastry", "ice cream"]),
                ("cafe_brown", "Cà phê hoặc quán", ["coffee", "cafe", "espresso"]),
                ("city_night", "Đường phố / đô thị", ["city", "skyscraper", "street"]),
                ("natural_skin", "Chân dung", ["portrait", "selfie", "person", "face"])
            ]
            for result in labels {
                let label = result.identifier.lowercased()
                for (id, reason, keywords) in categories {
                    if keywords.contains(where: { label.contains($0) }) {
                        return PhotoPresetSuggestion(
                            presetID: id, reason: reason +
                                String(format: " (%.0f%%)", result.confidence * 100)
                        )
                    }
                }
            }
            if !(faces.results ?? []).isEmpty {
                return PhotoPresetSuggestion(
                    presetID: "natural_skin",
                    reason: "Phát hiện gương mặt trong ảnh"
                )
            }
            return nil
        }.value
    }
}
