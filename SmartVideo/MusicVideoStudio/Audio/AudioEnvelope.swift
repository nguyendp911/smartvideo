import Foundation

extension MusicVideoStudio {
    /// Volume of an audio clip over time. The eye toggle of the layer MUTES it.
    enum AudioEnvelope {
        /// Linear fade multiplier 0...1 at `local` seconds into a clip of `duration`.
        /// Fades that together exceed the clip are scaled down proportionally.
        static func fade(local: Double, duration: Double, fadeIn: Double, fadeOut: Double) -> Double {
            guard duration > 0, local.isFinite, local >= 0, local <= duration else { return 0 }
            var fi = max(0, fadeIn.isFinite ? fadeIn : 0), fo = max(0, fadeOut.isFinite ? fadeOut : 0)
            if fi + fo > duration { let k = duration / (fi + fo); fi *= k; fo *= k }
            var gain = 1.0
            if fi > 0, local < fi { gain = min(gain, local / fi) }
            if fo > 0, local > duration - fo { gain = min(gain, (duration - local) / fo) }
            return min(1, max(0, gain))
        }

        static func gain(_ layer: AudioLayer, at time: ProjectTime) -> Double {
            guard layer.core.isVisible, layer.core.range.contains(time) else { return 0 }
            let local = (time - layer.core.start).seconds
            let volume = min(AudioLayer.volumeRange.upperBound, max(0, layer.volume.isFinite ? layer.volume : 1))
            return volume * fade(local: local, duration: layer.core.duration.seconds,
                                 fadeIn: layer.fadeIn, fadeOut: layer.fadeOut)
        }
    }
}
