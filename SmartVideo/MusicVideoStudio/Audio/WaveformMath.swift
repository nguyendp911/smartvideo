import Foundation
import Accelerate

extension MusicVideoStudio {
    /// Peak envelope of an audio file: one value 0...1 per bucket.
    struct Waveform: Codable, Equatable {
        var bucketsPerSecond: Double
        var peaks: [Float]
        var duration: Double { bucketsPerSecond > 0 ? Double(peaks.count) / bucketsPerSecond : 0 }
    }

    enum WaveformMath {
        /// Peak (max |sample|) per bucket, computed with vDSP. REAL samples in, real peaks out.
        static func peaks(samples: [Float], sampleRate: Double, bucketsPerSecond: Double) -> [Float] {
            guard sampleRate > 0, bucketsPerSecond > 0, !samples.isEmpty else { return [] }
            let per = max(1, Int((sampleRate / bucketsPerSecond).rounded()))
            var result: [Float] = []
            result.reserveCapacity(samples.count / per + 1)
            samples.withUnsafeBufferPointer { buffer in
                var index = 0
                while index < buffer.count {
                    let n = min(per, buffer.count - index)
                    var peak: Float = 0
                    vDSP_maxmgv(buffer.baseAddress! + index, 1, &peak, vDSP_Length(n))
                    result.append(min(1, peak.isFinite ? peak : 0))
                    index += n
                }
            }
            return result
        }

        /// Max peak of the waveform between two times (seconds); 0 outside the file.
        static func peak(_ waveform: Waveform, from: Double, to: Double) -> Float {
            guard waveform.bucketsPerSecond > 0, !waveform.peaks.isEmpty, to > from else { return 0 }
            let first = max(0, Int((from * waveform.bucketsPerSecond).rounded(.down)))
            let last = min(waveform.peaks.count - 1, Int((to * waveform.bucketsPerSecond).rounded(.up)))
            guard first <= last else { return 0 }
            return waveform.peaks[first...last].max() ?? 0
        }

        /// `count` columns describing a CLIP on the timeline: clip-local time maps to
        /// file time through the trim point and (optionally) looping, so the drawing
        /// is visually tied to what will actually be heard.
        static func clipColumns(_ waveform: Waveform, sourceStart: Double, sourceDuration: Double,
                                clipDuration: Double, loops: Bool, count: Int) -> [Float] {
            guard count > 0, clipDuration > 0 else { return [] }
            let span = max(0.001, sourceDuration - sourceStart)
            var columns = [Float](repeating: 0, count: count)
            for column in 0..<count {
                let t0 = clipDuration * Double(column) / Double(count)
                let t1 = clipDuration * Double(column + 1) / Double(count)
                if !loops, t0 >= span { continue }
                let s0 = sourceStart + (loops ? t0.truncatingRemainder(dividingBy: span) : t0)
                var s1 = sourceStart + (loops ? t1.truncatingRemainder(dividingBy: span) : min(t1, span))
                if s1 <= s0 { s1 = s0 + 1 / max(1, waveform.bucketsPerSecond) }       // wrapped inside one column
                columns[column] = peak(waveform, from: s0, to: s1)
            }
            return columns
        }
    }
}
