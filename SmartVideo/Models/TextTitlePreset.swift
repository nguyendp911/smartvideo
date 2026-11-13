import Foundation
import CoreGraphics

enum TextTitlePreset: String, CaseIterable, Identifiable {
    case behindPerson = "Title Behind Person"
    case bigBold = "Big Bold Intro"
    case imagePoster = "Image In Text"
    case videoReveal = "Video In Text"
    case productName = "Product Behind Person"
    case cinematic = "Cinematic Name"
    case laptopSale = "Laptop Sale"
    case travel = "Travel Text"
    case neonBlue = "Neon Blue"
    case neonPink = "Neon Pink"
    case chrome = "Chrome Silver"
    case royalGold = "Royal Gold"
    case fire = "Fire Glow"
    case ice = "Ice Frost"
    case cyberpunk = "Cyberpunk"
    case saleFlash = "Flash Sale"

    var id: String { rawValue }

    var previewColors: (start: String, end: String) {
        var sample = TextOverlayClip()
        apply(to: &sample)
        return (sample.colorHex, sample.gradientEndHex)
    }

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
        title.shadowOpacity = 0.35
        title.strokeHex = "FFFFFF"
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
        case .neonBlue:
            title.fillMode = .gradient
            title.colorHex = "E4FFFF"
            title.gradientEndHex = "00CFFF"
            title.strokeHex = "008DFF"
            title.strokeWidth = 2.5
            title.glowRadius = 15
            title.fauxDepth = 0
        case .neonPink:
            title.fillMode = .gradient
            title.colorHex = "FFF1FB"
            title.gradientEndHex = "FF36BC"
            title.strokeHex = "A400FF"
            title.strokeWidth = 2.5
            title.glowRadius = 16
            title.fauxDepth = 0
        case .chrome:
            title.fillMode = .gradient
            title.colorHex = "FFFFFF"
            title.gradientEndHex = "6F8396"
            title.strokeHex = "E8F4FF"
            title.strokeWidth = 1.5
            title.glowRadius = 0
            title.fauxDepth = 7
        case .royalGold:
            title.fillMode = .gradient
            title.colorHex = "FFF5BB"
            title.gradientEndHex = "B77A15"
            title.strokeHex = "FFDE7C"
            title.strokeWidth = 1.5
            title.glowRadius = 0
            title.fauxDepth = 5
        case .fire:
            title.fillMode = .gradient
            title.colorHex = "FFF498"
            title.gradientEndHex = "FF3B0B"
            title.strokeHex = "B91800"
            title.strokeWidth = 2
            title.glowRadius = 18
            title.fauxDepth = 0
        case .ice:
            title.fillMode = .gradient
            title.colorHex = "FFFFFF"
            title.gradientEndHex = "42AFFF"
            title.strokeHex = "BEF7FF"
            title.strokeWidth = 3
            title.glowRadius = 8
            title.fauxDepth = 0
        case .cyberpunk:
            title.fillMode = .gradient
            title.colorHex = "00FFF0"
            title.gradientEndHex = "F7FF32"
            title.strokeHex = "FD2FFF"
            title.strokeWidth = 3
            title.glowRadius = 9
            title.fauxDepth = 5
        case .saleFlash:
            title.fillMode = .gradient
            title.colorHex = "FFE500"
            title.gradientEndHex = "FF4534"
            title.strokeHex = "FFFFFF"
            title.strokeWidth = 3
            title.glowRadius = 7
            title.fauxDepth = 7
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
