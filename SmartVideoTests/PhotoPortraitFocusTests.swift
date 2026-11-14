import Foundation
import XCTest
@testable import SmartVideo

@MainActor
final class PhotoPortraitFocusTests: XCTestCase {
    func testPortraitStylesHaveSafeDistinctIntensity() {
        let natural = PhotoPortraitFocusSettings.Style.natural.settings
        let studio = PhotoPortraitFocusSettings.Style.studio.settings
        let cinema = PhotoPortraitFocusSettings.Style.cinematic.settings
        XCTAssertTrue(natural.enabled)
        XCTAssertLessThan(natural.blurStrength, studio.blurStrength)
        XCTAssertLessThan(studio.blurStrength, cinema.blurStrength)
        XCTAssertLessThan(natural.backgroundDim, cinema.backgroundDim)
    }

    func testPortraitSettingsDecodeClampsImportedOutliers() throws {
        let json = """
        {
          "enabled": true,
          "blurStrength": 250,
          "backgroundDim": -10,
          "backgroundSaturation": 8,
          "edgeSoftness": -3,
          "subjectLiftEV": 4
        }
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(
            PhotoPortraitFocusSettings.self, from: json
        )
        XCTAssertEqual(settings.blurStrength, 1)
        XCTAssertEqual(settings.backgroundDim, 0)
        XCTAssertEqual(settings.backgroundSaturation, 1.2)
        XCTAssertEqual(settings.edgeSoftness, 0)
        XCTAssertEqual(settings.subjectLiftEV, 0.4)
    }

    func testStillImageRoundTripAndOldProjectCompatibility() throws {
        var photo = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/portrait.jpg"),
            duration: 4, originalDuration: 4
        )
        photo.portraitFocus =
            PhotoPortraitFocusSettings.Style.studio.settings
        let data = try JSONEncoder().encode(photo)
        let loaded = try JSONDecoder().decode(TimelineClip.self, from: data)
        XCTAssertEqual(loaded.portraitFocus, photo.portraitFocus)

        var old = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "portraitFocus")
        let legacy = try JSONSerialization.data(withJSONObject: old)
        let oldClip = try JSONDecoder().decode(
            TimelineClip.self, from: legacy
        )
        XCTAssertFalse(oldClip.portraitFocus.enabled)
    }

    func testPortraitFocusIsImageOnlyAndUndoable() {
        let editor = EditorViewModel()
        let photo = TimelineClip(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/portrait.jpg"),
            duration: 4, originalDuration: 4
        )
        let video = TimelineClip(
            kind: .video,
            fileURL: URL(fileURLWithPath: "/tmp/movie.mov"),
            duration: 4, originalDuration: 4
        )
        editor.clips = [photo, video]
        editor.applyPortraitFocus(
            to: photo.id,
            settings: PhotoPortraitFocusSettings.Style.cinematic.settings
        )
        XCTAssertTrue(editor.clips[0].portraitFocus.enabled)
        editor.applyPortraitFocus(
            to: video.id,
            settings: PhotoPortraitFocusSettings.Style.cinematic.settings
        )
        XCTAssertFalse(editor.clips[1].portraitFocus.enabled)
        editor.undoEdit()
        XCTAssertFalse(editor.clips[0].portraitFocus.enabled)
    }
}
