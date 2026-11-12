import Foundation

@main
struct MultiMusicRegionTests {
    static func near(
        _ actual: Double, _ expected: Double,
        precision: Double = 0.002
    ) {
        precondition(actual.isFinite &&
            abs(actual - expected) < precision,
            "Expected \(expected), found \(actual)")
    }

    static func main() throws {
        let url = URL(fileURLWithPath: "/tmp/song-one.m4a")
        let frames = [
            AudioGainKeyframe(progress: 0.25, gain: 0.2),
            AudioGainKeyframe(progress: 0.75, gain: 0.8)
        ]
        let music = MusicRegionEditMath.fromLegacy(
            url: url,
            fileDuration: 110,
            sourceStart: 20,
            highlightDuration: 18,
            timelineStart: 6,
            projectDuration: 40,
            volume: 0.4,
            fadeIn: 0.5,
            fadeOut: 0.75,
            frames: frames
        )!
        near(music.start, 6)
        near(music.sourceStart, 20)
        near(music.duration, 18)
        near(Double(music.volume), 0.4)
        precondition(music.volumeKeyframes.count == 2)
        precondition(music.fileURL == url)

        let copies = MusicRegionEditMath.duplicate(
            music, at: 24, projectDuration: 40
        )
        near(copies.start, 22)
        precondition(copies.id != music.id)
        precondition(copies.volumeKeyframes[0].id !=
                     music.volumeKeyframes[0].id)
        precondition(copies.volumeKeyframes[0].gain ==
                     music.volumeKeyframes[0].gain)
        precondition(copies.fileURL == music.fileURL)

        let parts = MusicRegionEditMath.split(
            music, at: music.start + 9
        )!
        near(parts.left.duration, 9)
        near(parts.right.duration, 9)
        near(parts.right.start, 15)
        near(parts.right.sourceStart, 29)
        near(parts.left.fadeOut, 0)
        near(parts.right.fadeIn, 0)
        near(parts.left.fadeIn, music.fadeIn)
        near(parts.right.fadeOut, music.fadeOut)
        near(Double(AudioAutomationMath.factor(
            at: 1, frames: parts.left.volumeKeyframes
        )), 0.5)
        near(Double(AudioAutomationMath.factor(
            at: 0, frames: parts.right.volumeKeyframes
        )), 0.5)
        precondition(parts.right.id != music.id)

        precondition(MusicRegionEditMath.split(
            music, at: music.start
        ) == nil)
        precondition(MusicRegionEditMath.split(
            music, at: music.end
        ) == nil)
        precondition(MusicRegionEditMath.fromLegacy(
            url: url, fileDuration: .nan,
            sourceStart: 0, highlightDuration: 0,
            timelineStart: 0, projectDuration: 40,
            volume: 0.4, fadeIn: 0, fadeOut: 0, frames: []
        ) == nil)
        let clipped = MusicRegionEditMath.fromLegacy(
            url: url, fileDuration: 10,
            sourceStart: 8, highlightDuration: 0,
            timelineStart: 9, projectDuration: 10,
            volume: 1, fadeIn: 0, fadeOut: 0, frames: []
        )!
        near(clipped.duration, 1)

        let encoded = try JSONEncoder().encode(music)
        let decoded = try JSONDecoder().decode(
            SoundEffectClip.self, from: encoded
        )
        precondition(decoded == music)
        var legacy = try JSONSerialization.jsonObject(
            with: encoded
        ) as! [String: Any]
        legacy.removeValue(forKey: "volumeKeyframes")
        let bytes = try JSONSerialization.data(
            withJSONObject: legacy
        )
        precondition(try JSONDecoder().decode(
            SoundEffectClip.self, from: bytes
        ).volumeKeyframes.isEmpty)
        print("PASS: independent music trim, paste/duplicate identities, split gain continuity, bounds and Codable")
    }
}
