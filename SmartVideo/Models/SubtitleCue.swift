import Foundation

/// Timing is always in *global video timeline* seconds, not file offsets.
struct SubtitleWord: Codable, Equatable {
    var start: Double
    var end: Double
    var text: String
}

struct SubtitleCue: Identifiable, Equatable, Codable {
    var id: UUID
    var start: Double
    var end: Double
    var text: String
    var words: [SubtitleWord]

    init(id: UUID = UUID(), start: Double, end: Double,
         text: String, words: [SubtitleWord] = []) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, text, words
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try fields.decode(Double.self, forKey: .start)
        end = try fields.decode(Double.self, forKey: .end)
        text = try fields.decode(String.self, forKey: .text)
        words = try fields.decodeIfPresent([SubtitleWord].self, forKey: .words) ?? []
    }

    var hasAlignedWords: Bool {
        guard !words.isEmpty else { return false }
        // If the user manually rewrote the caption, do not play the
        // outdated word timing against unrelated text.
        return Self.cleaned(words.map(\.text).joined(separator: " ")) ==
            Self.cleaned(text)
    }

    private static func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " !", with: "!")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SubtitleFile {
    static func parse(_ data: Data, filename: String, videoDuration: Double) throws -> [SubtitleCue] {
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16) else {
            throw SmartVideoError.invalidMedia("Phụ đề phải được lưu dưới dạng văn bản UTF-8 hoặc UTF-16.")
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        let blocks = normalized.components(separatedBy: "\n\n")
        var parsed: [SubtitleCue] = []

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard let lineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = lines[lineIndex].components(separatedBy: "-->")
            guard times.count == 2, let begin = parseTime(times[0]),
                  let finish = parseTime(times[1]), finish > begin else { continue }
            let caption = lines.dropFirst(lineIndex + 1)
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !caption.isEmpty {
                parsed.append(SubtitleCue(start: begin, end: finish, text: caption))
            }
        }
        if !parsed.isEmpty {
            return parsed.sorted { $0.start < $1.start }
        }

        let lines = normalized.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }
        let duration = max(1, videoDuration)
        let lineWindow = duration / Double(lines.count)
        return lines.enumerated().map { idx, caption in
            let start = Double(idx) * lineWindow
            return SubtitleCue(start: start,
                               end: min(duration, start + min(lineWindow, 5.5)),
                               text: caption)
        }
    }

    static func makeSRT(_ cues: [SubtitleCue]) -> String {
        cues.sorted { $0.start < $1.start }.enumerated().map { index, cue in
            "\(index + 1)\n\(timecode(cue.start)) --> \(timecode(cue.end))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    private static func parseTime(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let pattern = #"(?:([0-9]{1,2}):)?([0-9]{1,2}):([0-9]{2})[,.]([0-9]{1,3})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func component(_ index: Int) -> Double {
            guard let range = Range(match.range(at: index), in: text) else { return 0 }
            return Double(text[range]) ?? 0
        }
        let milliseconds = component(4)
        let digits = match.range(at: 4).length
        return component(1) * 3600 + component(2) * 60 + component(3)
            + milliseconds / pow(10, Double(digits))
    }

    private static func timecode(_ seconds: Double) -> String {
        let ms = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d,%03d",
                      ms / 3_600_000, (ms / 60_000) % 60,
                      (ms / 1000) % 60, ms % 1000)
    }
}
