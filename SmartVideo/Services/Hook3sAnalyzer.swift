import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// Finds three-second opening candidates using sampled motion,
/// contrast and visible faces on-device. This is a heuristic ranking,
/// not a guarantee of virality or Gemini semantic understanding.
struct Hook3sSuggestion: Identifiable, Equatable {
    let id = UUID()
    let start: Double   // Seconds relative to original selected clip's source trim.
    let duration: Double
    let score: Double
    let reason: String
}

enum Hook3sAnalyzer {
    static func suggest(from clip: TimelineClip) async throws -> [Hook3sSuggestion] {
        guard clip.kind == .video, clip.duration >= 3 else {
            throw SmartVideoError.invalidMedia(
                "Hook 3 giây cần clip video gốc dài tối thiểu 3 giây.")
        }
        let asset = AVURLAsset(url: clip.fileURL)
        let realLength = try await asset.load(.duration).seconds
        let safeStart = max(0, min(clip.startTime, realLength))
        let visible = min(clip.duration, max(0, realLength - safeStart))
        guard visible >= 3.0 else {
            throw SmartVideoError.invalidMedia(
                "Phần video đã chọn còn dưới 3 giây.")
        }
        let maxStart = visible - 3.0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        generator.requestedTimeToleranceBefore =
            CMTime(seconds: 0.12, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter =
            CMTime(seconds: 0.12, preferredTimescale: 600)
        let count = max(1, min(16, Int(ceil(maxStart / 3.0)) + 1))
        var ranked: [Hook3sSuggestion] = []

        for index in 0..<count {
            try Task.checkCancellation()
            let begin = count == 1 ? 0 :
                maxStart * Double(index) / Double(count - 1)
            var previous: [Double]?
            var motion = 0.0
            var clarity = 0.0
            var face = 0.0
            var frames = 0
            for offset in [0.35, 1.35, 2.55] {
                let time = CMTime(
                    seconds: safeStart + begin + offset,
                    preferredTimescale: 600)
                guard let frame = try? await generator.image(at: time).image
                else { continue }
                let luma = luminanceGrid(frame)
                guard !luma.isEmpty else { continue }
                frames += 1
                let mean = luma.reduce(0, +) / Double(luma.count)
                let spread = sqrt(luma.reduce(0) {
                    $0 + ($1 - mean) * ($1 - mean)
                } / Double(luma.count))
                clarity += min(1, spread * 3.7)
                if let previous {
                    motion += min(1, zip(luma, previous).reduce(0) {
                        $0 + abs($1.0 - $1.1)
                    } / Double(luma.count) * 4.0)
                }
                let faces = VNDetectFaceRectanglesRequest()
                let handler = VNImageRequestHandler(
                    cgImage: frame, options: [:])
                if (try? handler.perform([faces])) != nil {
                    face += min(1, Double(faces.results?.count ?? 0) * 0.6)
                }
                previous = luma
            }
            guard frames >= 2 else { continue }
            let movement = motion / Double(frames - 1)
            let detail = clarity / Double(frames)
            let people = face / Double(frames)
            // Face/motion and visible detail make a strong starting point;
            // the user reviews it before inserting the suggested hook.
            let score = 0.45 * movement + 0.32 * people + 0.23 * detail
            let reason = people >= 0.35 ? "Có gương mặt nổi bật" :
                         movement >= 0.30 ? "Chuyển động / đổi cảnh" :
                         "Hình ảnh rõ, tương phản tốt"
            ranked.append(Hook3sSuggestion(
                start: begin, duration: 3, score: score, reason: reason))
        }
        guard !ranked.isEmpty else {
            throw SmartVideoError.invalidMedia(
                "Không trích xuất được khung hình để tìm Hook.")
        }
        var chosen: [Hook3sSuggestion] = []
        for candidate in ranked.sorted(by: { $0.score > $1.score }) {
            if chosen.allSatisfy({
                abs($0.start - candidate.start) >= 2.7
            }) {
                chosen.append(candidate)
            }
            if chosen.count >= 3 { break }
        }
        return chosen
    }

    private static func luminanceGrid(_ frame: CGImage) -> [Double] {
        let side = 12
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * bytesPerRow)
        let valid = pixels.withUnsafeMutableBytes { data in
            guard let ctx = CGContext(
                data: data.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(frame, in: CGRect(
                x: 0, y: 0, width: side, height: side))
            return true
        }
        guard valid else { return [] }
        var lumas: [Double] = []
        lumas.reserveCapacity(side * side)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[offset])
            let green = Double(pixels[offset + 1])
            let blue = Double(pixels[offset + 2])
            let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
            lumas.append(luminance / 255.0)
        }
        return lumas
    }
}
