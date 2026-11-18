import Foundation

extension MusicVideoStudio {
    /// One contiguous run of the file to hand to an `AVAudioPlayerNode`.
    struct AudioSegment: Equatable {
        /// Seconds from "now" until the segment starts (only the first one can be > 0).
        var delay: Double
        var startFrame: Int64
        var frameCount: Int64
    }

    /// Pure scheduling maths shared by live playback and the offline mixdown
    /// used for export, so what you hear is what gets exported.
    enum AudioScheduling {
        static let maxSegments = 500

        /// Position inside the FILE (seconds) that plays at project `time`, or nil outside the clip.
        static func sourcePosition(layer: AudioLayer, at time: ProjectTime) -> Double? {
            guard layer.core.range.contains(time) else { return nil }
            let span = layer.availableSource
            guard span > 0 else { return nil }
            let local = (time - layer.core.start).seconds
            if layer.loops { return layer.sourceStart + local.truncatingRemainder(dividingBy: span) }
            return local < span ? layer.sourceStart + local : nil
        }

        /// What to schedule when playback (re)starts at `now`.
        static func segments(layer: AudioLayer, from now: ProjectTime, sampleRate: Double, fileFrames: Int64) -> [AudioSegment] {
            let clipEnd = layer.core.end
            guard now < clipEnd, sampleRate > 0, fileFrames > 0 else { return [] }
            let span = min(layer.availableSource, Double(fileFrames) / sampleRate)
            guard span > 0.001 else { return [] }

            let delay = max(0, (layer.core.start - now).seconds)
            let offset = max(0, (now - layer.core.start).seconds)          // already into the clip
            let clipLength = layer.core.duration.seconds
            var remaining = clipLength - offset
            guard remaining > 0.0005 else { return [] }

            func frames(_ seconds: Double) -> Int64 { Int64((seconds * sampleRate).rounded()) }
            var segments: [AudioSegment] = []
            var positionInPass = layer.loops ? offset.truncatingRemainder(dividingBy: span) : offset
            if !layer.loops && offset >= span { return [] }
            var first = true
            while remaining > 0.0005, segments.count < maxSegments {
                let length = min(span - positionInPass, remaining)
                guard length > 0.0005 else { break }
                let start = min(fileFrames - 1, frames(layer.sourceStart + positionInPass))
                let count = min(fileFrames - start, max(1, frames(length)))
                segments.append(AudioSegment(delay: first ? delay : 0, startFrame: start, frameCount: count))
                first = false
                remaining -= length
                positionInPass = 0
                if !layer.loops { break }
            }
            return segments
        }
    }
}
