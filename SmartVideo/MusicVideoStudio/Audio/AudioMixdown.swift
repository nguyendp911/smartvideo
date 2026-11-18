import Foundation
import AVFoundation

extension MusicVideoStudio {
    /// Renders every audio clip of the project to one file, OFFLINE, with the
    /// same scheduling and envelope maths as the live preview. The export never
    /// depends on a live audio device.
    enum AudioMixdown {
        static let sampleRate = 44_100.0
        static let chunk: AVAudioFrameCount = 1_024

        /// Returns false when the project has no audible audio clip (nothing written).
        @discardableResult
        static func render(project: VideoProject, mediaURL: (AudioLayer) -> URL, to url: URL,
                           duration: ProjectTime? = nil, progress: ((Double) -> Void)? = nil) throws -> Bool {
            let layers = project.audios.filter { $0.core.isVisible && $0.volume > 0 }
            guard !layers.isEmpty else { return false }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { throw AudioError.unreadable }
            let engine = AVAudioEngine()
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunk)

            var nodes: [(node: AVAudioPlayerNode, layer: AudioLayer, file: AVAudioFile)] = []
            for layer in layers {
                guard let file = try? AVAudioFile(forReading: mediaURL(layer)) else { continue }
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
                nodes.append((node, layer, file))
            }
            guard !nodes.isEmpty else { return false }
            try engine.start()

            for entry in nodes {
                let rate = entry.file.processingFormat.sampleRate
                let segments = AudioScheduling.segments(layer: entry.layer, from: .zero, sampleRate: rate, fileFrames: entry.file.length)
                for (index, segment) in segments.enumerated() {
                    let at: AVAudioTime? = index == 0 && segment.delay > 0
                        ? AVAudioTime(sampleTime: AVAudioFramePosition((segment.delay * rate).rounded()), atRate: rate) : nil
                    entry.node.scheduleSegment(entry.file, startingFrame: segment.startFrame,
                                               frameCount: AVAudioFrameCount(segment.frameCount), at: at)
                }
                entry.node.play()
            }

            try? FileManager.default.removeItem(at: url)
            let output = try AVAudioFile(forWriting: url, settings: format.settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunk) else { throw AudioError.unreadable }

            let total = Int64(((duration ?? project.duration).seconds * sampleRate).rounded())
            var rendered: Int64 = 0
            var stalls = 0
            while rendered < total {
                try Task.checkCancellation()
                let now = ProjectTime(seconds: Double(rendered) / sampleRate)
                for entry in nodes { entry.node.volume = Float(AudioEnvelope.gain(entry.layer, at: now)) }
                let frames = AVAudioFrameCount(min(Int64(chunk), total - rendered))
                switch try engine.renderOffline(frames, to: buffer) {
                case .success:
                    try output.write(from: buffer)
                    rendered += Int64(buffer.frameLength)
                    stalls = 0
                    if rendered % (Int64(chunk) * 64) < Int64(chunk) { progress?(Double(rendered) / Double(max(1, total))) }
                case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                    stalls += 1
                    if stalls > 200 { throw AudioError.unreadable }
                case .error:
                    throw AudioError.unreadable
                @unknown default:
                    throw AudioError.unreadable
                }
            }
            for entry in nodes { entry.node.stop() }
            engine.stop()
            progress?(1)
            return true
        }
    }
}
