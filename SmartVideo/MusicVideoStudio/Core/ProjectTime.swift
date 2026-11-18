import Foundation
import CoreMedia

extension MusicVideoStudio {
    /// The single time base of the whole module. Stored as integer ticks of
    /// 1/60000 s, which is an exact multiple of one frame at 24, 25, 30 and
    /// 60 fps, so frame-accurate maths never drifts. Converts to/from `CMTime`
    /// for AVFoundation (audio, composition, export).
    struct ProjectTime: Hashable, Comparable, Codable {
        static let timescale: Int32 = 60_000
        static let zero = ProjectTime(ticks: 0)

        var ticks: Int64

        init(ticks: Int64) { self.ticks = ticks }

        init(seconds: Double) {
            ticks = seconds.isFinite
                ? Int64((seconds * Double(Self.timescale)).rounded())
                : 0
        }

        init(_ time: CMTime) {
            guard time.isNumeric, !time.isIndefinite else { ticks = 0; return }
            ticks = CMTimeConvertScale(time, timescale: Self.timescale, method: .roundHalfAwayFromZero).value
        }

        var seconds: Double { Double(ticks) / Double(Self.timescale) }
        var cmTime: CMTime { CMTime(value: ticks, timescale: Self.timescale) }

        static func < (a: ProjectTime, b: ProjectTime) -> Bool { a.ticks < b.ticks }
        static func + (a: ProjectTime, b: ProjectTime) -> ProjectTime { ProjectTime(ticks: a.ticks + b.ticks) }
        static func - (a: ProjectTime, b: ProjectTime) -> ProjectTime { ProjectTime(ticks: a.ticks - b.ticks) }
        static func * (a: ProjectTime, k: Double) -> ProjectTime { ProjectTime(seconds: a.seconds * k) }

        func clamped(_ lower: ProjectTime, _ upper: ProjectTime) -> ProjectTime {
            upper < lower ? lower : min(upper, max(lower, self))
        }

        // MARK: Frames

        static let supportedFrameRates = [24, 25, 30, 60]

        static func ticksPerFrame(fps: Int) -> Int64 {
            Int64(Self.timescale) / Int64(max(1, fps))
        }

        func frameIndex(fps: Int) -> Int {
            guard ticks > 0 else { return 0 }
            return Int(ticks / Self.ticksPerFrame(fps: fps))
        }

        /// Floors to the start of the frame this time falls in.
        func quantized(fps: Int) -> ProjectTime {
            let per = Self.ticksPerFrame(fps: fps)
            guard ticks > 0 else { return .zero }
            return ProjectTime(ticks: ticks / per * per)
        }

        static func frame(_ index: Int, fps: Int) -> ProjectTime {
            ProjectTime(ticks: Int64(max(0, index)) * ticksPerFrame(fps: fps))
        }

        /// `MM:SS:FF`, or `H:MM:SS:FF` from one hour on.
        func timecode(fps: Int) -> String {
            let total = max(0, ticks) / Int64(Self.timescale)
            let frames = frameIndex(fps: fps) - Int(total) * max(1, fps)
            let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
            let ff = String(format: "%02d", max(0, frames))
            if hours > 0 { return String(format: "%lld:%02lld:%02lld:", hours, minutes, secs) + ff }
            return String(format: "%02lld:%02lld:", minutes, secs) + ff
        }
    }

    struct TimeRange: Hashable, Codable {
        var start: ProjectTime
        var duration: ProjectTime

        var end: ProjectTime { start + duration }

        /// Half-open: a clip is active on [start, end).
        func contains(_ time: ProjectTime) -> Bool { time >= start && time < end }

        func overlaps(_ other: TimeRange) -> Bool { start < other.end && other.start < end }
    }
}
