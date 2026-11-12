import Foundation

@main
struct MockupLightShadowTests {
    static func main() throws {
        precondition(MockupAssetLibrary.all.count == 42)
        precondition(MockupPreset.all.count == 12)
        precondition(Set(MockupAssetLibrary.all.map(\.id)).count == 42)
        for preset in MockupPreset.all {
            precondition(!preset.ids.isEmpty)
            for id in preset.ids {
                precondition(MockupAssetLibrary.asset(id) != nil)
            }
        }
        for asset in MockupAssetLibrary.all {
            let clip = MockupAssetLibrary.makeClip(
                asset, at: 2.4, duration: 5
            )
            precondition(clip.start == 2.4)
            precondition(clip.duration == 5)
            precondition(clip.blendMode == asset.recommendedBlend)
            precondition(!MockupAnimationSampler.active(clip, at: 2.3))
            precondition(MockupAnimationSampler.active(clip, at: 2.5))
            precondition(!MockupAnimationSampler.active(clip, at: 7.4))
            let json = try JSONEncoder().encode(clip)
            let restored = try JSONDecoder().decode(
                MockupOverlayClip.self, from: json
            )
            precondition(clip == restored)
            let state = MockupAnimationSampler.sample(
                clip, at: 3.1
            )
            precondition(state.x.isFinite && state.y.isFinite)
            precondition(state.scale > 0)
            precondition(state.opacity >= 0 && state.opacity <= 1)
        }
        var sample = MockupOverlayClip()
        sample.depthMode = .behindPerson
        sample.animationStyle = .sway
        sample.flipHorizontal = true
        sample.opacity = 0.83
        sample.scale = 1.75
        let copy = try JSONDecoder().decode(
            MockupOverlayClip.self,
            from: JSONEncoder().encode(sample)
        )
        precondition(copy == sample)
        print("PASS: 42 procedural mockups, 12 presets, blend/depth, timeline and animation Codable tests")
    }
}
