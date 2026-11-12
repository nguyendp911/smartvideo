import Foundation

enum ProjectAudioLane {
    case music
    case narration
}

/// Shared source/time mapping and audio-gain automation for the two project
/// tracks (music and narration). Used by export, live preview and tests.
enum ProjectAudioTrackMath {
    static func safeStart(_ start: Double, projectDuration: Double) -> Double {
        let end = projectDuration.isFinite ? max(0, projectDuration) : 0
        return min(end, max(0, start.isFinite ? start : 0))
    }

    static func musicDuration(
        projectDuration: Double, timelineStart: Double,
        fileDuration: Double, sourceStart: Double,
        highlightDuration: Double, repeats: Bool
    ) -> Double {
        guard projectDuration.isFinite, projectDuration > 0,
              fileDuration.isFinite, fileDuration > 0.05 else { return 0 }
        let start = safeStart(timelineStart, projectDuration: projectDuration)
        let remaining = max(0, projectDuration - start)
        let from = min(max(0, sourceStart.isFinite ? sourceStart : 0),
                       max(0, fileDuration - 0.05))
        let available = fileDuration - from
        let length = highlightDuration.isFinite && highlightDuration > 0
            ? min(available, highlightDuration) : available
        return repeats ? remaining : min(remaining, max(0, length))
    }

    static func musicSourceTime(
        projectSecond: Double, timelineStart: Double,
        projectDuration: Double, fileDuration: Double,
        sourceStart: Double, highlightDuration: Double, repeats: Bool
    ) -> Double? {
        guard projectSecond.isFinite, fileDuration.isFinite,
              fileDuration > 0.05 else { return nil }
        let start = safeStart(timelineStart, projectDuration: projectDuration)
        let length = musicDuration(
            projectDuration: projectDuration, timelineStart: start,
            fileDuration: fileDuration, sourceStart: sourceStart,
            highlightDuration: highlightDuration, repeats: repeats
        )
        let local = projectSecond - start
        guard local >= 0, local < length else { return nil }
        let from = min(max(0, sourceStart), max(0, fileDuration - 0.05))
        let segment = highlightDuration > 0
            ? min(fileDuration - from, highlightDuration)
            : fileDuration - from
        return from + (repeats
            ? local.truncatingRemainder(dividingBy: segment) : local)
    }

    /// Optional voice duck is expressed in local seconds of the music track.
    /// Two 150/200ms shoulders match the existing renderer's intention.
    static func duck(
        at second: Double, narrationStart: Double?,
        narrationEnd: Double?
    ) -> Double {
        guard let narrationStart, let narrationEnd,
              narrationEnd > narrationStart else { return 1 }
        let attack = min(0.15, (narrationEnd - narrationStart) / 2)
        let release = min(0.20, (narrationEnd - narrationStart) / 2)
        if second < narrationStart { return 1 }
        if second < narrationStart + attack, attack > 0.001 {
            return 1 - 0.75 * (second - narrationStart) / attack
        }
        if second <= narrationEnd { return 0.25 }
        if second < narrationEnd + release, release > 0.001 {
            return 0.25 + 0.75 * (second - narrationEnd) / release
        }
        return 1
    }

    static func gain(
        localSecond: Double, duration: Double,
        volume: Float, fadeIn: Double, fadeOut: Double,
        keyframes: [AudioGainKeyframe],
        narrationStart: Double? = nil,
        narrationEnd: Double? = nil
    ) -> Float {
        let normal = AudioAutomationMath.gain(
            at: localSecond, duration: duration, volume: volume,
            muted: false, fadeIn: fadeIn, fadeOut: fadeOut,
            frames: keyframes
        )
        return normal * Float(duck(
            at: localSecond, narrationStart: narrationStart,
            narrationEnd: narrationEnd
        ))
    }

    /// Interval-linear AVAudioMix ramps. Generate at most ~400 points:
    /// keyframes are anchors; fade/duck shoulders sampled at 50ms.
    static func points(
        duration: Double, volume: Float, fadeIn: Double, fadeOut: Double,
        keyframes: [AudioGainKeyframe],
        narrationStart: Double? = nil,
        narrationEnd: Double? = nil
    ) -> [(second: Double, gain: Float)] {
        guard duration.isFinite, duration >= 0.05 else { return [] }
        var times = AudioAutomationMath.envelope(
            duration: duration, volume: volume, muted: false,
            fadeIn: fadeIn, fadeOut: fadeOut, frames: keyframes
        ).map(\.second)
        func addShoulder(_ from: Double, _ to: Double) {
            let lo = min(duration, max(0, from))
            let hi = min(duration, max(0, to))
            guard hi > lo else { return }
            let samples = max(1, Int(ceil((hi - lo) / 0.05)))
            for i in 0...samples {
                times.append(lo + Double(i) / Double(samples) * (hi - lo))
            }
        }
        if let narrationStart, let narrationEnd {
            addShoulder(narrationStart, narrationStart + 0.15)
            addShoulder(narrationEnd, narrationEnd + 0.20)
        }
        let quantized = Array(Set(times.map {
            Int((min(duration, max(0, $0)) * 60_000).rounded())
        })).sorted()
        return quantized.map { value in
            let second = Double(value) / 60_000
            return (second: second, gain: gain(
                localSecond: second, duration: duration,
                volume: volume, fadeIn: fadeIn, fadeOut: fadeOut,
                keyframes: keyframes,
                narrationStart: narrationStart,
                narrationEnd: narrationEnd
            ))
        }
    }
}
