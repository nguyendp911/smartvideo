import SwiftUI

/// Word-aware SwiftUI preview using the same timestamp metadata as export.
/// Changing the entire caption text disables outdated karaoke timing.
struct KaraokeSubtitlePreview: View {
    let text: String
    let cue: SubtitleCue?
    let appearance: SubtitleAppearance
    let playhead: Double

    var body: some View {
        renderedText
            .animation(.easeOut(duration: 0.08), value: activeWordIndex)
    }

    private var activeWordIndex: Int {
        guard let cue, appearance.karaokeEnabled,
              cue.hasAlignedWords else { return -1 }
        return cue.words.firstIndex(where: {
            playhead >= $0.start && playhead < $0.end
        }) ?? -1
    }

    private var renderedText: Text {
        guard let cue, appearance.karaokeEnabled,
              cue.hasAlignedWords else {
            return Text(text)
        }
        let activeColor = Color(uiColor:
            TextOverlayRenderer.uiColor(hex: appearance.karaokeHex))
        let baseColor = Color(uiColor:
            TextOverlayRenderer.uiColor(hex: appearance.foregroundHex))
        var combined = Text("")
        for (index, word) in cue.words.enumerated() {
            let part = Text((index == 0 ? "" : " ") + word.text)
                .foregroundColor(index == activeWordIndex ?
                                 activeColor : baseColor)
                .fontWeight(index == activeWordIndex ? .heavy : .semibold)
            combined = combined + part
        }
        return combined
    }
}
