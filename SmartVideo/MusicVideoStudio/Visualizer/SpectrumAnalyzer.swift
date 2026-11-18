import Foundation
import Accelerate

extension MusicVideoStudio {
    /// Offline, deterministic spectrum analysis (Hann window + vDSP FFT). The same samples
    /// always give the same SpectrumData, on any run or device.
    enum SpectrumAnalyzer {
        static let fftSize = 2048
        static let minFrequency = 40.0
        static let maxFrequency = 16_000.0
        /// Level (dB re full scale) that maps to 0.
        static let floorDB: Float = -66

        /// `count + 1` log-spaced band edges in Hz.
        static func bandEdges(count: Int, sampleRate: Double) -> [Double] {
            let top = min(maxFrequency, sampleRate / 2 * 0.98)
            let ratio = pow(top / minFrequency, 1 / Double(max(1, count)))
            return (0...count).map { minFrequency * pow(ratio, Double($0)) }
        }

        static func analyze(samples: [Float], sampleRate: Double, frameRate: Double = 30, bandCount: Int = 96) -> SpectrumData {
            let n = fftSize, half = n / 2
            let log2n = vDSP_Length(11)
            let empty = SpectrumData(frameRate: frameRate, bandCount: max(1, bandCount), frames: [], beats: [])
            guard sampleRate > 0, frameRate > 0, bandCount > 0, !samples.isEmpty,
                  let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return empty }
            defer { vDSP_destroy_fftsetup(setup) }

            let window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) }
            let edges = bandEdges(count: bandCount, sampleRate: sampleRate)
            let binHz = sampleRate / Double(n)
            var ranges: [(lo: Int, hi: Int)] = []
            var tilt: [Float] = []
            for b in 0..<bandCount {
                let lo = min(half - 2, max(1, Int(edges[b] / binHz)))
                let hi = min(half - 1, max(lo + 1, Int((edges[b + 1] / binHz).rounded(.up))))
                ranges.append((lo, hi))
                // Music falls roughly 3 dB per octave: lift the highs so they are visible.
                tilt.append(Float(2.5 * log2(sqrt(edges[b] * edges[b + 1]) / 500)))
            }

            let hop = sampleRate / frameRate
            let frameCount = max(1, Int((Double(samples.count) / hop).rounded(.up)))
            var frames = [Float](repeating: 0, count: frameCount * bandCount)
            var windowed = [Float](repeating: 0, count: n)
            var real = [Float](repeating: 0, count: half)
            var imag = [Float](repeating: 0, count: half)
            var mags = [Float](repeating: 0, count: half)

            for f in 0..<frameCount {
                let start = Int(Double(f) * hop) - n / 2
                for i in 0..<n {
                    let s = start + i
                    windowed[i] = (s >= 0 && s < samples.count) ? samples[s] * window[i] : 0
                }
                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        windowed.withUnsafeBufferPointer { wp in
                            wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                                vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(half))
                    }
                }
                for b in 0..<bandCount {
                    var peak: Float = 0
                    for k in ranges[b].lo..<ranges[b].hi { peak = max(peak, mags[k]) }
                    // |X| from vDSP is 2x the DFT; a Hann window halves a sine: amplitude = |X| * 2 / N.
                    let amplitude = peak.squareRoot() * 2 / Float(n)
                    let db = 20 * log10(max(amplitude, 1e-6)) + tilt[b]
                    let value = min(1, max(0, (db - floorDB) / -floorDB))
                    frames[f * bandCount + b] = (value * 255).rounded() / 255
                }
            }

            // Spectral flux of the low half of the spectrum -> beats.
            let lowCount = max(1, bandCount / 2)
            var flux = [Float](repeating: 0, count: frameCount)
            if frameCount > 1 {
                for f in 1..<frameCount {
                    var sum: Float = 0
                    for b in 0..<lowCount { sum += max(0, frames[f * bandCount + b] - frames[(f - 1) * bandCount + b]) }
                    flux[f] = sum / Float(lowCount)
                }
            }
            return SpectrumData(frameRate: frameRate, bandCount: bandCount, frames: frames,
                                beats: BeatDetector.detect(flux: flux, frameRate: frameRate))
        }
    }
}
