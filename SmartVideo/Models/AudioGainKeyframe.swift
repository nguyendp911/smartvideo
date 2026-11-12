import Foundation

/// A volume automation point, located within one SFX region (0...1).
/// Gain multiplies the track's base volume; zero is silence.
struct AudioGainKeyframe: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var progress: Double
    var gain: Float

    init(id: UUID = UUID(), progress: Double, gain: Float) {
        self.id = id
        self.progress = AudioAutomationMath.clampProgress(progress)
        self.gain = AudioAutomationMath.clampGain(gain)
    }
}

enum AudioAutomationMath {
    static func clampProgress(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    static func clampGain(_ value: Float) -> Float {
        value.isFinite ? min(1, max(0, value)) : 1
    }

    static func normalized(_ frames: [AudioGainKeyframe]) -> [AudioGainKeyframe] {
        var result: [AudioGainKeyframe] = []
        for frame in frames.prefix(24).sorted(by: { $0.progress < $1.progress }) {
            var fixed = frame
            fixed.progress = clampProgress(frame.progress)
            fixed.gain = clampGain(frame.gain)
            if let last = result.last,
               abs(last.progress - fixed.progress) < 0.0001 {
                result[result.count - 1] = fixed
            } else {
                result.append(fixed)
            }
        }
        return result
    }

    /// Implicit 100% gain at each boundary for legacy/no-keyframe SFX.
    static func factor(at progress: Double,
                       frames: [AudioGainKeyframe]) -> Float {
        let p = clampProgress(progress)
        let ordered = normalized(frames)
        guard !ordered.isEmpty else { return 1 }
        let nodes: [(Double, Float)] =
            (ordered.first!.progress > 0.0001 ? [(0, 1)] : []) +
            ordered.map { ($0.progress, $0.gain) } +
            (ordered.last!.progress < 0.9999 ? [(1, 1)] : [])
        if p <= nodes[0].0 { return nodes[0].1 }
        for (a, b) in zip(nodes, nodes.dropFirst()) where p <= b.0 {
            let blend = (p - a.0) / max(0.000001, b.0 - a.0)
            return Float(Double(a.1) + blend * Double(b.1 - a.1))
        }
        return nodes.last!.1
    }

    static func gain(
        at second: Double, duration: Double, volume: Float, muted: Bool,
        fadeIn: Double, fadeOut: Double, frames: [AudioGainKeyframe]
    ) -> Float {
        guard second.isFinite, duration.isFinite, duration > 0,
              second >= 0, second <= duration, !muted else { return 0 }
        let rise = min(max(0, fadeIn.isFinite ? fadeIn : 0), duration * 0.48)
        let fall = min(max(0, fadeOut.isFinite ? fadeOut : 0), duration * 0.48)
        let up = rise > 0.0001 ? min(1, second / rise) : 1
        let down = fall > 0.0001 ?
            min(1, max(0, (duration - second) / fall)) : 1
        let base = Double(clampGain(volume))
        let key = Double(factor(at: second / duration, frames: frames))
        return Float(min(1, max(0, base * up * down * key)))
    }

    /// Ramp points at keyframe positions and around fades; interpolates
    /// exactly between keyframes where fade multipliers are constant.
    /// Sampling fades at 50ms bounds complexity independent of clip length.
    static func envelope(
        duration: Double, volume: Float, muted: Bool,
        fadeIn: Double, fadeOut: Double,
        frames: [AudioGainKeyframe]
    ) -> [(second: Double, gain: Float)] {
        guard duration.isFinite, duration > 0.05 else { return [] }
        let inLength = min(max(0, fadeIn.isFinite ? fadeIn : 0),
                           duration * 0.48)
        let outLength = min(max(0, fadeOut.isFinite ? fadeOut : 0),
                            duration * 0.48)
        var positions: [Double] = [0, duration]
        positions += normalized(frames).map { $0.progress * duration }
        func sampleRegion(_ a: Double, _ b: Double) {
            guard b > a else { return }
            let steps = max(1, Int(ceil((b - a) / 0.05)))
            for n in 0...steps {
                positions.append(a + (b - a) * Double(n) / Double(steps))
            }
        }
        sampleRegion(0, inLength)
        sampleRegion(duration - outLength, duration)
        let quantized = Array(Set(positions.map {
            Int((min(duration, max(0, $0)) * 60_000).rounded())
        })).sorted()
        return quantized.map { i in
            let second = Double(i) / 60_000
            return (second: second, gain: gain(
                at: second, duration: duration, volume: volume,
                muted: muted, fadeIn: fadeIn, fadeOut: fadeOut, frames: frames
            ))
        }
    }

    /// Preserve absolute source-volume automation when one SFX is split.
    /// The incoming/outgoing edges are new keyframes at progress 0 and 1.
    static func slice(
        _ frames: [AudioGainKeyframe],
        start: Double, end: Double
    ) -> [AudioGainKeyframe] {
        guard !frames.isEmpty else { return [] }
        let a = clampProgress(start), b = clampProgress(end)
        guard b - a > 0.001 else { return [] }
        var sliced = [
            AudioGainKeyframe(progress: 0, gain: factor(at: a, frames: frames))
        ]
        for frame in normalized(frames)
            where frame.progress > a + 0.0001 &&
                  frame.progress < b - 0.0001 {
            sliced.append(AudioGainKeyframe(
                progress: (frame.progress - a) / (b - a),
                gain: frame.gain
            ))
        }
        sliced.append(AudioGainKeyframe(
            progress: 1, gain: factor(at: b, frames: frames)
        ))
        return normalized(sliced)
    }
}
