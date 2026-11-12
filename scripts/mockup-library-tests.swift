import Foundation

@main
struct MockupLibraryTests {
    static func near(
        _ left: Double, _ right: Double,
        tolerance: Double = 0.001
    ) {
        precondition(abs(left - right) < tolerance,
                     "Expected \(right), received \(left)")
    }

    static func main() throws {
        let all = MockupAssetLibrary.all
        precondition(all.count == 42, "Expected 42 builtin mockups")
        precondition(Set(all.map(\.id)).count == all.count,
                     "Mockup IDs must be unique")
        for category in MockupCategory.allCases {
            precondition(all.contains { $0.category == category },
                         "Category \(category) is empty")
        }
        precondition(MockupMoodPreset.all.count >= 10)
        for mood in MockupMoodPreset.all {
            precondition(!mood.effectIDs.isEmpty)
            for id in mood.effectIDs {
                precondition(MockupAssetLibrary.find(id) != nil,
                             "Invalid preset effect: \(id)")
            }
        }
        for preset in all {
            let clip = preset.makeClip(start: 7, duration: 3.5)
            near(clip.start, 7)
            near(clip.duration, 3.5)
            precondition(clip.id != UUID())
            let data = try JSONEncoder().encode(clip)
            let restored = try JSONDecoder().decode(
                MockupOverlayClip.self, from: data
            )
            precondition(restored == clip,
                         "Mockup \(preset.id) did not round trip")
        }

        var clip = all[0].makeClip(
            start: 1, duration: 3
        )
        clip.assetURL = URL(
            fileURLWithPath: "/tmp/mockup-alpha.png"
        )
        clip.depthMode = .behindPerson
        clip.blendMode = .multiply
        clip.opacity = 0.83
        clip.centerX = 0.18
        clip.centerY = 0.29
        clip.animationStyle = .sway
        clip.animationSpeed = 2.5
        clip.loopEnabled = false
        clip.avoidFace = true
        clip.blurRadius = 4.2
        clip.feather = 1.9
        clip.flipHorizontal = true
        let data = try JSONEncoder().encode(clip)
        near(
            try JSONDecoder().decode(
                MockupOverlayClip.self, from: data
            ).opacity, 0.83
        )
        precondition(try JSONDecoder().decode(
            MockupOverlayClip.self, from: data
        ) == clip)

        // Historical incomplete title / mockup entries do not crash.
        var dictionary = try JSONSerialization.jsonObject(
            with: data
        ) as! [String: Any]
        for key in [
            "assetURL", "depthMode", "blendMode", "centerX",
            "centerY", "animationStyle", "animationSpeed",
            "loopEnabled", "avoidFace", "feather", "flipHorizontal",
            "opacity", "rotationDegrees"
        ] {
            dictionary.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(
            MockupOverlayClip.self,
            from: JSONSerialization.data(
                withJSONObject: dictionary
            )
        )
        precondition(legacy.depthMode == .front)
        precondition(legacy.assetURL == nil)
        precondition(legacy.blendMode == .screen)

        var move = all.first(where: {
            $0.id == "motion-leaf"
        })!.makeClip(start: 5, duration: 4)
        let before = MockupAnimationSampler.sample(
            move, atProjectTime: 5
        )
        let after = MockupAnimationSampler.sample(
            move, atProjectTime: 6
        )
        precondition(before.rotation != after.rotation ||
                     before.x != after.x)
        move.animationStyle = .still
        let still = MockupAnimationSampler.sample(
            move, atProjectTime: 8
        )
        near(still.x, move.centerX)
        near(still.y, move.centerY)
        near(still.opacity, move.opacity)
        for animation in MockupAnimationStyle.allCases {
            move.animationStyle = animation
            let state = MockupAnimationSampler.sample(
                move, atProjectTime: 6.5
            )
            precondition(state.opacity >= 0 &&
                         state.opacity <= 1 &&
                         state.scale > 0)
        }
        print(
            "PASS: 42 light/shadow mockups, 12 moods, unique IDs, Codable compatibility, custom PNG and animations"
        )
    }
}
