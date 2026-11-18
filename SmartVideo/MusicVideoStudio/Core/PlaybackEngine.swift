import Foundation
import QuartzCore
import Combine

extension MusicVideoStudio {
    /// Anything that must follow the master clock (the audio engine today;
    /// others later) implements this instead of running its own timer.
    protocol TransportObserver: AnyObject {
        func transportDidStart(at time: ProjectTime)
        func transportDidStop()
        func transportDidSeek(to time: ProjectTime, isPlaying: Bool)
        func transportTick(at time: ProjectTime)
        /// When the observer has a more accurate clock (the audio hardware), the
        /// transport follows it so picture and sound can never drift apart.
        func masterTime() -> ProjectTime?
    }

    /// ONE master clock for the whole studio: a single `CADisplayLink` advances
    /// a `TransportState`; photos, text and (in later phases) audio, vinyl,
    /// lyrics and visualizers all derive their picture from `state.frameTime`.
    /// There are no per-track timers, so nothing can drift after a seek or pause.
    /// Used from the main thread only (UI and display link).
    final class PlaybackEngine: ObservableObject {
        @Published private(set) var state = TransportState()

        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        weak var observer: TransportObserver?

        var isPlaying: Bool { state.isPlaying }
        var time: ProjectTime { state.time }

        func configure(duration: ProjectTime, fps: Int) { update(seek: false) { $0.setDuration(duration, fps: fps) } }
        func play() { update(seek: false) { $0.play() } }
        func pause() { update(seek: false) { $0.pause() } }
        func toggle() { update(seek: false) { $0.togglePlay() } }
        func seek(to time: ProjectTime) { update(seek: true) { $0.seek(to: time) } }
        func step(frames: Int) { update(seek: true) { $0.step(frames: frames) } }
        func goToStart() { update(seek: true) { $0.goToStart() } }
        func goToEnd() { update(seek: true) { $0.goToEnd() } }
        func setLoops(_ enabled: Bool) { update(seek: false) { $0.loops = enabled } }

        private func update(seek: Bool, _ change: (inout TransportState) -> Void) {
            let before = state
            var next = state
            change(&next)
            if next != state { state = next }
            if next.isPlaying { startLink() } else { stopLink() }
            if !before.isPlaying && next.isPlaying {
                observer?.transportDidStart(at: next.time)
            } else if before.isPlaying && !next.isPlaying {
                observer?.transportDidStop()
            } else if seek || next.time != before.time {
                observer?.transportDidSeek(to: next.time, isPlaying: next.isPlaying)
            }
        }

        private func startLink() {
            guard displayLink == nil else { return }
            lastTimestamp = 0
            let proxy = DisplayLinkProxy(engine: self)
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 60, preferred: Float(state.fps))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private func stopLink() {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
        }

        fileprivate func tick(timestamp: CFTimeInterval) {
            // Real elapsed time between frames; a long gap (app suspended) is capped.
            let elapsed = lastTimestamp == 0 ? 0 : min(0.1, max(0, timestamp - lastTimestamp))
            lastTimestamp = timestamp
            let before = state
            var next = state
            next.advance(by: elapsed)
            // The audio hardware clock is the master while sound is playing.
            if next.isPlaying, let audioTime = observer?.masterTime() {
                next.time = audioTime.clamped(.zero, next.duration)
            }
            state = next
            if !next.isPlaying {
                stopLink()
                observer?.transportDidStop()
            } else if next.time < before.time {
                observer?.transportDidSeek(to: next.time, isPlaying: true)       // the loop wrapped
            } else {
                observer?.transportTick(at: next.time)
            }
        }

        deinit { displayLink?.invalidate() }
    }

    /// CADisplayLink retains its target, so it gets a weak proxy.
    private final class DisplayLinkProxy: NSObject {
        weak var engine: PlaybackEngine?
        init(engine: PlaybackEngine) { self.engine = engine }
        @objc func fire(_ link: CADisplayLink) { engine?.tick(timestamp: link.timestamp) }
    }
}
