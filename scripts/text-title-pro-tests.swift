import Foundation

// Pure Foundation stubs for the overlay animation model. Full app builds
// compile the real overlay sampler and its concrete enum definitions.
enum OverlayEasing: String, Codable { case easeInOut }
enum OverlayMotionPath: String, Codable { case straight }
struct OverlayKeyframe: Codable, Equatable {
    var progress: Double = 0
}

@main
struct TextTitleProTests {
    static func near(_ actual: Double, _ expected: Double) {
        precondition(abs(actual - expected) < 0.0001,
                     "Timeline should be \(expected) but was \(actual)")
    }

    static func main() throws {
        let base = TextOverlayClip()
        precondition(base.depthMode == .front)
        precondition(base.fillMode == .solid)
        precondition(base.fillAssetURL == nil)
        precondition(base.maskScale == 1)

        let data = try JSONEncoder().encode(base)
        var old = try JSONSerialization.jsonObject(
            with: data
        ) as! [String: Any]
        for key in [
            "depthMode", "fillMode", "fillAssetURL",
            "maskScale", "maskOffsetX", "maskOffsetY", "maskFit",
            "gradientEndHex", "strokeWidth", "strokeHex",
            "shadowOpacity", "glowRadius", "fauxDepth",
            "pulseEnabled"
        ] {
            old.removeValue(forKey: key)
        }
        let legacy = try JSONSerialization.data(
            withJSONObject: old
        )
        let oldTitle = try JSONDecoder().decode(
            TextOverlayClip.self, from: legacy
        )
        precondition(oldTitle.depthMode == .front)
        precondition(oldTitle.fillMode == .solid)
        precondition(oldTitle.fillAssetURL == nil)
        precondition(oldTitle.maskScale == 1)
        precondition(oldTitle.text == base.text)
        precondition(oldTitle.behindVisibilityAssist)
        // Regression: original source video begins at 13s but the
        // zero-based trimmed MOV begins at 0. For the second source clip
        // starting at 7s on the project timeline at 2x playback speed,
        // half a second in the MOV means project second 7.25.
        near(
            TextTitleRenderTime.projectSecond(
                clipStart: 7,
                trimmedCompositionSecond: 0.5,
                playbackSpeed: 2
            ), 7.25
        )
        near(
            TextTitleRenderTime.projectSecond(
                clipStart: 4,
                trimmedCompositionSecond: 2,
                playbackSpeed: 0.5
            ), 8
        )
        precondition(TextTitleRenderTime.intersects(
            titleStart: 7.1, titleDuration: 1.5,
            clipStart: 7, clipDuration: 3
        ))
        precondition(!TextTitleRenderTime.intersects(
            titleStart: 10.1, titleDuration: 1,
            clipStart: 7, clipDuration: 3
        ))

        for preset in TextTitlePreset.allCases {
            var title = TextOverlayClip()
            preset.apply(to: &title)
            precondition(title.fontSize >= 20)
            precondition(title.fontSize <= 160)
            precondition(!title.text.isEmpty)
            let saved = try JSONEncoder().encode(title)
            let restored = try JSONDecoder().decode(
                TextOverlayClip.self, from: saved
            )
            precondition(title == restored)
        }

        var title = TextOverlayClip()
        title.depthMode = .behindPerson
        title.fillMode = .video
        title.fillAssetURL = URL(
            fileURLWithPath: "/tmp/letter-fill.mp4"
        )
        title.maskOffsetX = -0.32
        title.maskScale = 2.4
        title.strokeWidth = 3
        title.fauxDepth = 5
        title.pulseEnabled = true
        let roundtrip = try JSONDecoder().decode(
            TextOverlayClip.self, from: JSONEncoder().encode(title)
        )
        precondition(roundtrip == title)
        precondition(TextAutoPlacement.bestPosition(
            normalizedFaceBoxes: []
        ).y > 0.7)
        let face = CGRect(
            x: 0.32, y: 0.65, width: 0.36, height: 0.28
        )
        let selected = TextAutoPlacement.bestPosition(
            normalizedFaceBoxes: [face]
        )
        precondition(selected.y < 0.65)
        print("PASS: Text Layer Pro v5.5 legacy Codable, presets, fill asset references and face-aware layout")
    }
}
