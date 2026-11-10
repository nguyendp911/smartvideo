import Foundation

/// Compiled together with Models/SpeedCurve.swift by GitHub Actions.
/// Deliberately Foundation-only, so the duration and inverse-time math can
/// be checked without a simulator or any private video files.
@main
struct SpeedCurveTests {
    static func main() {
        let sourceDuration = 12.0
        for preset in [
            SpeedCurvePreset.montage, .hero, .flash, .custom
        ] {
            let points = preset.points
            let samples = SpeedCurveMath.slices(
                sourceDuration: sourceDuration, points: points
            )
            precondition(!samples.isEmpty,
                         "\(preset.rawValue): missing sampled intervals")
            precondition(samples.count <= 36,
                         "\(preset.rawValue): too many samples")
            for sample in samples {
                precondition(sample.speed >= 0.25 && sample.speed <= 4)
                precondition(sample.sourceDuration > 0)
                precondition(sample.outputDuration > 0)
            }

            let rendered = SpeedCurveMath.outputDuration(
                sourceDuration: sourceDuration, points: points
            )
            let last = samples[samples.count - 1]
            precondition(abs(last.outputOffset +
                             last.outputDuration - rendered) < 0.001)
            precondition(abs(SpeedCurveMath.sourceOffset(
                atOutputSecond: 0, sourceDuration: sourceDuration,
                points: points
            )) < 0.001)
            precondition(abs(SpeedCurveMath.sourceOffset(
                atOutputSecond: rendered, sourceDuration: sourceDuration,
                points: points
            ) - sourceDuration) < 0.001)

            var previous = 0.0
            for step in 0...50 {
                let time = rendered * Double(step) / 50
                let source = SpeedCurveMath.sourceOffset(
                    atOutputSecond: time, sourceDuration: sourceDuration,
                    points: points
                )
                precondition(source >= previous - 0.00001,
                             "\(preset.rawValue): nonmonotonic inverse")
                precondition(source <= sourceDuration + 0.00001)
                previous = source
            }

            let middle = SpeedCurveMath.sourceOffset(
                atOutputSecond: rendered * 0.5,
                sourceDuration: sourceDuration, points: points
            )
            let fraction = middle / sourceDuration
            let left = SpeedCurveMath.trimmed(points, from: 0, to: fraction)
            let right = SpeedCurveMath.trimmed(points, from: fraction, to: 1)
            precondition(!left.isEmpty && !right.isEmpty)
            let leftSeconds = SpeedCurveMath.outputDuration(
                sourceDuration: middle, points: left
            )
            let rightSeconds = SpeedCurveMath.outputDuration(
                sourceDuration: sourceDuration - middle, points: right
            )
            precondition(abs((leftSeconds + rightSeconds) - rendered) < 0.025,
                         "\(preset.rawValue): duration drift after split")
        }

        // Malformed user project data is clamped and stable.
        let invalid: [SpeedCurvePoint] = [
            .init(-1, 0.01), .init(0.5, 100), .init(2, -50)
        ]
        let safe = SpeedCurveMath.normalized(invalid)
        precondition(safe.first?.position == 0 && safe.last?.position == 1)
        precondition(safe.allSatisfy { $0.speed >= 0.25 && $0.speed <= 4 })
        precondition(SpeedCurveMath.normalized([]).isEmpty)
        print("PASS: Speed Curve duration, inverse mapping, split and validation")
    }
}
