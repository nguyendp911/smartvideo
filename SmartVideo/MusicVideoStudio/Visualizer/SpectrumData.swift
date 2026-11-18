import Foundation

extension MusicVideoStudio {
    /// The analysed spectrum of one audio FILE: `frameRate` frames per second, `bandCount`
    /// log-spaced bands, every value 0...1 (steps of 1/255, so memory and disk agree exactly).
    /// Reading is a pure function of the time asked for: no state, no timers.
    struct SpectrumData: Equatable {
        var frameRate: Double
        var bandCount: Int
        /// frame-major: frames[frame * bandCount + band]
        var frames: [Float]
        /// Beat times in seconds of the file.
        var beats: [Double]

        init(frameRate: Double, bandCount: Int, frames: [Float], beats: [Double] = []) {
            self.frameRate = frameRate
            self.bandCount = bandCount
            self.frames = frames
            self.beats = beats
        }

        var frameCount: Int { bandCount > 0 ? frames.count / bandCount : 0 }
        var duration: Double { frameRate > 0 ? Double(frameCount) / frameRate : 0 }

        static let maxLookback = 30

        /// Trailing-decay smoothing: a band falls at most `decay` per frame after a peak.
        private func smoothed(frame: Int, band: Int, decay: Float) -> Float {
            var best: Float = 0
            var weight: Float = 1
            var index = frame
            for _ in 0..<Self.maxLookback {
                if index < 0 || weight < 0.01 { break }
                if index < frameCount { best = max(best, frames[index * bandCount + band] * weight) }
                weight *= decay
                index -= 1
            }
            return best
        }

        /// `count` band levels (0...1) at file time `time`, interpolated between frames.
        /// Outside the file, or for non-finite times, everything is 0.
        func bands(at time: Double, count: Int, decay: Double = 0.7) -> [Float] {
            guard count > 0 else { return [] }
            guard time.isFinite, time >= 0, frameCount > 0, time < duration else { return [Float](repeating: 0, count: count) }
            let position = time * frameRate
            let first = Int(position)
            let fraction = Float(position - Double(first))
            let fall = Float(min(0.95, max(0, decay)))
            var out = [Float](repeating: 0, count: count)
            for k in 0..<count {
                let lo = min(bandCount - 1, k * bandCount / count)
                let hi = min(bandCount, max(lo + 1, (k + 1) * bandCount / count))
                var a: Float = 0, b: Float = 0
                for band in lo..<hi {
                    a = max(a, smoothed(frame: first, band: band, decay: fall))
                    b = max(b, smoothed(frame: first + 1, band: band, decay: fall))
                }
                out[k] = a + (b - a) * fraction
            }
            return out
        }

        /// Average level of the lowest quarter of the bands (the "kick"), 0...1.
        func bass(at time: Double) -> Double {
            guard time.isFinite, time >= 0, frameCount > 0, time < duration else { return 0 }
            let frame = min(frameCount - 1, Int(time * frameRate))
            let lowBands = max(1, bandCount / 4)
            var sum: Float = 0
            for band in 0..<lowBands { sum += frames[frame * bandCount + band] }
            return Double(sum / Float(lowBands))
        }

        /// 1 at a beat, falling to 0 over roughly `release` seconds. 0 before the first beat.
        func beatPulse(at time: Double, release: Double = 0.18) -> Double {
            guard time.isFinite, !beats.isEmpty, time >= beats[0] else { return 0 }
            var lo = 0, hi = beats.count - 1
            while lo < hi {                                   // last beat <= time
                let mid = (lo + hi + 1) / 2
                if beats[mid] <= time { lo = mid } else { hi = mid - 1 }
            }
            return exp(-(time - beats[lo]) / max(0.01, release))
        }

        // MARK: Compact binary form (disk cache)

        private static let magic: [UInt8] = Array("SPK1".utf8)

