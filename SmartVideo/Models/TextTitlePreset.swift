import Foundation

enum TextTitlePreset: String, CaseIterable, Identifiable {
    case behindPerson = "Title Behind Person"
    case bigBold = "Big Bold Intro"
    case imagePoster = "Image In Text"
    case videoReveal = "Video In Text"
    case productName = "Product Behind Person"
    case cinematic = "Cinematic Name"
    case laptopSale = "Laptop Sale"
    case travel = "Travel Text"

    var id: String { rawValue }

    func apply(to title: inout TextOverlayClip) {
        title.pulseEnabled = false
        title.useBackground = false
        title.fauxDepth = 0
        title.glowRadius = 0
        title.strokeWidth = 0
        title.maskScale = 1
        title.maskOffsetX = 0
        title.maskOffsetY = 0
        title.opacity = 1
        title.fontSize = 80
        title.depthMode = .front
        title.fillMode = .solid
        title.colorHex = "FFFFFF"
        title.gradientEndHex = "18D6F5"

        switch self {
        case .behindPerson:
            title.depthMode = .behindPerson
            title.fontSize = 112
            title.shadowOpacity = 0.65
        case .bigBold:
            title.fontSize = 125
            title.fillMode = .gradient
            title.colorHex = "FFFFFF"
            title.gradientEndHex = "F3C66B"
            title.pulseEnabled = true
        case .imagePoster:
            title.fillMode = .image
            title.fontSize = 110
            title.strokeWidth = 1
        case .videoReveal:
            title.fillMode = .video
            title.fontSize = 110
            title.strokeWidth = 1
        case .productName:
            title.depthMode = .behindPerson
            title.fillMode = .gradient
            title.colorHex = "FFE29A"
            title.gradientEndHex = "F79B35"
            title.fontSize = 110
        case .cinematic:
            title.fillMode = .gradient
            title.colorHex = "F4F0E8"
            title.gradientEndHex = "C19B6B"
            title.fauxDepth = 3
            title.shadowOpacity = 0.8
            title.fontSize = 76
        case .laptopSale:
            title.fillMode = .gradient
            title.colorHex = "FFD631"
            title.gradientEndHex = "FF5B48"
            title.fauxDepth = 5
            title.strokeWidth = 2
            title.glowRadius = 5
            title.fontSize = 116
        case .travel:
            title.fillMode = .video
            title.fontSize = 115
            title.pulseEnabled = true
            title.strokeWidth = 1
        }
    }
}

enum TextAutoPlacement {
    /// Normalized top-left UI coordinates. Candidate centers are ranked by
    /// squared distance from *every* detected face with strong penalties for
    /// overlapping an enlarged face box. The tie-break keeps captions low.
    static func bestPosition(
        normalizedFaceBoxes: [CGRect]
    ) -> (x: Double, y: Double) {
        let options: [(Double, Double)] = [
            (0.5, 0.81),
            (0.5, 0.18),
            (0.22, 0.80),
            (0.78, 0.80),
            (0.22, 0.23),
            (0.78, 0.23),
            (0.5, 0.51)
        ]
        guard !normalizedFaceBoxes.isEmpty else {
            return (0.5, 0.81)
        }
        func score(_ point: (Double, Double)) -> Double {
            var distance = 0.0
            for box in normalizedFaceBoxes {
                let x = Double(box.midX)
                let y = Double(box.midY)
                let dx = point.0 - x
                let dy = point.1 - y
                let d = sqrt(dx * dx + dy * dy)
                let faceRadius = max(
                    0.15, Double(max(box.width, box.height)) * 0.9
                )
                distance += max(-2, min(1,
                    (d - faceRadius) * 3
                ))
            }
            return distance
        }
        return options.max(by: { score($0) < score($1) }) ?? (0.5, 0.81)
    }
}
