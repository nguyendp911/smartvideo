import Foundation

@main
struct MultitrackAudioTests {
    static func near(_ a: Double, _ b: Double,
                     tolerance: Double = 0.0001) {
        precondition(a.isFinite && abs(a - b) <= tolerance,
                     "expected \(b), got \(a)")
    }

    static func main() {
        let math = AudioTimelineMath.self
        let width = math.contentWidth(
            duration: 30, zoom: 1, viewportWidth: 340
        )
        near(width, 720)
        near(math.contentWidth(duration: 30, zoom: 0.5,
                               viewportWidth: 340), 360)
        near(math.contentWidth(duration: 10_000, zoom: 3,
                               viewportWidth: 340), 12_000)
        near(math.clampStart(-10, duration: 2,
                             projectDuration: 30), 0)
        near(math.clampStart(29.8, duration: 2,
                             projectDuration: 30), 28)
        near(math.draggedTime(
            origin: 5, translationPoints: 120,
            contentWidth: 720, projectDuration: 30, duration: 2
        ), 10)
        near(math.draggedTime(
            origin: 5, translationPoints: -240,
            contentWidth: 720, projectDuration: 30, duration: 2
        ), 0)
        near(math.draggedTime(
            origin: 5, translationPoints: 120,
            contentWidth: 720, projectDuration: 30, duration: 2,
            snapMarkers: [10.08, 15], snapThreshold: 0.12
        ), 10.08)
        near(math.draggedTime(
            origin: 5, translationPoints: 120,
            contentWidth: 720, projectDuration: 30, duration: 2,
            snapMarkers: [10.25, 15], snapThreshold: 0.12
        ), 10)
        let moved = math.draggedKeyframe(
            initialProgress: 0.25, initialGain: 0.8,
            horizontalPoints: 120, verticalPoints: 17,
            regionWidth: 400, regionHeight: 34
        )
        near(moved.progress, 0.55)
        near(Double(moved.gain), 0.3)
        let bounded = math.draggedKeyframe(
            initialProgress: 1, initialGain: 1,
            horizontalPoints: 200, verticalPoints: -50,
            regionWidth: 300, regionHeight: 34
        )
        near(bounded.progress, 1)
        near(Double(bounded.gain), 1)
        let empty = math.draggedTime(
            origin: 15, translationPoints: .nan,
            contentWidth: 400, projectDuration: 20, duration: 8
        )
        near(empty, 12)
        print("PASS: common timeline scale, audio dragging, beat snap, keyframe drag, bounds and nonfinite values")
    }
}
