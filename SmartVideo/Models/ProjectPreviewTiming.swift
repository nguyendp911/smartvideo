import Foundation

/// Lightweight project-preview transport rules; independent from AVFoundation.
/// Incoming clips take over at their timeline start, including any overlap.
/// This is cut-style live preview, not a composited transition or audio mix.
enum ProjectPreviewTiming {
    static func nextClip(
        after index: Int, globalTime: Double, clipStarts: [Double],
        tolerance: Double = 0.025
    ) -> Int? {
        let next = index + 1
        guard next < clipStarts.count, next > 0,
              globalTime.isFinite, clipStarts[next].isFinite else {
            return nil
        }
        return globalTime + max(0, tolerance) >= clipStarts[next] ?
            next : nil
    }

    static func isFinished(
        globalTime: Double, totalDuration: Double,
        tolerance: Double = 0.065
    ) -> Bool {
        guard globalTime.isFinite, totalDuration.isFinite,
              totalDuration > 0 else { return false }
        return globalTime + max(0, tolerance) >= totalDuration
    }

    static func normalizedProgress(
        localTime: Double, renderedDuration: Double
    ) -> Double {
        guard localTime.isFinite, renderedDuration.isFinite,
              renderedDuration > 0 else { return 0 }
        return min(1, max(0, localTime / renderedDuration))
    }

    static func clockDelta(
        elapsed: Double, maxStep: Double = 0.25
    ) -> Double {
        guard elapsed.isFinite else { return 0 }
        return min(max(0, elapsed), max(0.01, maxStep))
    }

    static func sourceTime(
        localTime: Double, trimStart: Double, playbackSpeed: Double,
        speedCurveEnabled: Bool
    ) -> Double {
        guard localTime.isFinite else { return 0 }
        let local = max(0, localTime)
        if speedCurveEnabled { return local }
        return max(0, trimStart) + local * max(0.25, playbackSpeed)
    }
}
