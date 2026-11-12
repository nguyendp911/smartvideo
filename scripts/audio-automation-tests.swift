import Foundation

@main
struct AudioAutomationTests {
    static func near(_ value: Double, _ expected: Double,
                     tolerance: Double = 0.001) {
        precondition(value.isFinite && abs(value - expected) < tolerance,
                     "Wanted \(expected), got \(value)")
    }

    static func main() throws {
        let empty: [AudioGainKeyframe] = []
        near(Double(AudioAutomationMath.factor(at: 0.3, frames: empty)), 1)

        let frames: [AudioGainKeyframe] = [
            AudioGainKeyframe(progress: 0.25, gain: 0.2),
            AudioGainKeyframe(progress: 0.75, gain: 0.8)
        ]
        near(Double(AudioAutomationMath.factor(at: 0, frames: frames)), 1)
        near(Double(AudioAutomationMath.factor(at: 0.25, frames: frames)), 0.2)
        near(Double(AudioAutomationMath.factor(at: 0.5, frames: frames)), 0.5)
        near(Double(AudioAutomationMath.factor(at: 0.75, frames: frames)), 0.8)
        near(Double(AudioAutomationMath.factor(at: 1, frames: frames)), 1)

        near(Double(AudioAutomationMath.gain(
            at: 5, duration: 10, volume: 0.8, muted: false,
            fadeIn: 0, fadeOut: 0, frames: frames
        )), 0.4)
        near(Double(AudioAutomationMath.gain(
            at: 0.5, duration: 10, volume: 1, muted: false,
            fadeIn: 1, fadeOut: 0, frames: empty
        )), 0.5)
        near(Double(AudioAutomationMath.gain(
            at: 5, duration: 10, volume: 1, muted: true,
            fadeIn: 0, fadeOut: 0, frames: frames
        )), 0)

        let nodes = AudioAutomationMath.envelope(
            duration: 90_000, volume: 0.8, muted: false,
            fadeIn: 1.5, fadeOut: 1.5, frames: frames
        )
        precondition(nodes.count < 100)
        near(nodes.first!.second, 0)
        near(nodes.last!.second, 90_000)
        for (a, b) in zip(nodes, nodes.dropFirst()) {
            precondition(a.second < b.second)
            precondition(a.gain >= 0 && a.gain <= 1)
        }

        let left = AudioAutomationMath.slice(
            frames, start: 0, end: 0.5
        )
        let right = AudioAutomationMath.slice(
            frames, start: 0.5, end: 1
        )
        near(Double(AudioAutomationMath.factor(at: 1, frames: left)), 0.5)
        near(Double(AudioAutomationMath.factor(at: 0, frames: right)), 0.5)
        near(Double(AudioAutomationMath.factor(at: 0.5, frames: left)), 0.2)
        near(Double(AudioAutomationMath.factor(at: 0.5, frames: right)), 0.8)

        let source = SoundEffectClip.create(
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            audioDuration: 8, timelineStart: 1, timelineEnd: 10
        )
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SoundEffectClip.self,
                                                from: data)
        precondition(decoded == source)
        // Legacy documents had no volumeKeyframes key.
        var legacy = try JSONSerialization.jsonObject(
            with: data
        ) as! [String: Any]
        legacy.removeValue(forKey: "volumeKeyframes")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyFX = try JSONDecoder().decode(
            SoundEffectClip.self, from: legacyData
        )
        precondition(legacyFX.volumeKeyframes.isEmpty)
        print("PASS: volume automation, fade mix, split remap, long files and legacy Codable")
    }
}
