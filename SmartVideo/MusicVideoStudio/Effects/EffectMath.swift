import Foundation

extension MusicVideoStudio {
    /// Motion applied to the picture layers (photos, record, visualizer) by Shake / Beat Pulse.
    struct SceneMotion: Equatable {
        /// Fractions of the canvas width / height.
        var dx = 0.0
        var dy = 0.0
        var rotation = 0.0
        var scale = 1.0
        static let identity = SceneMotion()
    }

    enum EffectMath {
        static func smooth(_ x: Double) -> Double {
            let t = min(1, max(0, x.isFinite ? x : 0))
            return t * t * (3 - 2 * t)
        }

        /// Deterministic 0...1 value for (index, salt): film grain.
        static func unit(_ index: Int, _ salt: Int) -> Double {
            var x = UInt64(truncatingIfNeeded: index) &* 0x9E3779B97F4A7C15 &+ UInt64(truncatingIfNeeded: salt) &* 0xBF58476D1CE4E5B9
            x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
            x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
            x ^= x >> 31
            return Double(x % 100_000) / 100_000
        }

        /// Grain changes 24 times a second.
        static func grainFrame(_ seconds: Double) -> Int {
            seconds.isFinite ? Int((max(0, seconds) * 24).rounded(.down)) : 0
        }

        /// File beats -> project seconds, inside [from, to), keeping every `every`-th.
        static func projectBeats(fileBeats: [Double], offset: Double, from: Double, to: Double, every: Int) -> [Double] {
            let step = max(1, every)
            var out: [Double] = []
            var counter = 0
            for beat in fileBeats {
                let t = beat + offset
                guard t >= from, t < to else { continue }
                if counter % step == 0 { out.append(t) }
                counter += 1
            }
            return out
        }

        /// Seconds since the last beat at or before `time` (nil before the first beat).
        static func sinceLastBeat(_ time: Double, in beats: [Double]) -> Double? {
            guard time.isFinite, let first = beats.first, time >= first else { return nil }
            var lo = 0, hi = beats.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if beats[mid] <= time { lo = mid } else { hi = mid - 1 }
            }
            return time - beats[lo]
        }

        /// 1 on a beat, decaying over `release` seconds.
        static func pulse(_ time: Double, beats: [Double], release: Double) -> Double {
            guard let since = sinceLastBeat(time, in: beats) else { return 0 }
            return exp(-since / max(0.01, release))
        }

        /// White-flash level 0...1 for Flash.
        static func flash(_ layer: EffectLayer, beats: [Double], at time: Double) -> Double {
            min(1, max(0, layer.intensity)) * pulse(time, beats: beats, release: 0.1)
        }

        /// Black overlay opacity 0...1 for Fade to/from Black (smooth ramps at both ends of the layer).
        static func fadeBlack(_ layer: EffectLayer, at time: ProjectTime) -> Double {
            let local = (time - layer.core.start).seconds
            let length = layer.core.duration.seconds
            guard local.isFinite, local >= 0, local <= length else { return 0 }
            var black = 0.0
            if layer.fadeIn > 0 { black = max(black, 1 - smooth(local / layer.fadeIn)) }
            if layer.fadeOut > 0 { black = max(black, 1 - smooth((length - local) / layer.fadeOut)) }
            return black * min(1, max(0, layer.intensity))
        }

        /// A few detuned sines: irregular but a pure function of time.
        static func shake(_ layer: EffectLayer, at time: ProjectTime) -> SceneMotion {
            let t = (time - layer.core.start).seconds * 8 * max(0.1, layer.speed)
            let a = 0.02 * min(1, max(0, layer.intensity))
            let tau = 2 * Double.pi
            return SceneMotion(
                dx: a * (0.6 * sin(tau * t) + 0.4 * sin(tau * t * 2.3 + 1.7)),
                dy: a * (0.6 * sin(tau * t * 1.3 + 0.9) + 0.4 * sin(tau * t * 2.9 + 2.1)),
                rotation: a * 60 * sin(tau * t * 0.9 + 0.3),
                scale: 1 + a * 2.5)                                   // hides the edges that the shake exposes
        }

        static func beatPulseScale(_ layer: EffectLayer, beats: [Double], at time: Double) -> Double {
            1 + 0.12 * min(1, max(0, layer.intensity)) * pulse(time, beats: beats, release: 0.16)
        }

        /// Centre (0...1) and opacity of the moving light for Light Leak.
        static func lightLeak(_ layer: EffectLayer, at time: ProjectTime) -> (x: Double, y: Double, opacity: Double) {
            let phase = (time - layer.core.start).seconds * 0.1 * max(0.1, layer.speed)
            let tau = 2 * Double.pi
            let opacity = min(1, max(0, layer.intensity * (0.55 + 0.35 * sin(tau * phase * 1.3 + 2))))
            return (0.5 + 0.55 * sin(tau * phase), 0.35 + 0.25 * sin(tau * phase * 0.7 + 1), opacity)
        }

        /// Everything that moves the picture at `time`.
        static func sceneMotion(effects: [EffectLayer], at time: ProjectTime, beats: (EffectLayer) -> [Double]) -> SceneMotion {
            var motion = SceneMotion.identity
            for layer in effects where layer.kind.movesScene && layer.core.isActive(at: time) {
                switch layer.kind {
                case .shake:
                    let s = shake(layer, at: time)
                    motion.dx += s.dx; motion.dy += s.dy; motion.rotation += s.rotation; motion.scale *= s.scale
                case .beatPulse:
                    motion.scale *= beatPulseScale(layer, beats: beats(layer), at: time.seconds)
                default: break
                }
            }
            return motion
        }
    }
}
