import Foundation

extension MusicVideoStudio {
    /// Spreads a line's words across its time span by letter count.
    enum LyricsWordTiming {
        static let maxLineSeconds = 8.0
        static let minLineSeconds = 0.4

        static func words(_ text: String, start: Double, end: Double) -> [LyricWord] {
            let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard !tokens.isEmpty else { return [] }
            let span = max(0.05 * Double(tokens.count), end - start)
            let weights = tokens.map { Double(max(1, $0.count)) + 1 }
            let total = weights.reduce(0, +)
            var cursor = start
            var out: [LyricWord] = []
            for (token, weight) in zip(tokens, weights) {
                let length = span * weight / total
                out.append(LyricWord(text: token, start: cursor, end: cursor + length))
                cursor += length
            }
            return out
        }
    }

    /// LRC: `[mm:ss.xx]line`, several time tags per line, the `[offset:ms]` tag,
    /// and enhanced word timing `<mm:ss.xx>word <mm:ss.xx>word`.
    enum LRCParser {
        private static let tag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
        private static let wordTag = try! NSRegularExpression(pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#)

        static func seconds(_ minutes: String, _ secs: String, _ fraction: String?) -> Double {
            let m = Double(minutes) ?? 0, s = Double(secs) ?? 0
            var f = 0.0
            if let fraction, !fraction.isEmpty, let value = Double(fraction) { f = value / pow(10, Double(fraction.count)) }
            return m * 60 + s + f
        }

        private struct Raw { var start: Double; var text: String; var words: [(Double, String)] }

        static func parse(_ text: String) -> [LyricLine] {
            var offset = 0.0
            var raws: [Raw] = []
            for original in text.components(separatedBy: .newlines) {
                let line = original.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("[") else { continue }
                let ns = line as NSString
                let matches = tag.matches(in: line, range: NSRange(location: 0, length: ns.length))
                // Leading tags only.
                var times: [Double] = []
                var cursor = 0
                for match in matches where match.range.location == cursor {
                    let g = (1...3).map { match.range(at: $0).location == NSNotFound ? nil : ns.substring(with: match.range(at: $0)) }
                    times.append(seconds(g[0] ?? "0", g[1] ?? "0", g[2]))
                    cursor = match.range.location + match.range.length
                }
                if times.isEmpty {
                    // Metadata: [offset:+500] shifts everything (positive = earlier).
                    if line.lowercased().hasPrefix("[offset:"), let close = line.firstIndex(of: "]") {
                        let value = line[line.index(line.startIndex, offsetBy: 8)..<close].trimmingCharacters(in: .whitespaces)
                        offset = (Double(value.replacingOccurrences(of: "+", with: "")) ?? 0) / 1000
                    }
                    continue
                }
                let body = ns.substring(from: cursor).trimmingCharacters(in: .whitespaces)
                let parsedWords = enhancedWords(body)
                let plain = parsedWords.isEmpty ? body : parsedWords.map(\.1).joined(separator: " ")
                for t in times { raws.append(Raw(start: t, text: plain, words: parsedWords)) }
            }
            raws.sort { $0.start < $1.start }

            var lines: [LyricLine] = []
            for (i, raw) in raws.enumerated() {
                let nextStart = i + 1 < raws.count ? raws[i + 1].start : nil
                if raw.text.isEmpty { continue }                              // an instrumental gap
                let start = max(0, raw.start - offset)
                let naturalEnd = (nextStart ?? raw.start + 4) - offset
                let end = min(start + LyricsWordTiming.maxLineSeconds, max(start + LyricsWordTiming.minLineSeconds, naturalEnd))
                if !raw.words.isEmpty {
                    var words: [LyricWord] = []
                    for (j, entry) in raw.words.enumerated() {
                        let wStart = max(0, entry.0 - offset)
                        let wEnd = j + 1 < raw.words.count ? max(wStart + 0.02, raw.words[j + 1].0 - offset) : max(wStart + 0.05, end)
                        words.append(LyricWord(text: entry.1, start: wStart, end: wEnd))
                    }
                    lines.append(LyricLine(words: words))
                } else {
                    lines.append(LyricLine(words: LyricsWordTiming.words(raw.text, start: start, end: end)))
                }
            }
            return lines
        }

        /// `<00:01.20>Hello <00:01.80>world` -> [(1.2, "Hello"), (1.8, "world")]
        private static func enhancedWords(_ body: String) -> [(Double, String)] {
            let ns = body as NSString
            let matches = wordTag.matches(in: body, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { return [] }
            var out: [(Double, String)] = []
            for (i, match) in matches.enumerated() {
                let g = (1...3).map { match.range(at: $0).location == NSNotFound ? nil : ns.substring(with: match.range(at: $0)) }
                let time = seconds(g[0] ?? "0", g[1] ?? "0", g[2])
                let from = match.range.location + match.range.length
                let to = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
                let word = ns.substring(with: NSRange(location: from, length: to - from)).trimmingCharacters(in: .whitespaces)
                if !word.isEmpty { out.append((time, word)) }
            }
            return out
        }
    }

    /// Writes enhanced LRC (a line time tag plus a tag per word).
    enum LRCWriter {
        static func stamp(_ seconds: Double) -> String {
            let total = max(0, Int((seconds * 100).rounded()))
            return String(format: "%02ld:%02ld.%02ld", total / 6000, (total / 100) % 60, total % 100)
        }

        static func string(_ lines: [LyricLine], title: String? = nil) -> String {
            var out: [String] = []
            if let title { out.append("[ti:\(title)]") }
            for line in lines {
                let words = line.words.map { "<\(stamp($0.start))>\($0.text)" }.joined(separator: " ")
                out.append("[\(stamp(line.start))]\(words)")
            }
            return out.joined(separator: "\n") + "\n"
        }
    }

    enum SRTParser {
        private static let time = try! NSRegularExpression(
            pattern: #"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})"#)

        static func parse(_ text: String) -> [LyricLine] {
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            var lines: [LyricLine] = []
            for block in normalized.components(separatedBy: "\n\n") {
                let rows = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                guard let timeRow = rows.first(where: { $0.contains("-->") }),
                      let match = time.firstMatch(in: timeRow, range: NSRange(location: 0, length: (timeRow as NSString).length)) else { continue }
                let ns = timeRow as NSString
                func part(_ i: Int) -> String { ns.substring(with: match.range(at: i)) }
                func stamp(_ h: Int) -> Double {
                    (Double(part(h)) ?? 0) * 3600 + (Double(part(h + 1)) ?? 0) * 60 + (Double(part(h + 2)) ?? 0)
                        + (Double(part(h + 3)) ?? 0) / pow(10, Double(part(h + 3).count))
                }
                let start = stamp(1), end = stamp(5)
                guard end > start, let index = rows.firstIndex(of: timeRow) else { continue }
                let body = rows[(index + 1)...].joined(separator: " ")
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                let words = LyricsWordTiming.words(body, start: start, end: end)
                if !words.isEmpty { lines.append(LyricLine(words: words)) }
            }
            return lines.sorted { $0.start < $1.start }
        }
    }

    /// Plain typed or pasted lyrics (no timestamps): spread over a time range by word count.
    enum PlainLyrics {
        static func distribute(_ text: String, start: Double, duration: Double) -> [LyricLine] {
            let rows = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let counts = rows.map { max(1, $0.split(whereSeparator: { $0.isWhitespace }).count) }
            let total = Double(counts.reduce(0, +))
            guard total > 0, duration > 0 else { return [] }
            var cursor = start
            var lines: [LyricLine] = []
            for (row, count) in zip(rows, counts) {
                let length = duration * Double(count) / total
                lines.append(LyricLine(words: LyricsWordTiming.words(row, start: cursor, end: cursor + length)))
                cursor += length
            }
            return lines
        }
    }
}