        func encoded() -> Data {
            var data = Data(Self.magic)
            func put<T>(_ value: T) { var v = value; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
            put(frameRate)
            put(Int32(bandCount)); put(Int32(frameCount)); put(Int32(beats.count))
            for beat in beats { put(beat) }
            data.append(contentsOf: frames.map { UInt8(min(255, max(0, ($0 * 255).rounded()))) })
            return data
        }

        init?(decoding data: Data) {
            let bytes = [UInt8](data)
            guard bytes.count >= 24, Array(bytes[0..<4]) == Self.magic else { return nil }
            func read<T>(_ offset: Int, _ type: T.Type) -> T? {
                guard offset + MemoryLayout<T>.size <= bytes.count else { return nil }
                return bytes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
            }
            guard let rate = read(4, Double.self), let bandCount32 = read(12, Int32.self),
                  let frameCount32 = read(16, Int32.self), let beatCount32 = read(20, Int32.self),
                  rate > 0, bandCount32 > 0, frameCount32 >= 0, beatCount32 >= 0 else { return nil }
            let bandCount = Int(bandCount32), frameCount = Int(frameCount32), beatCount = Int(beatCount32)
            let valueCount = bandCount * frameCount
            guard bytes.count == 24 + beatCount * 8 + valueCount else { return nil }
            var beats: [Double] = []
            beats.reserveCapacity(beatCount)
            for i in 0..<beatCount { if let beat = read(24 + i * 8, Double.self) { beats.append(beat) } }
            let start = 24 + beatCount * 8
            self.init(frameRate: rate, bandCount: bandCount,
                      frames: bytes[start...].map { Float($0) / 255 }, beats: beats)
        }
    }

    /// Picks beats out of a "spectral flux" series: peaks well above the local average.
    enum BeatDetector {
        static func detect(flux: [Float], frameRate: Double, sensitivity: Double = 1.5,
                           minGap: Double = 0.28, floor: Double = 0.02) -> [Double] {
            guard flux.count > 2, frameRate > 0 else { return [] }
            let radius = max(2, Int(frameRate * 0.75))
            var prefix = [Double](repeating: 0, count: flux.count + 1)
            for i in flux.indices { prefix[i + 1] = prefix[i] + Double(flux[i]) }
            var beats: [Double] = []
            var last = -Double.infinity
            for i in 1..<(flux.count - 1) {
                let lo = max(0, i - radius), hi = min(flux.count, i + radius + 1)
                let mean = (prefix[hi] - prefix[lo]) / Double(hi - lo)
                let value = Double(flux[i])
                guard value > mean * sensitivity + floor, flux[i] >= flux[i - 1], flux[i] > flux[i + 1] else { continue }
                let time = Double(i) / frameRate
                if time - last >= minGap { beats.append(time); last = time }
            }
            return beats
        }
    }

    /// Turning beats into photo cuts.
    enum BeatMath {
        /// Cut times (project seconds) inside [from, to): `from`, then every `every`-th beat
        /// that leaves at least `minimum` seconds on both sides, then `to`.
        static func cutTimes(beats: [Double], every: Int, from: Double, to: Double, minimum: Double = 0.4) -> [Double] {
            guard to > from, every >= 1 else { return [] }
            let inside = beats.filter { $0 > from && $0 < to }.sorted()
            var cuts = [from]
            var counter = 0
            for beat in inside {
                if counter % every == 0, beat - cuts[cuts.count - 1] >= minimum, to - beat >= minimum { cuts.append(beat) }
                counter += 1
            }
            cuts.append(to)
            return cuts
        }
    }

    /// Where a visualizer's audio-file time sits on the project clock.
    enum VisualizerTiming {
        static func offset(_ layer: VisualizerLayer, in project: VideoProject) -> Double {
            if let id = layer.audioLayerID, let audio = project.audios.first(where: { $0.core.id == id }) {
                return audio.core.start.seconds - audio.sourceStart
            }
            return layer.core.start.seconds
        }

        static func sourceTime(_ layer: VisualizerLayer, in project: VideoProject, at time: ProjectTime) -> Double {
            time.seconds - offset(layer, in: project)
        }
    }

    /// Everything the painter needs for one instant. Preview and export both build it here.
    struct VisualizerFrame: Equatable {
        var bands: [Float]
        var bass: Double
        var pulse: Double
        /// Slowly falling copy of `bands` (peak-hold caps). Empty = use `bands`.
        var peaks: [Float] = []

        static func make(layer: VisualizerLayer, spectrum: SpectrumData?, sourceTime: Double) -> VisualizerFrame {
            guard let spectrum else { return VisualizerFrame(bands: [Float](repeating: 0, count: layer.barCount), bass: 0, pulse: 0) }
            return VisualizerFrame(bands: spectrum.bands(at: sourceTime, count: layer.barCount, decay: layer.smoothing),
                                   bass: spectrum.bass(at: sourceTime), pulse: spectrum.beatPulse(at: sourceTime),
                                   peaks: spectrum.bands(at: sourceTime, count: layer.barCount, decay: 0.95))
        }
    }
}
