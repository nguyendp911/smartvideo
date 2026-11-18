import Foundation
import AVFoundation

extension MusicVideoStudio {
    enum AudioError: LocalizedError {
        case noAudioTrack
        case unreadable

        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "Tệp không có âm thanh."
            case .unreadable: return "Không đọc được âm thanh của tệp."
            }
        }
    }

    /// Decodes a file's REAL samples (mono, 11 kHz) in a stream and reduces them to a peak envelope.
    enum WaveformGenerator {
        static let sampleRate = 11_025.0

        static func generate(url: URL, bucketsPerSecond: Double = 100) async throws -> Waveform {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw AudioError.noAudioTrack }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            guard reader.canAdd(output) else { throw AudioError.unreadable }
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? AudioError.unreadable }

            let per = max(1, Int((sampleRate / bucketsPerSecond).rounded()))
            let actualRate = sampleRate / Double(per)
            var peaks: [Float] = []
            var pending: [Float] = []
            while let buffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let bytes = CMBlockBufferGetDataLength(block)
                guard bytes >= MemoryLayout<Float>.size else { continue }
                var chunk = [Float](repeating: 0, count: bytes / MemoryLayout<Float>.size)
                let copied = chunk.count * MemoryLayout<Float>.size
                let status = chunk.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: copied, destination: $0.baseAddress!)
                }
                guard status == kCMBlockBufferNoErr else { continue }
                pending.append(contentsOf: chunk)
                let full = pending.count / per * per
                if full > 0 {
                    peaks += WaveformMath.peaks(samples: Array(pending[0..<full]), sampleRate: sampleRate, bucketsPerSecond: actualRate)
                    pending.removeFirst(full)
                }
            }
            if reader.status == .failed { throw reader.error ?? AudioError.unreadable }
            if !pending.isEmpty {
                peaks += WaveformMath.peaks(samples: pending, sampleRate: sampleRate, bucketsPerSecond: actualRate)
            }
            return Waveform(bucketsPerSecond: actualRate, peaks: peaks)
        }
    }

    /// Memory + disk cache keyed by file path, size and modification date.
    final class WaveformCache {
        static let shared = WaveformCache()

        private final class Box { let value: Waveform; init(_ value: Waveform) { self.value = value } }
        private let memory = NSCache<NSString, Box>()
        private let directory: URL

        init(directory: URL? = nil) {
            let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MusicVideoWaveforms", isDirectory: true)
            self.directory = base
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            memory.countLimit = 24
        }

        private func key(for url: URL) -> String {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let text = [url.path, "\(values?.fileSize ?? 0)", "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"].joined(separator: "|")
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in text.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
            return String(hash, radix: 16)
        }

        func cached(for url: URL) -> Waveform? {
            let k = key(for: url)
            if let hit = memory.object(forKey: k as NSString) { return hit.value }
            let file = directory.appendingPathComponent(k + ".json")
            if let data = try? Data(contentsOf: file), let wave = try? JSONDecoder().decode(Waveform.self, from: data) {
                memory.setObject(Box(wave), forKey: k as NSString)
                return wave
            }
            return nil
        }

        func waveform(for url: URL) async -> Waveform? {
            if let hit = cached(for: url) { return hit }
            guard let wave = try? await WaveformGenerator.generate(url: url) else { return nil }
            let k = key(for: url)
            memory.setObject(Box(wave), forKey: k as NSString)
            if let data = try? JSONEncoder().encode(wave) {
                try? data.write(to: directory.appendingPathComponent(k + ".json"), options: .atomic)
            }
            return wave
        }
    }
}
