import Foundation

@main
struct ProjectAudioTrackTests {
    static func near(_ a: Double, _ b: Double,
                     tolerance: Double = 0.002) {
        precondition(a.isFinite && abs(a - b) < tolerance,
                     "Expected \(b) got \(a)")
    }
    static func main() {
        let m = ProjectAudioTrackMath.self
        near(m.safeStart(-3, projectDuration: 20), 0)
        near(m.safeStart(100, projectDuration: 20), 20)
        near(m.musicDuration(projectDuration: 30,
            timelineStart: 7, fileDuration: 50, sourceStart: 10,
            highlightDuration: 8, repeats: false), 8)
        near(m.musicDuration(projectDuration: 30,
            timelineStart: 7, fileDuration: 50, sourceStart: 10,
            highlightDuration: 8, repeats: true), 23)
        near(m.musicDuration(projectDuration: 30,
            timelineStart: 29, fileDuration: 5, sourceStart: 0,
            highlightDuration: 0, repeats: true), 1)
        precondition(m.musicSourceTime(
            projectSecond: 6.9, timelineStart: 7,
            projectDuration: 30, fileDuration: 50, sourceStart: 10,
            highlightDuration: 8, repeats: true
        ) == nil)
        near(m.musicSourceTime(
            projectSecond: 7, timelineStart: 7,
            projectDuration: 30, fileDuration: 50, sourceStart: 10,
            highlightDuration: 8, repeats: true
        )!, 10)
        near(m.musicSourceTime(
            projectSecond: 17, timelineStart: 7,
            projectDuration: 30, fileDuration: 50, sourceStart: 10,
            highlightDuration: 8, repeats: true
        )!, 12)
        precondition(m.musicSourceTime(
            projectSecond: 16, timelineStart: 7,
            projectDuration: 30, fileDuration: 50, sourceStart: 10,
            highlightDuration: 8, repeats: false
        ) == nil)

        let frames = [
            AudioGainKeyframe(progress: 0.25, gain: 0.2),
            AudioGainKeyframe(progress: 0.75, gain: 0.8)
        ]
        near(Double(m.gain(
            localSecond: 5, duration: 10, volume: 0.8,
            fadeIn: 0, fadeOut: 0, keyframes: frames
        )), 0.4)
        near(Double(m.duck(at: 2,
            narrationStart: 5, narrationEnd: 9)), 1)
        near(Double(m.duck(at: 5.075,
            narrationStart: 5, narrationEnd: 9)), 0.625)
        near(Double(m.duck(at: 7,
            narrationStart: 5, narrationEnd: 9)), 0.25)
        near(Double(m.duck(at: 9.1,
            narrationStart: 5, narrationEnd: 9)), 0.625)
        near(Double(m.duck(at: 10,
            narrationStart: 5, narrationEnd: 9)), 1)
        near(Double(m.gain(
            localSecond: 7, duration: 10, volume: 1,
            fadeIn: 0, fadeOut: 0, keyframes: [],
            narrationStart: 5, narrationEnd: 9
        )), 0.25)
        let nodes = m.points(
            duration: 10_000, volume: 0.6,
            fadeIn: 1.5, fadeOut: 1.5,
            keyframes: frames,
            narrationStart: 2_500, narrationEnd: 2_520
        )
        precondition(nodes.count < 180)
        near(nodes.first!.second, 0)
        near(nodes.last!.second, 10_000)
        for (a, b) in zip(nodes, nodes.dropFirst()) {
            precondition(a.second < b.second)
            precondition(a.gain >= 0 && a.gain <= 1)
            precondition(b.gain >= 0 && b.gain <= 1)
        }
        print("PASS: moved music, clip offsets, loop, narration duck, fade and volume automation")
    }
}
