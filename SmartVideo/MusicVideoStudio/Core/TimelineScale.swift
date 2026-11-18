import Foundation

extension MusicVideoStudio {
    /// Maps time <-> x position on the horizontal timeline and decides where
    /// ruler ticks go for the current zoom level.
    struct TimelineScale: Equatable {
        static let range = 8.0...400.0
        static let trailingPadding = 140.0

        var pixelsPerSecond = 60.0 {
            didSet { pixelsPerSecond = Self.clamp(pixelsPerSecond) }
        }

        init(pixelsPerSecond: Double = 60) {
            self.pixelsPerSecond = Self.clamp(pixelsPerSecond)
        }

        static func clamp(_ value: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : 60
        }

        func x(for time: ProjectTime) -> Double { time.seconds * pixelsPerSecond }

        func time(forX x: Double) -> ProjectTime {
            ProjectTime(seconds: max(0, x) / pixelsPerSecond)
        }

        func contentWidth(duration: ProjectTime) -> Double {
            x(for: duration) + Self.trailingPadding
        }

        /// Zoom so the whole project exactly fills `width` points.
        static func fitting(duration: ProjectTime, width: Double) -> TimelineScale {
            let seconds = max(0.5, duration.seconds)
            return TimelineScale(pixelsPerSecond: max(1, width - trailingPadding) / seconds)
        }

        struct Tick: Equatable {
            var time: ProjectTime
            var isMajor: Bool
            var label: String?
        }

        private static let majorSteps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1800]

        /// Major tick spacing in seconds: the smallest step that is at least 70 pt wide.
        var majorStep: Double {
            Self.majorSteps.first { $0 * pixelsPerSecond >= 70 } ?? Self.majorSteps.last!
        }

        static func label(for seconds: Double, step: Double) -> String {
            let total = Int((seconds * 10).rounded())
            let whole = total / 10, tenth = total % 10
            let m = whole / 60, s = whole % 60
            if step < 1 { return m > 0 ? String(format: "%ld:%02ld.%ld", m, s, tenth) : String(format: "%ld.%ld", s, tenth) }
            return String(format: "%ld:%02ld", m, s)
        }

        /// Ticks intersecting `visible` (seconds). Minor ticks only when they are >= 9 pt apart.
        func ticks(visible: ClosedRange<Double>) -> [Tick] {
            let step = majorStep
            let minorDivisions: Int = step >= 1 ? (step >= 5 ? 5 : 4) : 2
            let minorStep = step / Double(minorDivisions)
            let showMinor = minorStep * pixelsPerSecond >= 9
            let unit = showMinor ? minorStep : step
            let first = max(0, Int((visible.lowerBound / unit).rounded(.down)))
            let last = Int((visible.upperBound / unit).rounded(.up))
            guard last >= first, last - first < 20_000 else { return [] }
            var out: [Tick] = []
            for index in first...last {
                let seconds = Double(index) * unit
                let isMajor = abs((seconds / step).rounded() * step - seconds) < unit * 0.01
                out.append(Tick(time: ProjectTime(seconds: seconds), isMajor: isMajor,
                                label: isMajor ? Self.label(for: seconds, step: step) : nil))
            }
            return out
        }
    }
}
