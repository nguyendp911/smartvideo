import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

/// Lightweight on-device beat *suggestions*: PCM RMS onset detection,
/// not machine understanding of the song or a guaranteed metronome.
struct MusicBeatAnalysis {
    let sourceTimes: [Double]
    let tempoBPM: Double
    let confidence: Double
    let analyzedDuration: Double
}

enum MusicBeatAnalyzer {
    static func analyze(url: URL, start: Double = 0,
                        scanDuration: Double = 90) async throws -> MusicBeatAnalysis {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SmartVideoError.invalidMedia("Không tìm được track âm thanh để phân tích nhịp.")
        }
        let total = try await asset.load(.duration).seconds
        guard total.isFinite, total > 0.75 else {
            throw SmartVideoError.invalidMedia("Tệp nhạc quá ngắn để phân tích nhịp.")
        }
        let from = min(max(0, start), max(0, total - 0.5))
        let available = min(max(0.5, scanDuration), total - from, 120)
        let window = 0.05
        let bucketCount = max(1, Int(ceil(available / window)))
        var power = [Double](repeating: 0, count: bucketCount)
        var sampleCount = [Int](repeating: 0, count: bucketCount)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: from, preferredTimescale: 600),
            duration: CMTime(seconds: available, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else {
            throw SmartVideoError.invalidMedia("Không giải mã được nhạc để phân tích nhịp.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw SmartVideoError.invalidMedia(
                reader.error?.localizedDescription ?? "Không thể mở bộ giải mã nhạc."
            )
        }
        defer { reader.cancelReading() }

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount > 1 else { continue }
            var pcm = [Int16](repeating: 0, count: byteCount / 2)
            let status = pcm.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0,
                                           dataLength: pcm.count * 2,
                                           destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }

            let baseSecond = CMTimeGetSeconds(
                CMSampleBufferGetPresentationTimeStamp(buffer)
            )
            let asbd = CMSampleBufferGetFormatDescription(buffer)
                .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
            let rate = max(1, asbd?.mSampleRate ?? 44_100)
            let channels = max(1, Int(asbd?.mChannelsPerFrame ?? 1))
            let step = max(8, channels * 12)
            guard baseSecond.isFinite else { continue }

            for offset in stride(from: 0, to: pcm.count, by: step) {
                let relative = baseSecond - from +
                    Double(offset / channels) / rate
                let index = Int(relative / window)
                guard power.indices.contains(index) else { continue }
                let level = Double(pcm[offset]) / 32768
                power[index] += level * level
                sampleCount[index] += 1
            }
        }
        if reader.status == .failed {
            throw SmartVideoError.invalidMedia(
                reader.error?.localizedDescription ?? "Đọc mẫu âm thanh thất bại."
            )
        }

        let rms = power.indices.map { i -> Double in
            guard sampleCount[i] > 0 else { return 0 }
            return sqrt(power[i] / Double(sampleCount[i]))
        }
        guard (rms.max() ?? 0) > 0.001 else {
            throw SmartVideoError.invalidMedia("Đoạn nhạc đang chọn gần như im lặng.")
        }

        // Local adaptive onset: rise above the preceding ~0.3s energy
        // while suppressing adjacent transients from one kick/drum hit.
        var onsets = [Double](repeating: 0, count: rms.count)
        for i in rms.indices {
            let lower = max(0, i - 7)
            let baseline = rms[lower...i].reduce(0, +) /
                Double(i - lower + 1)
            onsets[i] = max(0, rms[i] - baseline)
        }
        let sorted = onsets.sorted()
        let percentile = sorted[min(sorted.count - 1,
                                    Int(Double(sorted.count) * 0.76))]
        let threshold = max(0.005, percentile * 1.55)
        var peaks: [(index: Int, strength: Double)] = []
        if onsets.count >= 5 {
            for i in 2..<(onsets.count - 2) {
                let value = onsets[i]
                guard value >= threshold,
                      value >= onsets[i - 1],
                      value >= onsets[i + 1] else { continue }
                if let last = peaks.last, Double(i - last.index) * window < 0.24 {
                    if value > last.strength {
                        peaks[peaks.count - 1] = (i, value)
                    }
                } else {
                    peaks.append((i, value))
                }
            }
        }
        guard peaks.count >= 3 else {
            throw SmartVideoError.invalidMedia(
                "Chưa tìm được nhịp rõ. Hãy chọn đoạn nhạc có trống/nhịp nổi bật."
            )
        }

        // Onset autocorrelation to suggest a plausible tempo in 70–180 BPM.
        var bestLag = 0
        var bestScore = 0.0
        let minLag = Int((60.0 / 180.0) / window)
        let maxLag = Int((60.0 / 70.0) / window)
        for lag in minLag...maxLag where lag < onsets.count / 2 {
            var score = 0.0
            for i in lag..<onsets.count {
                score += onsets[i] * onsets[i - lag]
            }
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        let beatPeriod = bestLag > 0 ? Double(bestLag) * window : 0.5
        let bpm = 60.0 / beatPeriod
        // Align grid origin to strongest onset early in the scan.
        let firstWindow = peaks.filter { Double($0.index) * window <= 8 }
        let anchor = (firstWindow.max { $0.strength < $1.strength } ??
                      peaks[0]).index
        var beatTimes: [Double] = []
        var t = Double(anchor) * window
        while t > beatPeriod / 2 { t -= beatPeriod }
        while t < available {
            if t >= 0 { beatTimes.append(from + t) }
            t += beatPeriod
        }
        let confidence = min(1, max(0.1,
            bestScore / max(0.0001, onsets.reduce(0) { $0 + $1 * $1 })
        ))
        return MusicBeatAnalysis(sourceTimes: beatTimes, tempoBPM: bpm,
                                 confidence: confidence,
                                 analyzedDuration: available)
    }
}
