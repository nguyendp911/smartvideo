import Foundation

extension MusicVideoStudio {
    /// The record's pose is a pure function of time: no repeating animation
    /// that can desynchronise after a seek or pause.
    enum VinylMath {
        /// Degrees in [0, 360). With `spinUp` the record accelerates evenly over that many seconds
        /// (angle = integral of the speed), then turns at full speed; `phase` counts as time already spun.
        static func angle(rpm: Double, localSeconds: Double, phase: Double = 0, spinUp: Double = 0) -> Double {
            guard rpm.isFinite, localSeconds.isFinite, phase.isFinite else { return 0 }
            let t = max(0, localSeconds + phase)
            let ramp = spinUp.isFinite ? max(0, spinUp) : 0
            let effective: Double
            if ramp > 0 { effective = t < ramp ? t * t / (2 * ramp) : t - ramp / 2 } else { effective = localSeconds + phase }
            let degrees = rpm * 6 * effective                       // rpm * 360 / 60
            let wrapped = degrees.truncatingRemainder(dividingBy: 360)
            return wrapped < 0 ? wrapped + 360 : wrapped
        }

        // MARK: Tonearm (lengths in units of the record's radius)

        static let armPivot = (x: 1.05, y: -0.8)
        static let armLength = 1.3
        static let restRadius = 1.28
        static let outerGroove = 0.94

        /// Direction (degrees) of the arm so its tip is `radius` from the record's centre.
        static func armAngle(headRadius radius: Double) -> Double {
            let d = hypot(armPivot.x, armPivot.y)
            let base = atan2(-armPivot.y, -armPivot.x)                     // pivot -> record centre
            let r = min(d + armLength, max(abs(d - armLength), radius.isFinite ? radius : restRadius))
            let cosine = max(-1, min(1, (d * d + armLength * armLength - r * r) / (2 * d * armLength)))
            return (base + acos(cosine)) * 180 / .pi
        }

        /// Where the tip of the arm is for that direction (centre of the record = 0, 0).
        static func headPosition(armAngle degrees: Double) -> (x: Double, y: Double) {
            let a = degrees * .pi / 180
            return (armPivot.x + armLength * cos(a), armPivot.y + armLength * sin(a))
        }

        /// Smooth 0...1.
        static func smooth(_ x: Double) -> Double {
            let t = min(1, max(0, x.isFinite ? x : 0))
            return t * t * (3 - 2 * t)
        }

        /// Distance of the tip from the centre: at rest beside the record, lands on the outer groove in
        /// `drop` seconds, creeps inward while it plays, and lifts back in the last `lift` seconds.
        static func tonearmHeadRadius(localSeconds: Double, duration: Double, innerRadius: Double = 0.5,
                                      drop: Double = 1.2, lift: Double = 1.0) -> Double {
            guard localSeconds.isFinite, duration.isFinite, duration > 0 else { return restRadius }
            let t = max(0, localSeconds)
            let inner = min(outerGroove - 0.05, max(0.2, innerRadius))
            let landed = min(drop, duration / 2)
            if t < landed { return restRadius + (outerGroove - restRadius) * smooth(t / max(0.001, landed)) }
            let liftStart = max(landed, duration - lift)
            func track(_ time: Double) -> Double {
                outerGroove + (inner - outerGroove) * min(1, max(0, (time - landed) / max(0.001, liftStart - landed)))
            }
            if t >= liftStart {
                let from = track(liftStart)
                return from + (restRadius - from) * smooth((t - liftStart) / max(0.001, min(lift, duration - liftStart)))
            }
            return track(t)
        }

        /// Seconds into the layer at `time`.
        static func localSeconds(layerStart: ProjectTime, at time: ProjectTime) -> Double {
            max(0, (time - layerStart).seconds)
        }

        static func diameter(canvas: CGSize, size: Double) -> CGFloat {
            min(canvas.width, canvas.height) * CGFloat(min(VinylLayer.sizeRange.upperBound, max(VinylLayer.sizeRange.lowerBound, size.isFinite ? size : 0.55)))
        }
    }
}
