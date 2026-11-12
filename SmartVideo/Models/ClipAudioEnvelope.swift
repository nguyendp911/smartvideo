import Foundation

/// Source-audio automation for a single timeline video clip.
/// All times are local *rendered* seconds, after trimming and retiming.
/// It is reused by the AVAudioMix exporter and the quick AVPlayer preview.
enum ClipAudioEnvelope {
    struct Point {
        let second: Double
        let gain: Float
    }

    static func safeVolume(_ volume: Float) -> Float {
        volume.isFinite ? min(1, max(0, volume)) : 1
    }

    static func safeFade(_ seconds: Double) -> Double {
        seconds.isFinite ? min(3, max(0, seconds)) : 0
    }

    static func gain(
        at second: Double, duration: Double,
        volume: Float, muted: Bool, fadeIn: Double, fadeOut: Double,
        incomingOverlap: Double = 0, outgoingOverlap: Double = 0
    ) -> Float {
        guard duration.isFinite, duration > 0, second.isFinite,
              second >= 0, second <= duration, !muted else { return 0 }
        let t = min(duration, max(0, second))
        let inLength = min(safeFade(fadeIn), duration * 0.48)
        let outLength = min(safeFade(fadeOut), duration * 0.48)
        let crossIn = min(max(0, incomingOverlap.isFinite ?
            incomingOverlap : 0), duration * 0.48)
        let crossOut = min(max(0, outgoingOverlap.isFinite ?
            outgoingOverlap : 0), duration * 0.48)

        func rising(_ length: Double) -> Double {
            length > 0.0001 ? min(1, max(0, t / length)) : 1
        }
        func falling(_ length: Double) -> Double {
            length > 0.0001 ?
                min(1, max(0, (duration - t) / length)) : 1
        }
        let result = Double(safeVolume(volume)) *
            rising(inLength) * falling(outLength) *
            rising(crossIn) * falling(crossOut)
        return Float(min(1, max(0, result)))
    }

    /// Only the fade regions need sampling. Interior regions use a single
    /// constant gain, so even a very long clip produces O(1) automation nodes.
    /// Overlapping user fades + transition crossfades are approximated with
    /// <= 50ms linear ramps to avoid the erroneous overriding of ramps.
    static func points(
        duration: Double, volume: Float, muted: Bool,
        fadeIn: Double, fadeOut: Double,
        incomingOverlap: Double = 0, outgoingOverlap: Double = 0
    ) -> [Point] {
        guard duration.isFinite, duration > 0.001 else { return [] }
        let incoming = min(duration * 0.48,
                           max(safeFade(fadeIn), max(0, incomingOverlap)))
        let outgoing = min(duration * 0.48,
                           max(safeFade(fadeOut), max(0, outgoingOverlap)))
        let tick = 0.05
        var values: [Double] = [0, duration]

        // In fade and transition intervals may intersect; sample at 50ms.
        if incoming > 0 {
            let count = max(1, Int(ceil(incoming / tick)))
            for i in 0...count {
                values.append(incoming * Double(i) / Double(count))
            }
        }
        if outgoing > 0 {
            let count = max(1, Int(ceil(outgoing / tick)))
            for i in 0...count {
                values.append(duration - outgoing * Double(i) / Double(count))
            }
        }
        let sorted = Array(Set(values.map { Int(($0 * 60_000).rounded()) }))
            .sorted()
            .map { Double($0) / 60_000 }
        return sorted.map {
            Point(second: $0, gain: gain(
                at: $0, duration: duration, volume: volume, muted: muted,
                fadeIn: fadeIn, fadeOut: fadeOut,
                incomingOverlap: incomingOverlap,
                outgoingOverlap: outgoingOverlap
            ))
        }
    }
}
