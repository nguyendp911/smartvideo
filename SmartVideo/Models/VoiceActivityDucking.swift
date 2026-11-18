import Foundation

/// User-facing auto-ducking options for background music under narration.
struct VoiceDuckSettings: Codable, Equatable {
    /// true: the music dips only while speech is really present in the
    /// narration file. false: legacy behaviour (flat 25% for the whole file).
    var smart: Bool = true
    /// Remaining music gain while speech is present.
    var level: Double = 0.25

    var clampedLevel: Double {
        level.isFinite ? min(1, max(0.05, level)) : 0.25
    }

    static let legacy = VoiceDuckSettings(smart: false, level: 0.25)
}

/// Speech-activity detection and ducking envelopes. Pure Foundation so it can
/// be unit-tested without AVFoundation; the audio decoding lives in
/// `VoiceActivityAnalyzer`.
enum VoiceActivityMath {
    struct Interval: Equatable, Codable {
        var start: Double
        var end: Double
    }

    /// Music starts dipping slightly BEFORE speech so the first syllable is
    /// never masked; it recovers more slowly to avoid pumping.
    static let attack = 0.12
    static let release = 0.35
    static let maxIntervals = 600

    /// Turn RMS levels (one per `windowSeconds`) into speech intervals using an
    /// adaptive threshold between the noise floor and the speech peak.
    static func intervals(
        rms: [Float], windowSeconds: Double = 0.02,
        minSpeech: Double = 0.15, mergeGap: Double = 0.45
    ) -> [Interval] {
        guard windowSeconds > 0, !rms.isEmpty else { return [] }
        let values = rms.map { $0.isFinite ? max(0, Double($0)) : 0 }
        let sorted = values.sorted()
        func percentile(_ p: Double) -> Double {
            sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))]
        }
        let floor = percentile(0.10)
        let peak = percentile(0.95)
        guard peak >= 0.004 else { return [] }
        let threshold = max(0.004, floor + 0.2 * (peak - floor))

        var runs: [Interval] = []
        var runStart: Int?
        for (index, value) in values.enumerated() {
            if value >= threshold {
                if runStart == nil { runStart = index }
            } else if let begin = runStart {
                runs.append(Interval(start: Double(begin) * windowSeconds,
                                     end: Double(index) * windowSeconds))
                runStart = nil
            }
        }
        if let begin = runStart {
            runs.append(Interval(start: Double(begin) * windowSeconds,
                                 end: Double(values.count) * windowSeconds))
        }

        var merged: [Interval] = []
        for run in runs {
            if var last = merged.last, run.start - last.end <= mergeGap {
                last.end = run.end
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        return merged.filter { $0.end - $0.start >= minSpeech }
    }

    /// Sort, clamp to [0, duration], drop empties, merge overlaps, cap count.
    static func normalized(_ intervals: [Interval], duration: Double) -> [Interval] {
        guard duration.isFinite, duration > 0 else { return [] }
        let cleaned = intervals
            .filter { $0.start.isFinite && $0.end.isFinite }
            .map { Interval(start: min(duration, max(0, $0.start)),
                            end: min(duration, max(0, $0.end))) }
            .filter { $0.end - $0.start > 0.001 }
            .sorted { $0.start < $1.start }
        var out: [Interval] = []
        for item in cleaned {
            if var last = out.last, item.start <= last.end {
                last.end = max(last.end, item.end)
                out[out.count - 1] = last
            } else {
                out.append(item)
            }
        }
        return Array(out.prefix(maxIntervals))
    }

    static func shifted(_ intervals: [Interval], by delta: Double) -> [Interval] {
        intervals.map { Interval(start: $0.start + delta, end: $0.end + delta) }
    }

    /// Music gain multiplier (1 = untouched, `level` = fully ducked).
    static func duckGain(
        at second: Double, intervals: [Interval], level: Double,
        attack: Double = VoiceActivityMath.attack,
        release: Double = VoiceActivityMath.release
    ) -> Double {
        let level = level.isFinite ? min(1, max(0, level)) : 0.25
        var gain = 1.0
        for item in intervals {
            if second < item.start - attack || second > item.end + release { continue }
            let value: Double
            if second < item.start {
                value = 1 - (1 - level) * (second - (item.start - attack)) / attack
            } else if second <= item.end {
                value = level
            } else {
                value = level + (1 - level) * (second - item.end) / release
            }
            gain = min(gain, value)
        }
        return gain
    }

    /// Times at which the envelope changes slope. Linear volume ramps between
    /// these four points per interval reproduce the shoulders exactly, so no
    /// dense sampling (and no huge AVAudioMix) is needed.
    static func keyTimes(
        _ intervals: [Interval],
        attack: Double = VoiceActivityMath.attack,
        release: Double = VoiceActivityMath.release
    ) -> [Double] {
        intervals.flatMap {
            [$0.start - attack, $0.start, $0.end, $0.end + release]
        }
    }
}
