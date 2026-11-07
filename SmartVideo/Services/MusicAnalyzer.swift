import Foundation
import AVFoundation
import CoreMedia

/// Lightweight offline audio scan. Suggests an entry point after quiet intro.
/// It is amplitude-based, not AI understanding of musical structure.
enum MusicAnalyzer {
    static func firstAudibleSecond(in url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SmartVideoError.invalidMedia("MP3 không có track nhạc.")
        }
        let duration = try await asset.load(.duration).seconds
        let scan = min(90, duration)
        guard scan > 1 else { return 0 }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: .zero, duration: CMTime(seconds: scan, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else {
            throw SmartVideoError.invalidMedia("Không thể phân tích âm thanh của tệp này.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw SmartVideoError.invalidMedia(
                reader.error?.localizedDescription ?? "Không thể đọc MP3."
            )
        }

        let windowCount = max(1, Int(ceil(scan)) + 1)
        var totalEnergy = [Double](repeating: 0, count: windowCount)
        var sampleCount = [Int](repeating: 0, count: windowCount)

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let data = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let byteLength = CMBlockBufferGetDataLength(data)
            guard byteLength >= 2 else { continue }
            var samples = [Int16](repeating: 0, count: byteLength / 2)
            let result = samples.withUnsafeMutableBytes { address in
                CMBlockBufferCopyDataBytes(
                    data, atOffset: 0, dataLength: samples.count * 2,
                    destination: address.baseAddress!
                )
            }
            guard result == kCMBlockBufferNoErr else { continue }

            let stamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
            guard stamp.isFinite else { continue }
            let index = max(0, min(windowCount - 1, Int(stamp)))
            for n in stride(from: 0, to: samples.count, by: 64) {
                totalEnergy[index] += Double(abs(Int(samples[n])))
                sampleCount[index] += 1
            }
        }
        if reader.status == .failed {
            throw SmartVideoError.invalidMedia(
                reader.error?.localizedDescription ?? "Không thể phân tích MP3."
            )
        }

        let levels = zip(totalEnergy, sampleCount).map { energy, count in
            count == 0 ? 0 : energy / Double(count)
        }
        let loudest = levels.max() ?? 0
        guard loudest > 0 else { return 0 }
        let threshold = max(130.0, loudest * 0.18)
        // Require two consecutive seconds of audible content to avoid
        // picking a single loud click in an otherwise silent intro.
        for index in 0..<max(0, levels.count - 1) {
            if levels[index] >= threshold && levels[index + 1] >= threshold * 0.65 {
                return max(0, Double(index) - 0.25)
            }
        }
        return 0
    }
}
