import Foundation

extension MusicVideoStudio {
    /// A word heard by a speech/music recogniser: provider independent.
    struct RecognizedWord: Equatable {
        var text: String
        var start: Double
        var end: Double
    }

    /// Pure editing of lyric timings (seconds in the audio file's time).
    enum LyricsSynchronizer {
        static let minWord = 0.03

        /// Moves every word by `seconds` (never before 0).
        static func shift(_ lines: [LyricLine], by seconds: Double) -> [LyricLine] {
            guard seconds.isFinite, let first = lines.first?.start else { return lines }
            let delta = max(seconds, -first)
            return lines.map { line in
                var line = line
                for i in line.words.indices { line.words[i].start += delta; line.words[i].end += delta }
                return line
            }
        }

        /// Moves a whole line, keeping its word durations (and staying >= 0).
        static func moveLine(_ lines: [LyricLine], index: Int, toStart start: Double) -> [LyricLine] {
            guard lines.indices.contains(index), start.isFinite else { return lines }
            var out = lines
            let delta = max(0, start) - out[index].start
            for i in out[index].words.indices { out[index].words[i].start += delta; out[index].words[i].end += delta }
            return out
        }

        /// Drags the boundary in front of word `word` of `line`: it becomes that
        /// word's start and, when the previous word touched it, that word's end.
        static func moveBoundary(_ lines: [LyricLine], line: Int, word: Int, to time: Double) -> [LyricLine] {
            guard lines.indices.contains(line), lines[line].words.indices.contains(word), time.isFinite else { return lines }
            var out = lines
            var words = out[line].words
            let previous: LyricWord? = word > 0 ? words[word - 1] : (line > 0 ? out[line - 1].words.last : nil)
            let lower = (previous?.start ?? 0) + minWord
            let upper = words[word].end - minWord
            guard upper >= lower else { return lines }
            let t = min(upper, max(lower, time))
            let oldStart = words[word].start
            words[word].start = t
            if word > 0, abs(words[word - 1].end - oldStart) < 0.06 { words[word - 1].end = t }
            out[line].words = words
            if word == 0, line > 0, let last = out[line - 1].words.last, abs(last.end - oldStart) < 0.06 {
                out[line - 1].words[out[line - 1].words.count - 1].end = t
            }
            return out
        }

        static func setWordEnd(_ lines: [LyricLine], line: Int, word: Int, to time: Double) -> [LyricLine] {
            guard lines.indices.contains(line), lines[line].words.indices.contains(word), time.isFinite else { return lines }
            var out = lines
            let start = out[line].words[word].start
            out[line].words[word].end = max(start + minWord, time)
            return out
        }

        /// Turns tap times into word timings. Taps go to the words in order; a word ends
        /// at the next tap, or half a second after its own tap if the next one is far away.
        static func tapSync(_ lines: [LyricLine], taps: [Double]) -> [LyricLine] {
            var out = lines
            var index = 0
            for l in out.indices {
                for w in out[l].words.indices {
                    guard index < taps.count else { return out }
                    let start = max(0, taps[index])
                    var end = index + 1 < taps.count ? taps[index + 1] : start + 0.5
                    if end <= start || end - start > 1.6 { end = start + 0.5 }        // a pause: the word was short
                    out[l].words[w].start = start
                    out[l].words[w].end = max(start + minWord, end)
                    index += 1
                }
            }
            return out
        }

        /// Keeps words ordered and at least `minWord` long. Run after any bulk edit.
        static func normalized(_ lines: [LyricLine]) -> [LyricLine] {
            var out = lines
            var floorTime = 0.0
            for l in out.indices {
                for w in out[l].words.indices {
                    out[l].words[w].start = max(floorTime, max(0, out[l].words[w].start))
                    out[l].words[w].end = max(out[l].words[w].start + minWord, out[l].words[w].end)
                    floorTime = out[l].words[w].start
                }
            }
            return out
        }
    }

    /// Easier ways to time lyrics: ONE tap per line instead of one per word, and on the music's beats.
    /// All times are seconds of the audio FILE, like the words themselves.
    enum LyricsBeatSync {
        /// Rough singing time of a line (used when nothing says when it ends).
        static func estimatedSeconds(_ line: LyricLine) -> Double {
            min(LyricsWordTiming.maxLineSeconds, max(1.5, 0.35 * Double(line.words.count) + 0.8))
        }

