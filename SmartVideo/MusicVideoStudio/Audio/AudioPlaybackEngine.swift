import Foundation
import AVFoundation

extension MusicVideoStudio {
    /// Live audio for the preview: one `AVAudioPlayerNode` per audio clip,
    /// scheduled from the transport time with `AudioScheduling` (the same maths
    /// as the exporter). Follows the master clock; while sound plays, its
    /// hardware position drives the clock back (`masterTime`).
    final class AudioPlaybackEngine: TransportObserver {
        private struct Track {
            let node: AVAudioPlayerNode
            let file: AVAudioFile
            var layer: AudioLayer
        }

        private let engine = AVAudioEngine()
        private var tracks: [UUID: Track] = [:]
        private var isPlaying = false
        private var startedAt = ProjectTime.zero
        private var currentTime = ProjectTime.zero
        private var mediaURL: ((AudioLayer) -> URL)?
        private var observers: [NSObjectProtocol] = []

        /// Called when the system takes audio away (call, route change, engine reset).
        var onInterruption: (() -> Void)?
        private(set) var lastError: String?

        init() {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self?.onInterruption?()
            })
            observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                self?.onInterruption?()
            })
            observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                guard let self, self.isPlaying else { return }
                self.onInterruption?()
            })
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            engine.stop()
        }

        // MARK: Project sync

        /// Align the engine with the project's audio clips. Cheap to call after every edit.
        func update(audios: [AudioLayer], mediaURL: @escaping (AudioLayer) -> URL, time: ProjectTime) {
            self.mediaURL = mediaURL
            let wanted = Set(audios.map(\.core.id))
            for (id, track) in tracks where !wanted.contains(id) {
                track.node.stop()
                engine.detach(track.node)
                tracks[id] = nil
            }
            for layer in audios {
                if var track = tracks[layer.core.id] {
                    let moved = placementKey(track.layer) != placementKey(layer)
                    track.layer = layer
                    tracks[layer.core.id] = track
                    if moved, isPlaying { restart(layer.core.id, at: currentTime) }
                    else if moved { track.node.stop() }
                    continue
                }
                guard let file = try? AVAudioFile(forReading: mediaURL(layer)) else { continue }
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
                tracks[layer.core.id] = Track(node: node, file: file, layer: layer)
                if isPlaying { restart(layer.core.id, at: currentTime) }
            }
            applyVolumes(at: currentTime)
        }

        private func placementKey(_ layer: AudioLayer) -> [Double] {
            [layer.core.start.seconds, layer.core.duration.seconds, layer.sourceStart, layer.loops ? 1 : 0]
        }

        // MARK: Scheduling

        private func schedule(_ track: Track, from time: ProjectTime) {
            let rate = track.file.processingFormat.sampleRate
            let segments = AudioScheduling.segments(layer: track.layer, from: time, sampleRate: rate, fileFrames: track.file.length)
            for (index, segment) in segments.enumerated() {
                let at: AVAudioTime? = index == 0 && segment.delay > 0.0005
                    ? AVAudioTime(sampleTime: AVAudioFramePosition((segment.delay * rate).rounded()), atRate: rate) : nil
                track.node.scheduleSegment(track.file, startingFrame: segment.startFrame,
                                           frameCount: AVAudioFrameCount(segment.frameCount), at: at)
            }
        }

        private func restart(_ id: UUID, at time: ProjectTime) {
            guard let track = tracks[id] else { return }
            track.node.stop()
            schedule(track, from: time)
            track.node.volume = Float(AudioEnvelope.gain(track.layer, at: time))
            if engine.isRunning { track.node.play() }
        }

        private func applyVolumes(at time: ProjectTime) {
            for track in tracks.values {
                track.node.volume = Float(AudioEnvelope.gain(track.layer, at: time))
            }
        }

        private func startEngine() -> Bool {
            if engine.isRunning { return true }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
                engine.prepare()
                try engine.start()
                lastError = nil
                return true
            } catch {
                lastError = "Không phát được âm thanh: \(error.localizedDescription)"
                return false
            }
        }

        // MARK: TransportObserver

        func transportDidStart(at time: ProjectTime) {
            currentTime = time
            startedAt = time
            isPlaying = true
            guard !tracks.isEmpty, startEngine() else { return }
            for id in tracks.keys { restart(id, at: time) }
        }

        func transportDidStop() {
            isPlaying = false
            for track in tracks.values { track.node.stop() }
            if engine.isRunning { engine.pause() }
        }

        func transportDidSeek(to time: ProjectTime, isPlaying playing: Bool) {
            currentTime = time
            startedAt = time
            for track in tracks.values { track.node.stop() }
            applyVolumes(at: time)
            if playing, !tracks.isEmpty, startEngine() {
                isPlaying = true
                for id in tracks.keys { restart(id, at: time) }
            }
        }

        func transportTick(at time: ProjectTime) {
            currentTime = time
            applyVolumes(at: time)         // fades follow the clock
        }

        /// Project time according to the audio hardware, nil before sound is rendering.
        func masterTime() -> ProjectTime? {
            guard isPlaying, engine.isRunning,
                  let node = tracks.values.first?.node,
                  let last = node.lastRenderTime,
                  let player = node.playerTime(forNodeTime: last),
                  player.isSampleTimeValid, player.sampleRate > 0, player.sampleTime >= 0 else { return nil }
            return startedAt + ProjectTime(seconds: Double(player.sampleTime) / player.sampleRate)
        }
    }
}
