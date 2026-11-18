import Foundation

extension MusicVideoStudio {
    /// The record's pose is a pure function of time: no repeating animation
    /// that can desynchronise after a seek or pause.
    enum VinylMath {
        /// Degrees in [0, 360).
        static func angle(rpm: Double, localSeconds: Double, phase: Double = 0) -> Double {
            guard rpm.isFinite, localSeconds.isFinite, phase.isFinite else { return 0 }
            let degrees = rpm * 6 * (localSeconds + phase)          // rpm * 360 / 60
            let wrapped = degrees.truncatingRemainder(dividingBy: 360)
            return wrapped < 0 ? wrapped + 360 : wrapped
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
