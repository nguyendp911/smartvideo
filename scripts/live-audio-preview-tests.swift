import Foundation

@main
struct LiveAudioPreviewTests {
    static func near(_ value: Double, _ expected: Double,
                     tolerance: Double = 0.0001) {
        precondition(abs(value - expected) < tolerance,
                     "Expected \(expected), got \(value)")
    }

    static func main() {
        let math = LiveAudioPreviewMath.self
        near(math.musicOffset(
            timeline: 4, fileDuration: 90, start: 10,
            highlightDuration: 20, repeats: false
        )!, 14)
        precondition(math.musicOffset(
            timeline: 21, fileDuration: 90, start: 10,
            highlightDuration: 20, repeats: false
        ) == nil)
        near(math.musicOffset(
            timeline: 22, fileDuration: 90, start: 10,
            highlightDuration: 20, repeats: true
        )!, 12)
        near(math.musicOffset(
            timeline: 2, fileDuration: 30, start: 29,
            highlightDuration: 20, repeats: true
        )!, 29)
        precondition(math.musicOffset(
            timeline: .nan, fileDuration: 30, start: 0,
            highlightDuration: 0, repeats: true
        ) == nil)
        near(math.musicEnd(
            timelineEnd: 40, fileDuration: 25, start: 5,
            highlightDuration: 8, repeats: false
        ), 8)
        near(math.musicEnd(
            timelineEnd: 40, fileDuration: 25, start: 5,
            highlightDuration: 8, repeats: true
        ), 40)
        near(math.regionOffset(
            timeline: 3.5, regionStart: 2,
            sourceStart: 4, duration: 3
        )!, 5.5)
        precondition(math.regionOffset(
            timeline: 6, regionStart: 2, sourceStart: 4,
            duration: 3
        ) == nil)
        near(Double(math.envelope(
            timeline: 0, start: 0, duration: 10,
            fadeIn: 1, fadeOut: 2
        )), 0)
        near(Double(math.envelope(
            timeline: 0.5, start: 0, duration: 10,
            fadeIn: 1, fadeOut: 2
        )), 0.5)
        near(Double(math.envelope(
            timeline: 9, start: 0, duration: 10,
            fadeIn: 1, fadeOut: 2
        )), 0.5)
        near(Double(math.musicGain(
            timeline: 4, baseVolume: 0.8, musicEnd: 10,
            fadeIn: 0, fadeOut: 0,
            narrationStart: 3, narrationEnd: 5
        )), 0.2)
        near(Double(math.musicGain(
            timeline: 6, baseVolume: 0.8, musicEnd: 10,
            fadeIn: 0, fadeOut: 0,
            narrationStart: 3, narrationEnd: 5
        )), 0.8)
        print("PASS: live audio music loops, voice/SFX offsets, fades, duck and edge cases")
    }
}
