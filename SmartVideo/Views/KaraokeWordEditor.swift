import SwiftUI

/// Fine-tune the text and time of the *recognized words* without discarding
/// the Apple Speech timestamps. Editing the whole caption separately can
/// invalidate timing; that mismatch is explicitly shown.
struct KaraokeWordEditor: View {
    @Binding var cue: SubtitleCue

    var body: some View {
        DisclosureGroup {
            if !cue.hasAlignedWords {
                Text("Nội dung câu đã thay đổi. Karaoke của câu này tạm tắt " +
                     "để không làm sáng sai từ.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Button("Đồng bộ nội dung nếu số từ không đổi") {
                    synchronizeText()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .disabled(cue.text.split(whereSeparator: { $0.isWhitespace }).count !=
                          cue.words.count)
            }

            ForEach(Array(cue.words.indices), id: \.self) { index in
                wordRow(index: index)
            }
            Text("Nút ± dời thời gian của riêng từ đó 0,05 giây. " +
                 "Các mốc được giới hạn trong thời gian hiển thị của câu.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } label: {
            Label("Chỉnh karaoke từng từ (\(cue.words.count))",
                  systemImage: "text.cursor")
                .font(.caption2.bold())
        }
        .tint(.cyan)
    }

    private func wordRow(index: Int) -> some View {
        HStack(spacing: 6) {
            TextField("Từ", text: Binding(
                get: { cue.words[index].text },
                set: { updated in
                    cue.words[index].text = updated
                    updateCaptionFromWords()
                }
            ))
            .font(.caption)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)

            Text(String(format: "%.2fs", cue.words[index].start))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                shift(index, by: -0.05)
            } label: { Image(systemName: "minus") }
                .buttonStyle(.bordered)

            Button {
                shift(index, by: 0.05)
            } label: { Image(systemName: "plus") }
                .buttonStyle(.bordered)
        }
    }

    private func shift(_ index: Int, by amount: Double) {
        guard cue.words.indices.contains(index) else { return }
        let word = cue.words[index]
        let adjusted = min(
            max(amount, cue.start - word.start),
            cue.end - word.end
        )
        cue.words[index].start = word.start + adjusted
        cue.words[index].end = word.end + adjusted
    }

    private func synchronizeText() {
        let tokens = cue.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count == cue.words.count else { return }
        for index in tokens.indices {
            cue.words[index].text = tokens[index]
        }
        updateCaptionFromWords()
    }

    private func updateCaptionFromWords() {
        cue.text = cue.words.map(\.text)
            .joined(separator: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " !", with: "!")
    }
}
