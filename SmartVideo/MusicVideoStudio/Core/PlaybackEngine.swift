import Foundation
import QuartzCore
import Combine

extension MusicVideoStudio {
    /// ONE master clock for the whole studio: a single `CADisplayLink` advances
    /// a `TransportState`; photos, text and (in later phases) audio, vinyl,
    /// lyrics and visualizers all derive their picture from `state.frameTime`.
    /// There are no per-track timers, so nothing can drift after a seek or pause.
    /// Used from the main thread only (UI and display link).
    final class PlaybackEngine: ObservableObject {
        @Published private(set) var state = TransportState()

        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0

        var isPlaying: Bool { state.isPlaying }
        var time: ProjectTime { state.time }

        func configure(duration: ProjectTime, fps: Int) { update { $0.setDuration(duration, fps: fps) } }
        func play() { update { $0.play() } }
        func pause() { update { $0.pause() } }
        func toggle() { update { $0.togglePlay() } }
        func seek(to time: ProjectTime) { update { $0.seek(to: time) } }
        func step(frames: Int) { update { $0.step(frames: frames) } }
        func goToStart() { update { $0.goToStart() } }
        func goToEnd() { update { $0.goToEnd() } }
        func setLoops(_ enabled: Bool) { update { $0.loops = enabled } }

        private func update(_ change: (inout TransportState) -> Void) {
            var next = state
            change(&next)
            if next != state { state = next }
            if next.isPlaying { startLink() } else { stopLink() }
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
            var next = state
            next.advance(by: elapsed)
            state = next
            if !next.isPlaying { stopLink() }
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
