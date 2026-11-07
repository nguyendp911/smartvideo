import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Offline musical high points by energy, dynamics and peak activity.
/// Not lyric-, emotion- or beat-aware semantic AI.
enum SmartMusicHighlights {
    static func find(in url: URL, desiredLength: Double) async throws -> [MusicHighlight] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SmartVideoError.invalidMedia("Không tìm thấy track âm thanh.")
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite && duration > 1 else {
            throw SmartVideoError.invalidMedia("Độ dài nhạc không hợp lệ.")
        }

        let scanSeconds = min(duration, 240)
        let bucketTime = 0.5
        let count = max(1, Int(ceil(scanSeconds / bucketTime)))
        var energy = [Double](repeating: 0, count: count)
        var counts = [Double](repeating: 0, count: count)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: scanSeconds, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else {
            throw SmartVideoError.invalidMedia("Định dạng âm thanh không phân tích được.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw SmartVideoError.invalidMedia(
                reader.error?.localizedDescription ?? "Không đọc được nhạc."
            )
        }
        defer { reader.cancelReading() }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pcm = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(pcm)
            guard length >= 2 else { continue }

            var buffer = [Int16](repeating: 0, count: length / 2)
            let copiedBytes = buffer.count * MemoryLayout<Int16>.size
            let status = buffer.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(
                    pcm, atOffset: 0, dataLength: copiedBytes,
                    destination: bytes.baseAddress!
                )
            }
            guard status == kCMBlockBufferNoErr else { continue }
            let second = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard second.isFinite, second >= 0 else { continue }
            let bucket = Int(second / bucketTime)
            guard energy.indices.contains(bucket) else { continue }
            for index in stride(from: 0, to: buffer.count, by: 32) {
                let normalized = Double(buffer[index]) / 32768.0
                energy[bucket] += normalized * normalized
                counts[bucket] += 1
            }
        }

        if reader.status == .failed {
            throw SmartVideoError.invalidMedia(
                reader.error?.localizedDescription ?? "Không phân tích được nhạc."
            )
        }
        let rms = energy.indices.map { index -> Double in
            counts[index] > 0 ? sqrt(energy[index] / counts[index]) : 0
        }
        let peak = max(rms.max() ?? 0, 0.0001)
        let normalized = rms.map { min(1, $0 / peak) }
        let countWindow = min(count, max(2, Int(desiredLength / bucketTime)))
        let maxStart = max(0, count - countWindow)
        var candidates: [MusicHighlight] = []

        for offset in stride(from: 0, through: maxStart, by: 2) {
            let fragment = Array(normalized[offset..<min(count, offset + countWindow)])
            guard fragment.count > 1 else { continue }
            let average = fragment.reduce(0, +) / Double(fragment.count)
            let dynamics = zip(fragment.dropFirst(), fragment).reduce(0.0) { sum, pair in
                sum + max(0, pair.0 - pair.1)
            } / Double(fragment.count)
            let highCount = Double(fragment.filter { $0 > 0.55 }.count) / Double(fragment.count)
            let score = average * 0.55 + dynamics * 0.22 + highCount * 0.23
            candidates.append(MusicHighlight(
                start: Double(offset) * bucketTime,
                duration: min(desiredLength, scanSeconds - Double(offset) * bucketTime),
                score: score
            ))
        }
        let ordered = candidates.sorted { $0.score > $1.score }
        var selected: [MusicHighlight] = []
        for candidate in ordered {
            if selected.allSatisfy({ abs($0.start - candidate.start) >= desiredLength * 0.8 }) {
                selected.append(candidate)
            }
            if selected.count == 3 { break }
        }
        return selected.sorted { $0.start < $1.start }
    }
}