        /// `taps[i]` = when line i starts. A line ends where the next starts (or after its estimated
        /// length when the gap is an instrumental break). Words are spread by letter count.
        static func tapLines(_ lines: [LyricLine], taps: [Double]) -> [LyricLine] {
            var starts: [Double] = []
            for tap in taps where tap.isFinite {
                if let last = starts.last, tap < last + 0.1 { continue }                  // a double tap
                starts.append(max(0, tap))
            }
            var out = lines
            for i in out.indices where i < starts.count {
                let start = starts[i]
                var end = start + estimatedSeconds(out[i])
                if i + 1 < starts.count, starts[i + 1] - start <= LyricsWordTiming.maxLineSeconds { end = starts[i + 1] }
                let words = LyricsWordTiming.words(out[i].text, start: start, end: end)
                if !words.isEmpty { out[i].words = words }
            }
            return out
        }

        /// Median distance between beats (0 when there are fewer than two).
        static func interval(_ beats: [Double]) -> Double {
            guard beats.count >= 2 else { return 0 }
            let gaps = zip(beats, beats.dropFirst()).map { $1 - $0 }.sorted()
            return gaps[gaps.count / 2]
        }

        /// Index of the first beat at or after `time`.
        static func firstBeatIndex(atOrAfter time: Double, beats: [Double]) -> Int? {
            beats.firstIndex { $0 >= time - 0.02 }
        }

        /// Each line starts on a beat, `beatsPerLine` beats apart, beginning at `beats[firstBeat]`.
        /// Past the last known beat the song's median beat length is extended.
        static func distributeOnBeats(rows: [String], beats: [Double], beatsPerLine: Int, firstBeat: Int) -> [LyricLine] {
            let clean = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let step = interval(beats)
            guard !clean.isEmpty, beats.count >= 2, step > 0, let lastBeat = beats.last else { return [] }
            let per = max(1, beatsPerLine)
            let first = min(max(0, firstBeat), beats.count - 1)
            func start(_ i: Int) -> Double {
                let index = first + i * per
                return index < beats.count ? beats[index] : lastBeat + Double(index - (beats.count - 1)) * step
            }
            var lines: [LyricLine] = []
            for (i, row) in clean.enumerated() {
                let words = LyricsWordTiming.words(row, start: start(i), end: i + 1 < clean.count ? start(i + 1) : start(i) + Double(per) * step)
                if !words.isEmpty { lines.append(LyricLine(words: words)) }
            }
            return lines
        }

        /// The beat nearest to `time` within `threshold`, else `time` itself.
        static func snapTime(_ time: Double, beats: [Double], threshold: Double) -> Double {
            guard time.isFinite else { return time }
            var best = time, distance = threshold
            for beat in beats where abs(beat - time) <= distance { best = beat; distance = abs(beat - time) }
            return best
        }

        /// The next beat after (`forward`) or before `time`, at least 20 ms away.
        static func neighbor(of time: Double, beats: [Double], forward: Bool) -> Double? {
            forward ? beats.first { $0 > time + 0.02 } : beats.last { $0 < time - 0.02 }
        }

        /// Moves each line start to the nearest beat within `window`; a line keeps its length unless
        /// that would run into the next line (then it is squeezed). Word positions scale with the line.
        static func snapLines(_ lines: [LyricLine], beats: [Double], window: Double = 0.25) -> [LyricLine] {
            guard !beats.isEmpty, !lines.isEmpty else { return lines }
            var starts: [Double] = []
            for line in lines {
                var s = snapTime(line.start, beats: beats, threshold: window)
                if let previous = starts.last, s < previous + 0.2 { s = max(previous + 0.2, line.start) }
                starts.append(s)
            }
            var out = lines
            for i in out.indices {
                let old = lines[i]
                let oldLength = max(0.05, old.end - old.start)
                var newLength = oldLength
                if i + 1 < starts.count { newLength = min(oldLength, max(0.1, starts[i + 1] - starts[i])) }
                let scale = newLength / oldLength
                for w in out[i].words.indices {
                    out[i].words[w].start = starts[i] + (old.words[w].start - old.start) * scale
                    out[i].words[w].end = starts[i] + (old.words[w].end - old.start) * scale
                }
            }
            return LyricsSynchronizer.normalized(out)
        }
    }

    /// Maps lyric TEXT onto recognised, timed words (a light forced alignment):
    /// a global sequence alignment of normalised words, with timings interpolated
    /// for text words the recogniser missed. Independent of which recogniser
    /// produced `recognized`.
    enum LyricsAligner {
        static func normalize(_ word: String) -> String {
            word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
                .replacingOccurrences(of: "đ", with: "d")
                .filter { $0.isLetter || $0.isNumber }
        }

