import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Sample real signal amplitudes for an inexpensive waveform in the editor.
/// Decode only a user-selected 90-second viewport, never an entire
/// multi-hour file; this keeps memory/CPU usage bounded on older iPhones.
enum AudioWaveformSampler {
    static func sample(
        url: URL, count: Int = 64,
        from offset: Double = 0, window: Double = 90
    ) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(
            withMediaType: .audio
        ).first else { return [] }

        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { return [] }
        let start = min(max(0, offset.isFinite ? offset : 0),
                        max(0, duration - 0.05))
        let seconds = min(duration - start,
                          max(0.5, min(90, window.isFinite ? window : 90)))
        guard seconds > 0.04 else { return [] }
        let count = max(12, min(160, count))
        var peaks = [Double](repeating: 0, count: count)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: seconds, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        defer { reader.cancelReading() }

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            guard bytes >= 2 else { continue }
            var pcm = [Int16](repeating: 0, count: bytes / 2)
            let copied = pcm.count * MemoryLayout<Int16>.size
            let status = pcm.withUnsafeMutableBytes { storage in
                CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: copied,
                    destination: storage.baseAddress!
                )
            }
            guard status == kCMBlockBufferNoErr else { continue }
            let second = CMTimeGetSeconds(
                CMSampleBufferGetPresentationTimeStamp(buffer)
            )
            guard second.isFinite, second >= start else { continue }
            let index = min(count - 1, max(0, Int(
                (second - start) / seconds * Double(count)
            )))
            for offset in stride(from: 0, to: pcm.count, by: 64) {
                peaks[index] = max(peaks[index],
                                   abs(Double(pcm[offset]) / 32768.0))
            }
        }
        let peak = max(peaks.max() ?? 0, 0.01)
        return peaks.map { min(1, max(0.06, sqrt($0 / peak))) }
    }
}
