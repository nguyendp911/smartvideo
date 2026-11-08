import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

struct SilenceEditResult {
    let url: URL
    let originalDuration: Double
    let newDuration: Double
    let removedDuration: Double
}

/// Non-destructive voice silence removal. Detects 80ms RMS windows and
/// stitches audible regions, preserving configurable context around speech.
enum VoiceSilenceEditor {
    static func removeSilence(from source: URL,
                              thresholdDecibels: Double = -39,
                              minimumGap: Double = 0.45,
                              padding: Double = 0.12) async throws -> SilenceEditResult {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SmartVideoError.invalidMedia("Tệp thuyết minh không có âm thanh.")
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite && duration > 0.2 else {
            throw SmartVideoError.invalidMedia("Âm thanh quá ngắn để loại khoảng lặng.")
        }
        let windowSeconds = 0.08
        let windows = max(1, Int(ceil(duration / windowSeconds)))
        var energy = [Double](repeating: 0, count: windows)
        var samples = [Int](repeating: 0, count: windows)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleavedKey: false
        ])
        guard reader.canAdd(output) else {
            throw SmartVideoError.invalidMedia("Không giải mã được âm thanh.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw SmartVideoError.invalidMedia(reader.error?.localizedDescription
                                               ?? "Không mở được tệp âm thanh.")
        }
        defer { reader.cancelReading() }

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Int16>.size
            guard count > 0 else { continue }
            var pcm = [Int16](repeating: 0, count: count)
            let copied = count * MemoryLayout<Int16>.size
            let status = pcm.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0,
                                           dataLength: copied,
                                           destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            let start = CMTimeGetSeconds(
                CMSampleBufferGetPresentationTimeStamp(buffer)
            )
            let sampleRate = CMSampleBufferGetFormatDescription(buffer)
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mSampleRate }
                ?? 44_100
            guard start.isFinite, sampleRate > 0 else { continue }
            for index in stride(from: 0, to: count, by: 24) {
                let t = start + Double(index) / sampleRate
                let bucket = Int(t / windowSeconds)
                guard energy.indices.contains(bucket) else { continue }
                let value = Double(pcm[index]) / 32768
                energy[bucket] += value * value
                samples[bucket] += 1
            }
        }
        if reader.status == .failed {
            throw SmartVideoError.invalidMedia(
                reader.error?.localizedDescription ?? "Không phân tích được âm thanh."
            )
        }

        let threshold = pow(10, max(-60, min(-18, thresholdDecibels)) / 20)
        let voiced: [Bool] = energy.indices.map { i in
            samples[i] > 0 && sqrt(energy[i] / Double(samples[i])) > threshold
        }
        guard voiced.contains(true) else {
            throw SmartVideoError.invalidMedia(
                "Không phát hiện lời nói. Hạ ngưỡng âm lượng hoặc chọn tệp khác."
            )
        }
        var runs: [(Double, Double)] = []
        var runStart: Int?
        for i in 0...windows {
            let on = i < windows && voiced[i]
            if on && runStart == nil { runStart = i }
            if !on, let first = runStart {
                let from = Double(first) * windowSeconds
                let to = min(duration, Double(i) * windowSeconds)
                runs.append((from, to))
                runStart = nil
            }
        }
        let safePad = max(0, min(padding, 0.4))
        var segments: [(Double, Double)] = []
        for run in runs where run.1 - run.0 >= 0.08 {
            let low = max(0, run.0 - safePad)
            let high = min(duration, run.1 + safePad)
            if let last = segments.indices.last,
               low - segments[last].1 < max(0.1, minimumGap) {
                segments[last].1 = max(high, segments[last].1)
            } else {
                segments.append((low, high))
            }
        }
        guard !segments.isEmpty else {
            throw SmartVideoError.invalidMedia("Không tìm được đoạn giọng đọc đủ dài.")
        }

        let composition = AVMutableComposition()
        guard let destination = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw SmartVideoError.cannotCreateWriter }
        var time = CMTime.zero
        for (low, high) in segments {
            let start = CMTime(seconds: low, preferredTimescale: 600)
            let length = CMTime(seconds: high - low, preferredTimescale: 600)
            try destination.insertTimeRange(
                CMTimeRange(start: start, duration: length),
                of: track, at: time
            )
            time = CMTimeAdd(time, length)
        }
        let kept = time.seconds
        if duration - kept < 0.10 {
            throw SmartVideoError.invalidMedia(
                "Không có khoảng lặng đủ dài cần cắt theo ngưỡng hiện tại."
            )
        }

        let target = MediaStorage.mediaDirectory
            .appendingPathComponent("GiongDoc-DaCat-\(UUID().uuidString).m4a")
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetAppleM4A
        ) else { throw SmartVideoError.cannotCreateWriter }
        exporter.outputURL = target
        exporter.outputFileType = .m4a
        exporter.metadata = []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { done.resume() }
        }
        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: target)
            throw SmartVideoError.cannotExport(
                exporter.error?.localizedDescription ?? "Không xuất được giọng đã cắt."
            )
        }
        return SilenceEditResult(url: target,
                                 originalDuration: duration,
                                 newDuration: kept,
                                 removedDuration: max(0, duration - kept))
    }
}