        /// `rows` are the lyric lines as typed.
        static func align(rows: [String], recognized: [RecognizedWord]) -> [LyricLine] {
            let textWords: [[String]] = rows.map { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            let flat = textWords.flatMap { $0 }
            guard !flat.isEmpty else { return [] }
            guard !recognized.isEmpty else { return [] }
            let a = flat.map(normalize), b = recognized.map { normalize($0.text) }

            // Needleman-Wunsch: match = +2 (equal), mismatch = -1, gap = -1.
            let n = a.count, m = b.count
            var score = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
            for i in 0...n { score[i][0] = -i }
            for j in 0...m { score[0][j] = -j }
            func similar(_ x: String, _ y: String) -> Bool { !x.isEmpty && (x == y || (x.count > 3 && y.count > 3 && (x.hasPrefix(y) || y.hasPrefix(x)))) }
            for i in 1...n {
                for j in 1...m {
                    let diagonal = score[i - 1][j - 1] + (similar(a[i - 1], b[j - 1]) ? 2 : -1)
                    score[i][j] = max(diagonal, score[i - 1][j] - 1, score[i][j - 1] - 1)
                }
            }
            var matched = [Int?](repeating: nil, count: n)
            var i = n, j = m
            while i > 0, j > 0 {
                let isMatch = similar(a[i - 1], b[j - 1])
                if score[i][j] == score[i - 1][j - 1] + (isMatch ? 2 : -1) {
                    if isMatch { matched[i - 1] = j - 1 }
                    i -= 1; j -= 1
                } else if score[i][j] == score[i - 1][j] - 1 { i -= 1 }
                else { j -= 1 }
            }

            // Anchors (matched words) -> times; interpolate the rest between anchors.
            var starts = [Double?](repeating: nil, count: n), ends = [Double?](repeating: nil, count: n)
            for (k, index) in matched.enumerated() {
                if let index { starts[k] = recognized[index].start; ends[k] = recognized[index].end }
            }
            let anchors = starts.indices.filter { starts[$0] != nil }
            guard !anchors.isEmpty else { return [] }
            func fill(from lo: Int, to hi: Int, t0: Double, t1: Double) {
                guard hi >= lo else { return }
                let count = hi - lo + 1
                let step = (t1 - t0) / Double(count)
                for k in 0..<count {
                    starts[lo + k] = t0 + step * Double(k)
                    ends[lo + k] = t0 + step * Double(k + 1)
                }
            }
            if let first = anchors.first, first > 0, let s = starts[first] { fill(from: 0, to: first - 1, t0: max(0, s - 0.4 * Double(first)), t1: s) }
            for (x, y) in zip(anchors, anchors.dropFirst()) where y - x > 1 {
                fill(from: x + 1, to: y - 1, t0: ends[x] ?? starts[x]!, t1: starts[y]!)
            }
            if let last = anchors.last, last < n - 1 { fill(from: last + 1, to: n - 1, t0: ends[last] ?? starts[last]!, t1: (ends[last] ?? starts[last]!) + 0.4 * Double(n - 1 - last)) }

            var lines: [LyricLine] = []
            var cursor = 0
            for words in textWords where !words.isEmpty {
                var line: [LyricWord] = []
                for text in words {
                    let s = starts[cursor] ?? 0
                    line.append(LyricWord(text: text, start: s, end: max(s + LyricsSynchronizer.minWord, ends[cursor] ?? s + 0.3)))
                    cursor += 1
                }
                lines.append(LyricLine(words: line))
            }
            return LyricsSynchronizer.normalized(lines)
        }

        /// Groups recognised words into lines at pauses (> `gap` seconds) or after `maxWords`.
        static func lines(from recognized: [RecognizedWord], gap: Double = 0.8, maxWords: Int = 9) -> [LyricLine] {
            var lines: [LyricLine] = []
            var current: [LyricWord] = []
            for word in recognized {
                if let last = current.last, word.start - last.end > gap || current.count >= maxWords {
                    lines.append(LyricLine(words: current)); current = []
                }
                current.append(LyricWord(text: word.text, start: word.start, end: max(word.end, word.start + LyricsSynchronizer.minWord)))
            }
            if !current.isEmpty { lines.append(LyricLine(words: current)) }
            return lines
        }
    }
}
