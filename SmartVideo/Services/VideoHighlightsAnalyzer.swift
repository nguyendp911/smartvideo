import Foundation
import AVFoundation
import Vision
import CoreGraphics

/// Offline Vision suggestions; scans a bounded sample of video frames.
/// This is scene/visual saliency ranking, not language-level plot understanding.
enum VideoHighlightsAnalyzer {
    static func find(in url: URL,
                     sourceStart: Double,
                     sourceDuration: Double) async throws -> [VideoHighlight] {
        let asset = AVURLAsset(url: url)
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw SmartVideoError.invalidMedia("Tệp không có track video.")
        }
        let fullDuration = try await asset.load(.duration).seconds
        guard fullDuration.isFinite, fullDuration > 0 else {
            throw SmartVideoError.invalidMedia("Thời lượng video không hợp lệ.")
        }
        let begin = min(max(0, sourceStart), fullDuration)
        let length = min(max(0, sourceDuration), fullDuration - begin)
        guard length > 0.5 else {
            throw SmartVideoError.invalidMedia("Đoạn video quá ngắn để chọn highlight.")
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)

        let sampleCount = min(32, max(3, Int(ceil(length / 2.0))))
        let interval = length / Double(sampleCount)
        var previousThumbnail: [Double]?
        var samples: [(t: Double, score: Double, reason: String)] = []

        for index in 0..<sampleCount {
            try Task.checkCancellation()
            let relativeSecond = min(length - 0.05, (Double(index) + 0.5) * interval)
            let sourceTime = CMTime(seconds: begin + relativeSecond, preferredTimescale: 600)
            let frame: CGImage
            do {
                frame = try await generator.image(at: sourceTime).image
            } catch {
                continue
            }

            let thumbnail = gridLuminance(frame)
            let diff: Double
            if let previousThumbnail, previousThumbnail.count == thumbnail.count {
                diff = zip(previousThumbnail, thumbnail).reduce(0.0) {
                    $0 + abs($1.0 - $1.1)
                } / Double(thumbnail.count)
            } else {
                diff = 0
            }
            previousThumbnail = thumbnail

            let mean = thumbnail.reduce(0, +) / Double(max(1, thumbnail.count))
            let variance = thumbnail.reduce(0.0) {
                $0 + ($1 - mean) * ($1 - mean)
            } / Double(max(1, thumbnail.count))
            let contrast = min(1, sqrt(variance) * 3)

            let faceRequest = VNDetectFaceRectanglesRequest()
            let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cgImage: frame, options: [:])
            let faceScore: Double
            let saliencyScore: Double
            if (try? handler.perform([faceRequest, saliencyRequest])) != nil {
                faceScore = min(1, Double(faceRequest.results?.count ?? 0) * 0.45)
                let salient = saliencyRequest.results?.first?.salientObjects ?? []
                saliencyScore = min(1, Double(salient.count) * 0.28)
            } else {
                faceScore = 0
                saliencyScore = 0
            }

            let changeScore = min(1, diff * 3.5)
            let score = changeScore * 0.35 + faceScore * 0.25
                + saliencyScore * 0.25 + contrast * 0.15

            let reason = faceScore > 0.4 ? "Có khuôn mặt" :
                         changeScore > 0.35 ? "Thay đổi cảnh" :
                         saliencyScore > 0.25 ? "Chủ thể nổi bật" : "Hình ảnh tương phản"
            samples.append((t: relativeSecond, score: score, reason: reason))
        }

        guard !samples.isEmpty else {
            throw SmartVideoError.invalidMedia("Không trích xuất được hình để phân tích.")
        }

        let segmentLength = min(7, max(1.0, length / 5))
        let ranked = samples.sorted { $0.score > $1.score }
        var suggestions: [VideoHighlight] = []
        for sample in ranked {
            let maxStart = max(0, length - segmentLength)
            let start = min(max(0, sample.t - segmentLength * 0.5), maxStart)
            if suggestions.allSatisfy({ abs($0.start - start) > segmentLength * 0.85 }) {
                suggestions.append(VideoHighlight(
                    start: start, duration: segmentLength,
                    score: sample.score, reason: sample.reason
                ))
            }
            if suggestions.count == 3 { break }
        }
        return suggestions.sorted { $0.start < $1.start }
    }

    private static func gridLuminance(_ frame: CGImage) -> [Double] {
        let width = 8
        let height = 8
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 0, to: pixels.count, by: 4).map { index -> Double in
            let red = Double(pixels[index])
            let green = Double(pixels[index + 1])
            let blue = Double(pixels[index + 2])
            let weighted = (red * 0.2126) + (green * 0.7152) + (blue * 0.0722)
            return weighted / 255.0
        }
    }
}
