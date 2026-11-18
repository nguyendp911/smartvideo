import Foundation
import AVFoundation

extension MusicVideoStudio {
    /// Decodes a file's real samples (mono, 22.05 kHz) and analyses them once.
    enum SpectrumGenerator {
        static let sampleRate = 22_050.0
        /// Longer files are analysed up to this point only (about 8 min of float samples = 40 MB).
        static let maxSeconds = 480.0

        static func generate(url: URL, bandCount: Int = 96, frameRate: Double = 30) async throws -> SpectrumData {
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

            let limit = Int(maxSeconds * sampleRate)
            var samples: [Float] = []
            while samples.count < limit, let buffer = output.copyNextSampleBuffer() {
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
                samples.append(contentsOf: chunk)
            }
            reader.cancelReading()
            if samples.isEmpty { throw AudioError.unreadable }
            try Task.checkCancellation()
            return SpectrumAnalyzer.analyze(samples: samples, sampleRate: sampleRate, frameRate: frameRate, bandCount: bandCount)
        }
    }

    /// Memory + disk cache keyed by file path, size and modification date.
    final class SpectrumCache {
        static let shared = SpectrumCache()

        private final class Box { let value: SpectrumData; init(_ value: SpectrumData) { self.value = value } }
        private let memory = NSCache<NSString, Box>()
        private let directory: URL

        init(directory: URL? = nil) {
            let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("MusicVideoSpectra", isDirectory: true)
            self.directory = base
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            memory.countLimit = 6
        }

        private func key(for url: URL) -> String {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let text = ["v1", url.path, "\(values?.fileSize ?? 0)", "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"].joined(separator: "|")
            var hash: UInt64 = 0xcbf29ce484222325
            for byte in text.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
            return String(hash, radix: 16)
        }

        func cached(for url: URL) -> SpectrumData? {
            let k = key(for: url)
            if let hit = memory.object(forKey: k as NSString) { return hit.value }
            if let data = try? Data(contentsOf: directory.appendingPathComponent(k + ".spk")), let value = SpectrumData(decoding: data) {
                memory.setObject(Box(value), forKey: k as NSString)
                return value
            }
            return nil
        }

        func spectrum(for url: URL) async -> SpectrumData? {
            if let hit = cached(for: url) { return hit }
            guard let value = try? await SpectrumGenerator.generate(url: url) else { return nil }
            let k = key(for: url)
            memory.setObject(Box(value), forKey: k as NSString)
            try? value.encoded().write(to: directory.appendingPathComponent(k + ".spk"), options: .atomic)
            return value
        }
    }
}
