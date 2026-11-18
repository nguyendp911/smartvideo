import SwiftUI

extension MusicVideoStudio {
    /// Transport: scrub bar, frame stepping, play/pause, loop and time read-outs.
    struct PlaybackControlsView: View {
        @ObservedObject var playback: PlaybackEngine
        @State private var resumeAfterScrub = false
        @State private var scrubbing = false

        var body: some View {
            let state = playback.state
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { state.progress },
                        set: { value in
                            playback.seek(to: ProjectTime(ticks: Int64(value * Double(state.duration.ticks))))
                        }),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if editing {
                            resumeAfterScrub = playback.isPlaying
                            scrubbing = true
                            playback.pause()
                        } else {
                            scrubbing = false
                            if resumeAfterScrub { playback.play() }
                        }
                    })
                .tint(.cyan)
                .accessibilityLabel("Thanh tua")

                HStack(spacing: 14) {
                    Text(state.frameTime.timecode(fps: state.fps))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(minWidth: 86, alignment: .leading)
                    Spacer(minLength: 0)
                    Button { playback.goToStart() } label: { Image(systemName: "backward.end.fill") }
                        .accessibilityLabel("Về đầu")
                    Button { playback.step(frames: -1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Lùi một khung hình")
                    Button { playback.toggle() } label: {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                            .frame(width: 44, height: 34)
                    }
                    .accessibilityLabel(state.isPlaying ? "Tạm dừng" : "Phát")
                    Button { playback.step(frames: 1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Tiến một khung hình")
                    Button { playback.goToEnd() } label: { Image(systemName: "forward.end.fill") }
                        .accessibilityLabel("Đến cuối")
                    Spacer(minLength: 0)
                    Button { playback.setLoops(!state.loops) } label: {
                        Image(systemName: "repeat").foregroundStyle(state.loops ? Color.cyan : .secondary)
                    }
                    .accessibilityLabel(state.loops ? "Tắt lặp" : "Bật lặp")
                    Text(state.duration.timecode(fps: state.fps))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .font(.system(size: 16))
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}
