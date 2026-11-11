import Foundation

@main
struct ProjectPreviewTimingTests {
    static func main() {
        let starts: [Double] = [0, 2.8, 5.2, 10]
        precondition(ProjectPreviewTiming.nextClip(
            after: 0, globalTime: 2.50, clipStarts: starts
        ) == nil)
        precondition(ProjectPreviewTiming.nextClip(
            after: 0, globalTime: 2.79, clipStarts: starts
        ) == 1)
        precondition(ProjectPreviewTiming.nextClip(
            after: 1, globalTime: 5.18, clipStarts: starts
        ) == 2)
        precondition(ProjectPreviewTiming.nextClip(
            after: 3, globalTime: 15, clipStarts: starts
        ) == nil)
        precondition(ProjectPreviewTiming.nextClip(
            after: -1, globalTime: 0, clipStarts: starts
        ) == nil)
        precondition(ProjectPreviewTiming.isFinished(
            globalTime: 12.94, totalDuration: 13
        ))
        precondition(!ProjectPreviewTiming.isFinished(
            globalTime: 12.4, totalDuration: 13
        ))
        precondition(!ProjectPreviewTiming.isFinished(
            globalTime: .nan, totalDuration: 13
        ))
        precondition(ProjectPreviewTiming.normalizedProgress(
            localTime: 2, renderedDuration: 4
        ) == 0.5)
        precondition(ProjectPreviewTiming.normalizedProgress(
            localTime: 6, renderedDuration: 4
        ) == 1)
        precondition(ProjectPreviewTiming.normalizedProgress(
            localTime: -1, renderedDuration: 4
        ) == 0)
        precondition(ProjectPreviewTiming.clockDelta(elapsed: 0.2) == 0.2)
        precondition(ProjectPreviewTiming.clockDelta(elapsed: 5) == 0.25)
        precondition(ProjectPreviewTiming.clockDelta(elapsed: -5) == 0)
        precondition(ProjectPreviewTiming.sourceTime(
            localTime: 2, trimStart: 7, playbackSpeed: 2,
            speedCurveEnabled: false
        ) == 11)
        precondition(ProjectPreviewTiming.sourceTime(
            localTime: 2, trimStart: 7, playbackSpeed: 2,
            speedCurveEnabled: true
        ) == 2)
        print("PASS: project-preview clock, overlap handoffs, restart and seek math")
    }
}
