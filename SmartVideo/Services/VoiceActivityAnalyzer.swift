import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Finds the stretches of a narration file that actually contain speech so
/// background music can duck only while someone is talking. Decodes at 16 kHz
/// mono and keeps one RMS value per 20 ms window (a 15 minute file is ~45k
/// floats), so memory and CPU stay bounded on older iPhones.
enum VoiceActivityAnalyzer {
    static let sampleRate = 16_000
    static let windowSeconds = 0.02

    /// Speech intervals in seconds of the FILE (0 = start of the file).
    static func analyze(
        url: URL, maxSeconds: Double = 900
    ) async throws -> [VoiceActivityMath.Interval] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(
            withMediaType: .audio
        ).first else { return [] }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0.1 else { return [] }
        let length = min(duration, max(1, maxSeconds))

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? SmartVideoError.invalidMedia(
                "Không đọc được tệp thuyết minh để phân tích giọng nói."
            )
        }
        defer { reader.cancelReading() }

        let window = Int(Double(sampleRate) * windowSeconds)
        var levels: [Float] = []
        levels.reserveCapacity(Int(length / windowSeconds) + 1)
        var sumSquares = 0.0
        var counted = 0

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
            for sample in pcm {
                let value = Double(sample) / 32768.0
                sumSquares += value * value
                counted += 1
                if counted == window {
                    levels.append(Float((sumSquares / Double(window)).squareRoot()))
                    sumSquares = 0
                    counted = 0
                }
            }
        }
        if reader.status == .failed, let error = reader.error { throw error }
        return VoiceActivityMath.intervals(
            rms: levels, windowSeconds: windowSeconds
        )
    }
}
