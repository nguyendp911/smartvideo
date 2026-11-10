import Foundation

/// Speed keyframes use relative SOURCE positions, not rendered timeline time.
/// They remain stable when a clip is moved on the project timeline.
struct SpeedCurvePoint: Codable, Hashable {
    var position: Double
    var speed: Double

    init(_ position: Double, _ speed: Double) {
        self.position = position
        self.speed = speed
    }
}

enum SpeedCurvePreset: String, CaseIterable, Identifiable {
    case none = "Bình thường"
    case montage = "Montage"
    case hero = "Hero"
    case flash = "Flash"
    case custom = "Tùy chỉnh"

    var id: String { rawValue }

    var points: [SpeedCurvePoint] {
        switch self {
        case .none: return []
        case .montage:
            return [.init(0, 1), .init(0.25, 2.8), .init(0.5, 0.6),
                    .init(0.75, 2.5), .init(1, 1)]
        case .hero:
            return [.init(0, 1), .init(0.25, 0.45), .init(0.5, 0.35),
                    .init(0.75, 0.65), .init(1, 1.3)]
        case .flash:
            return [.init(0, 2.8), .init(0.25, 3.2), .init(0.5, 0.7),
                    .init(0.75, 3.4), .init(1, 1)]
        case .custom:
            return [.init(0, 1), .init(0.25, 1), .init(0.5, 1),
                    .init(0.75, 1), .init(1, 1)]
        }
    }
}

struct SpeedCurveSlice {
    let sourceOffset: Double
    let sourceDuration: Double
    let speed: Double
    let outputOffset: Double
    let outputDuration: Double
}

/// Shared by timeline math, source-frame lookup, live preview and export.
/// A linear curve is sampled into <= 36 constant-speed intervals to make
/// the result reproducible using AVMutableComposition.scaleTimeRange.
enum SpeedCurveMath {
    static let minSpeed = 0.25
    static let maxSpeed = 4.0

    static func normalized(_ input: [SpeedCurvePoint]) -> [SpeedCurvePoint] {
        guard input.count >= 2 else { return [] }
        let sorted = input.filter {
            $0.position.isFinite && $0.speed.isFinite
        }.map {
            SpeedCurvePoint(
                min(1, max(0, $0.position)),
                min(maxSpeed, max(minSpeed, $0.speed))
            )
        }.sorted { $0.position < $1.position }
        guard sorted.count >= 2 else { return [] }
        var result: [SpeedCurvePoint] = []
        for point in sorted {
            if let last = result.last, point.position - last.position < 0.00001 {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        guard result.count >= 2 else { return [] }
        if result[0].position > 0 {
            result.insert(.init(0, result[0].speed), at: 0)
        }
        if result[result.count - 1].position < 1 {
            result.append(.init(1, result[result.count - 1].speed))
        }
        return result
    }

    static func interpolatedSpeed(at position: Double,
                                  points: [SpeedCurvePoint]) -> Double {
        let values = normalized(points)
        guard let first = values.first else { return 1 }
        let fraction = min(1, max(0, position))
        if fraction <= first.position { return first.speed }
        for index in 0..<(values.count - 1) {
            let left = values[index]
            let right = values[index + 1]
            if fraction <= right.position {
                let weight = (fraction - left.position) /
                    max(0.00001, right.position - left.position)
                return left.speed + (right.speed - left.speed) * weight
            }
        }
        return values.last?.speed ?? 1
    }

    static func slices(sourceDuration: Double,
                       points: [SpeedCurvePoint]) -> [SpeedCurveSlice] {
        let keys = normalized(points)
        guard sourceDuration.isFinite, sourceDuration > 0.01,
              keys.count >= 2 else { return [] }

        var slices: [SpeedCurveSlice] = []
        var outputOffset = 0.0
        for i in 0..<(keys.count - 1) {
            let a = keys[i]
            let b = keys[i + 1]
            let steps = max(1, Int(ceil((b.position - a.position) * 32)))
            for step in 0..<steps {
                let lower = a.position + (b.position - a.position) *
                    Double(step) / Double(steps)
                let upper = a.position + (b.position - a.position) *
                    Double(step + 1) / Double(steps)
                let sourceLength = sourceDuration * (upper - lower)
                guard sourceLength > 0 else { continue }
                let midpoint = (lower + upper) * 0.5
                let speed = min(maxSpeed, max(minSpeed,
                    a.speed + (b.speed - a.speed) *
                    ((midpoint - a.position) / max(0.00001,
                                                 b.position - a.position))
                ))
                let outputLength = sourceLength / speed
                slices.append(SpeedCurveSlice(
                    sourceOffset: sourceDuration * lower,
                    sourceDuration: sourceLength, speed: speed,
                    outputOffset: outputOffset, outputDuration: outputLength
                ))
                outputOffset += outputLength
            }
        }
        return slices
    }

    static func outputDuration(sourceDuration: Double,
                               points: [SpeedCurvePoint]) -> Double {
        slices(sourceDuration: sourceDuration, points: points)
            .reduce(0) { $0 + $1.outputDuration }
    }

    /// Invert a rendered playhead to a position within the trimmed source.
    static func sourceOffset(atOutputSecond time: Double,
                             sourceDuration: Double,
                             points: [SpeedCurvePoint]) -> Double {
        let items = slices(sourceDuration: sourceDuration, points: points)
        guard let last = items.last else { return 0 }
        let output = min(max(0, time.isFinite ? time : 0),
                         last.outputOffset + last.outputDuration)
        for item in items {
            if output <= item.outputOffset + item.outputDuration {
                return min(sourceDuration, item.sourceOffset +
                    max(0, output - item.outputOffset) * item.speed)
            }
        }
        return sourceDuration
    }

    /// Preserve curve shape if the user splits a source clip or freezes a frame.
    static func trimmed(_ points: [SpeedCurvePoint],
                        from start: Double, to end: Double) -> [SpeedCurvePoint] {
        let keys = normalized(points)
        guard !keys.isEmpty else { return [] }
        let a = min(1, max(0, start))
        let b = min(1, max(a, end))
        guard b - a >= 0.00001 else { return [] }
        var output: [SpeedCurvePoint] = [
            .init(0, interpolatedSpeed(at: a, points: keys))
        ]
        for key in keys where key.position > a && key.position < b {
            output.append(.init((key.position - a) / (b - a), key.speed))
        }
        output.append(.init(1, interpolatedSpeed(at: b, points: keys)))
        return normalized(output)
    }
}
