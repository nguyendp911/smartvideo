import Foundation

@main
struct ClipAudioEnvelopeTests {
    static func near(_ actual: Double, _ expected: Double,
                     tolerance: Double = 0.002) {
        precondition(actual.isFinite && abs(actual - expected) <= tolerance,
                     "Expected \(expected), got \(actual)")
    }

    static func main() {
        func sample(_ second: Double, _ duration: Double = 10,
                    volume: Float = 1, muted: Bool = false,
                    fadeIn: Double = 0, fadeOut: Double = 0,
                    inOverlap: Double = 0,
                    outOverlap: Double = 0) -> Double {
            Double(ClipAudioEnvelope.gain(
                at: second, duration: duration,
                volume: volume, muted: muted,
                fadeIn: fadeIn, fadeOut: fadeOut,
                incomingOverlap: inOverlap,
                outgoingOverlap: outOverlap
            ))
        }

        near(sample(2), 1)
        near(sample(2, volume: 0.25), 0.25)
        near(sample(2, muted: true), 0)
        near(sample(0, fadeIn: 2), 0)
        near(sample(1, fadeIn: 2), 0.5)
        near(sample(2, fadeIn: 2), 1)
        near(sample(8, fadeOut: 2), 1)
        near(sample(9, fadeOut: 2), 0.5)
        near(sample(10, fadeOut: 2), 0)
        near(sample(0.25, inOverlap: 0.5), 0.5)
        near(sample(9.75, outOverlap: 0.5), 0.5)
        // User fades multiply with transition fades without overriding one.
        near(sample(0.25, fadeIn: 1, inOverlap: 0.5), 0.125)
        near(sample(9.75, fadeOut: 1, outOverlap: 0.5), 0.125)
        near(sample(0.5, 1, fadeIn: 3), 1)
        near(sample(0.24, 1, fadeIn: 3), 0.5)
        near(sample(1, 0.2, fadeOut: 3), 0)
        near(sample(-0.1), 0)
        near(sample(12), 0)
        precondition(ClipAudioEnvelope.safeVolume(.nan) == 1)
        precondition(ClipAudioEnvelope.safeVolume(3) == 1)
        precondition(ClipAudioEnvelope.safeFade(.infinity) == 0)
        precondition(ClipAudioEnvelope.safeFade(10) == 3)
        let nodes = ClipAudioEnvelope.points(
            duration: 7200, volume: 0.8, muted: false,
            fadeIn: 1, fadeOut: 2, incomingOverlap: 0.45,
            outgoingOverlap: 0.45
        )
        precondition(nodes.count < 100,
                     "Long clips must not generate per-frame ramps")
        near(nodes.first?.second ?? -1, 0)
        near(nodes.last?.second ?? -1, 7200)
        for (a, b) in zip(nodes, nodes.dropFirst()) {
            precondition(a.second < b.second, "Strictly ascending nodes")
            precondition(a.gain >= 0 && a.gain <= 1)
            precondition(b.gain >= 0 && b.gain <= 1)
        }
        let mutedNodes = ClipAudioEnvelope.points(
            duration: 10, volume: 1, muted: true,
            fadeIn: 0.5, fadeOut: 0.5
        )
        precondition(mutedNodes.allSatisfy { $0.gain == 0 })
        print("PASS: per-clip audio volume, mute, fades, transitions, old defaults and bounded automation")
    }
}
