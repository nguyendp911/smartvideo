import Foundation

extension MusicVideoStudio {
    /// The master playback clock as a pure value: every track, animation and
    /// the (later) audio engine read the same `time`. No timers live here;
    /// `PlaybackEngine` feeds it real elapsed time from one display link, and
    /// tests feed it simulated time.
    struct TransportState: Equatable {
        var time = ProjectTime.zero
        var duration = VideoProject.minimumDuration
        var fps = 30
        var isPlaying = false
        var loops = false
        var rate = 1.0

        /// The instant actually rendered: floored to a whole frame so playback
        /// and export show identical frames.
        var frameTime: ProjectTime { time.quantized(fps: fps) }

        var progress: Double { duration.ticks > 0 ? Double(time.ticks) / Double(duration.ticks) : 0 }

        mutating func setDuration(_ newDuration: ProjectTime, fps newFPS: Int) {
            duration = max(newDuration, ProjectTime(ticks: 1))
            fps = ProjectTime.supportedFrameRates.contains(newFPS) ? newFPS : fps
            if time > duration { time = duration; if !loops { isPlaying = false } }
        }

        mutating func seek(to target: ProjectTime) {
            time = target.clamped(.zero, duration)
        }

        mutating func play() {
            if time >= duration { time = .zero }       // restart from the beginning at the end
            isPlaying = true
        }

        mutating func pause() { isPlaying = false }

        mutating func togglePlay() { isPlaying ? pause() : play() }

        /// Step whole frames (pauses playback).
        mutating func step(frames: Int) {
            pause()
            let base = frameTime
            let moved = ProjectTime(ticks: base.ticks + Int64(frames) * ProjectTime.ticksPerFrame(fps: fps))
            time = moved.clamped(.zero, duration)
        }

        mutating func goToStart() { time = .zero }

        mutating func goToEnd() { pause(); time = duration }

        /// Advance by real elapsed seconds. Returns true when playback just
        /// stopped at the end.
        @discardableResult
        mutating func advance(by seconds: Double) -> Bool {
            guard isPlaying, seconds.isFinite, seconds > 0 else { return false }
            let next = time + ProjectTime(seconds: seconds * rate)
            if next < duration {
                time = next
                return false
            }
            if loops, duration.ticks > 0 {
                time = ProjectTime(ticks: (next.ticks - duration.ticks) % duration.ticks)
                return false
            }
            time = duration
            isPlaying = false
            return true
        }
    }
}
