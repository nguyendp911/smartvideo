import Foundation

extension MusicVideoStudio {
    /// How lyric time relates to project time.
    enum LyricsTiming {
        /// Seconds to ADD to a word's time (in the audio file) to get project time.
        /// With a linked audio clip it follows that clip's position and trim, so moving
        /// or trimming the music keeps the lyrics synchronised automatically.
        static func offset(_ layer: LyricsLayer, in project: VideoProject) -> Double {
            if let id = layer.audioLayerID, let audio = project.audios.first(where: { $0.core.id == id }) {
                return audio.core.start.seconds - audio.sourceStart
            }
            return layer.core.start.seconds
        }

        static func sourceTime(_ layer: LyricsLayer, in project: VideoProject, at time: ProjectTime) -> Double {
            time.seconds - offset(layer, in: project)
        }
    }

    /// Pure maths behind every karaoke effect: a function of time only.
    enum KaraokeMath {
        static func smooth(_ x: Double) -> Double {
            let t = min(1, max(0, x.isFinite ? x : 0))
            return t * t * (3 - 2 * t)
        }

        /// Progress 0...1 of a word at source time `t`.
        static func progress(_ word: LyricWord, at t: Double) -> Double {
            guard word.end > word.start else { return t >= word.start ? 1 : 0 }
            return min(1, max(0, (t - word.start) / (word.end - word.start)))
        }

        /// The line to show: the latest line that has started and not been over for more
        /// than `hold` seconds, otherwise the next line if it starts within `lead` seconds.
        static func currentLine(_ lines: [LyricLine], at t: Double, hold: Double = 1.2, lead: Double = 1.5) -> Int? {
            var current: Int?
            for (i, line) in lines.enumerated() where line.start <= t { current = i }
            if let current, t < lines[current].end + hold { return current }
            if let next = lines.firstIndex(where: { $0.start > t }), lines[next].start - t <= lead { return next }
            return nil
        }

        struct WordStyle: Equatable {
            /// 0 = normal colour ... 1 = highlight colour.
            var colorMix = 0.0
            /// 0...1 left-to-right fill (Fill animation only; otherwise equals colorMix).
            var fill = 0.0
            var glow = 0.0
            var scale = 1.0
            var opacity = 1.0
            /// Characters shown (typewriter); nil = all.
            var visibleCharacters: Int?
        }

        static let colorBlend = 0.12

        static func style(_ animation: LyricAnimation, word: LyricWord, at t: Double) -> WordStyle {
            let p = progress(word, at: t)
            let started = t >= word.start
            let done = t >= word.end
            let blend = smooth((t - word.start) / colorBlend)              // smooth colour transition
            let bell = sin(Double.pi * p)                                  // 0 -> 1 -> 0 while the word is sung
            switch animation {
            case .fill:
                return WordStyle(colorMix: done ? 1 : 0, fill: p)
            case .highlight:
                return WordStyle(colorMix: started ? blend : 0, fill: started ? 1 : 0)
            case .glow:
                return WordStyle(colorMix: started ? blend : 0, fill: started ? 1 : 0,
                                 glow: started ? (done ? 0.35 : 0.35 + 0.65 * bell) : 0)
            case .scale:
                return WordStyle(colorMix: started ? blend : 0, fill: started ? 1 : 0,
                                 scale: started && !done ? 1 + 0.22 * bell : 1)
            case .fade:
                return WordStyle(colorMix: started ? blend : 0, fill: started ? 1 : 0, opacity: 0.35 + 0.65 * smooth(p))
            case .typewriter:
                let count = max(0, Int((p * Double(word.text.count)).rounded(.up)))
                return WordStyle(colorMix: started ? blend : 0, fill: started ? 1 : 0,
                                 visibleCharacters: started ? min(word.text.count, count) : 0)
            }
        }
    }
}
