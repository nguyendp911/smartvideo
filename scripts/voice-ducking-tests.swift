import Foundation

@main
struct VoiceDuckingTests {
    static func near(_ a: Double, _ b: Double, tolerance: Double = 0.002,
                     _ note: String = "") {
        precondition(a.isFinite && abs(a - b) < tolerance,
                     "Expected \(b) got \(a) \(note)")
    }

    /// 20 ms windows: speech at 0.2 amplitude, background noise 0.001.
    static func levels(_ segments: [(Double, Double, Float)],
                       total: Double) -> [Float] {
        let w = 0.02
        let count = Int(total / w)
        var out = [Float](repeating: 0.001, count: count)
        for (start, end, value) in segments {
            for i in Int(start / w)..<min(count, Int(end / w)) { out[i] = value }
        }
        return out
    }

    static func main() {
        let m = VoiceActivityMath.self

        // 1. Two spoken phrases separated by a long pause stay separate.
        let rms = levels([(1.0, 3.0, 0.2), (6.0, 8.0, 0.18)], total: 10)
        let found = m.intervals(rms: rms)
        precondition(found.count == 2, "expected 2 intervals, got \(found)")
        near(found[0].start, 1.0); near(found[0].end, 3.0)
        near(found[1].start, 6.0); near(found[1].end, 8.0)

        // 2. A short breath between words (<0.45 s) is merged, a click is dropped.
        let merged = m.intervals(rms: levels(
            [(1.0, 2.0, 0.2), (2.3, 3.0, 0.2), (5.0, 5.05, 0.3)], total: 8
        ))
        precondition(merged.count == 1, "got \(merged)")
        near(merged[0].start, 1.0); near(merged[0].end, 3.0)

        // 3. Pure silence and NaN input produce nothing.
        precondition(m.intervals(rms: [Float](repeating: 0.0005, count: 500)).isEmpty)
        precondition(m.intervals(rms: [Float.nan, .infinity, 0]).isEmpty)
        precondition(m.intervals(rms: []).isEmpty)

        // 4. Duck envelope: unity far away, level inside, linear shoulders.
        let iv = [VoiceActivityMath.Interval(start: 10, end: 20)]
        near(m.duckGain(at: 5, intervals: iv, level: 0.25), 1)
        near(m.duckGain(at: 10 - 0.12, intervals: iv, level: 0.25), 1)
        near(m.duckGain(at: 10 - 0.06, intervals: iv, level: 0.25), 0.625)
        near(m.duckGain(at: 10, intervals: iv, level: 0.25), 0.25)
        near(m.duckGain(at: 15, intervals: iv, level: 0.25), 0.25)
        near(m.duckGain(at: 20, intervals: iv, level: 0.25), 0.25)
        near(m.duckGain(at: 20 + 0.175, intervals: iv, level: 0.25), 0.625)
        near(m.duckGain(at: 20.35, intervals: iv, level: 0.25), 1)
        near(m.duckGain(at: 30, intervals: [], level: 0.25), 1)

        // 5. Overlapping shoulders never go ABOVE the lowest requested gain.
        let two = [VoiceActivityMath.Interval(start: 1, end: 2),
                   VoiceActivityMath.Interval(start: 2.2, end: 3)]
        near(m.duckGain(at: 2.1, intervals: two, level: 0.3), 0.3 + 0.7 * 0.1 / 0.35,
             tolerance: 0.01, "inside the short gap")

        // 6. normalized: clamps, sorts, merges and drops empties.
        let n = m.normalized([
            .init(start: 8, end: 12), .init(start: -3, end: 2),
            .init(start: 1, end: 4), .init(start: 5, end: 5),
            .init(start: .nan, end: 3)
        ], duration: 10)
        precondition(n == [.init(start: 0, end: 4), .init(start: 8, end: 10)],
                     "got \(n)")

        // 7. shifted + keyTimes
        let s = m.shifted(iv, by: -4)
        near(s[0].start, 6); near(s[0].end, 16)
        let keys = m.keyTimes(iv)
        precondition(keys.count == 4)
        near(keys[0], 9.88); near(keys[3], 20.35)

        // 8. Track math: smart intervals override the flat narration duck,
        //    and silence inside the narration leaves the music untouched.
        let flat = ProjectAudioTrackMath.duck(
            at: 5, narrationStart: 0, narrationEnd: 20
        )
        near(flat, 0.25, tolerance: 0.001, "legacy duck inside file")
        let smart = ProjectAudioTrackMath.duck(
            at: 5, narrationStart: 0, narrationEnd: 20,
            speechIntervals: iv, duckLevel: 0.4
        )
        near(smart, 1, tolerance: 0.001, "pause before speech must not duck")
        let inside = ProjectAudioTrackMath.duck(
            at: 15, narrationStart: 0, narrationEnd: 20,
            speechIntervals: iv, duckLevel: 0.4
        )
        near(inside, 0.4, tolerance: 0.001)
        let none = ProjectAudioTrackMath.duck(
            at: 15, narrationStart: 0, narrationEnd: 20,
            speechIntervals: [], duckLevel: 0.4
        )
        near(none, 1, tolerance: 0.001, "narration without speech")

        // 9. Envelope points: bounded, monotonic and hit the level inside speech.
        let pts = ProjectAudioTrackMath.points(
            duration: 30, volume: 1, fadeIn: 0, fadeOut: 0, keyframes: [],
            speechIntervals: iv, duckLevel: 0.25
        )
        precondition(pts.count <= 60, "too many points: \(pts.count)")
        for (a, b) in zip(pts, pts.dropFirst()) {
            precondition(b.second > a.second, "points must be increasing")
        }
        let atTwelve = pts.first { abs($0.second - 12) < 0.5 }
        // no point is exactly at 12, but ramps are linear between 10 and 20
        precondition(atTwelve == nil || abs(Double(atTwelve!.gain) - 0.25) < 0.01)
        let tenPoint = pts.first { abs($0.second - 10) < 0.001 }!
        near(Double(tenPoint.gain), 0.25, tolerance: 0.01)

        // 10. Level clamping in settings.
        near(VoiceDuckSettings(smart: true, level: -4).clampedLevel, 0.05)
        near(VoiceDuckSettings(smart: true, level: 9).clampedLevel, 1)
        near(VoiceDuckSettings(smart: true, level: .nan).clampedLevel, 0.25)

        // 11. Codable round-trip keeps the values.
        let data = try! JSONEncoder().encode(VoiceDuckSettings(smart: false, level: 0.5))
        let back = try! JSONDecoder().decode(VoiceDuckSettings.self, from: data)
        precondition(back == VoiceDuckSettings(smart: false, level: 0.5))

        print("voice ducking tests passed")
    }
}
