import Foundation

/// Geometry for a unified video/audio timeline (global project seconds).
enum AudioTimelineMath {
    static func pixelsPerSecond(
        duration: Double, zoom: Double,
        viewportWidth: Double
    ) -> Double {
        let safeDuration = duration.isFinite ? max(0.1, duration) : 1
        let safeZoom = zoom.isFinite ? min(3, max(0.5, zoom)) : 1
        let preferred = max(12, 24 * safeZoom)
        // At most 12,000 points of content even for multi-hour projects.
        return min(preferred, max(0.1, 12_000 / safeDuration))
    }

    static func contentWidth(
        duration: Double, zoom: Double,
        viewportWidth: Double
    ) -> Double {
        let width = viewportWidth.isFinite ? max(1, viewportWidth) : 1
        let safeDuration = duration.isFinite ? max(0.1, duration) : 1
        return max(width, safeDuration * pixelsPerSecond(
            duration: duration, zoom: zoom, viewportWidth: width
        ))
    }

    static func clampStart(
        _ proposed: Double, duration: Double,
        projectDuration: Double
    ) -> Double {
        guard proposed.isFinite else { return 0 }
        let maximum = max(0, projectDuration - max(0.1, duration))
        return min(maximum, max(0, proposed))
    }

    static func draggedTime(
        origin: Double, translationPoints: Double,
        contentWidth: Double, projectDuration: Double,
        duration: Double,
        snapMarkers: [Double] = [],
        snapThreshold: Double = 0.12
    ) -> Double {
        let pps = contentWidth / max(0.1, projectDuration)
        let proposed = origin + (translationPoints.isFinite ?
            translationPoints / max(0.01, pps) : 0)
        let nearest = snapMarkers
            .filter { $0.isFinite }
            .min(by: { abs($0 - proposed) < abs($1 - proposed) })
        if let nearest,
           abs(nearest - proposed) <= max(0, snapThreshold) {
            return clampStart(nearest, duration: duration,
                              projectDuration: projectDuration)
        }
        return clampStart(proposed, duration: duration,
                          projectDuration: projectDuration)
    }

    static func draggedKeyframe(
        initialProgress: Double, initialGain: Float,
        horizontalPoints: Double, verticalPoints: Double,
        regionWidth: Double, regionHeight: Double
    ) -> (progress: Double, gain: Float) {
        let progress = AudioAutomationMath.clampProgress(
            initialProgress + (horizontalPoints.isFinite ?
                horizontalPoints / max(1, regionWidth) : 0)
        )
        let gain = AudioAutomationMath.clampGain(
            initialGain - Float(verticalPoints.isFinite ?
                verticalPoints / max(1, regionHeight) : 0)
        )
        return (progress, gain)
    }
}
