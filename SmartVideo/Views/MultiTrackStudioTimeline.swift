import SwiftUI
import AVFoundation

/// Professional-style shared horizontal viewport: video, music, voice and
/// independently movable FX use the exact same pixels-per-project-second.
/// Audio rows scroll vertically without moving the pinned video preview.
struct MultiTrackStudioTimeline: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @Binding var selectedSoundID: UUID?
    let onSelectClip: (TimelineClip, Int) -> Void
    let onSelectSound: (SoundEffectClip) -> Void
    let onSelectProjectAudio: (ProjectAudioLane) -> Void
    let onScrub: (Double) -> Void

    @State private var snapToBeat = true
    @State private var voiceDurationSeconds: Double = 0
    private let labelWidth: CGFloat = 36

    private var audioRowCount: Int {
        (model.musicURL == nil ? 0 : 1) +
        (model.voiceoverURL == nil ? 0 : 1) +
        model.soundEffects.count
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(0.1, model.totalDuration)
            let trackWidth = CGFloat(AudioTimelineMath.contentWidth(
                duration: total, zoom: model.timelineZoom,
                viewportWidth: Double(max(10, geo.size.width - labelWidth))
            ))
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 3) {
                    ruler(width: trackWidth, total: total)
                    videoLane(width: trackWidth, total: total)
                    if audioRowCount > 0 {
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                if let music = model.musicURL {
                                    trackLane(
                                        tag: "♪", title: model.repeatShortMusic ?
                                            "Nhạc · lặp" : "Nhạc",
                                        url: music, sourceStart: model.musicStartSeconds,
                                        start: model.musicTimelineOffset,
                                        duration: musicSpan(total),
                                        total: total, width: trackWidth,
                                        tint: .green,
                                        frames: model.musicVolumeKeyframes,
                                        selected: false,
                                        onSelect: {
                                            onSelectProjectAudio(.music)
                                        },
                                        onBeginMove: {
                                            model.beginSoundEffectsEdit()
                                            onSelectProjectAudio(.music)
                                        },
                                        onMove: { second in
                                            model.projectAudioMove(
                                                .music, to: second,
                                                recordUndo: false
                                            )
                                        },
                                        effectID: nil,
                                        projectAudioLane: .music
                                    )
                                }
                                if let voice = model.voiceoverURL {
                                    trackLane(
                                        tag: "🎙", title: "Giọng đọc",
                                        url: voice, sourceStart: 0,
                                        start: min(total, max(0, model.voiceoverOffset)),
                                        duration: max(0.1, min(
                                            total - model.voiceoverOffset,
                                            voiceDurationSeconds > 0 ?
                                                voiceDurationSeconds : total
                                        )),
                                        total: total, width: trackWidth,
                                        tint: .purple,
                                        frames: model.voiceVolumeKeyframes,
                                        selected: false,
                                        onSelect: {
                                            onSelectProjectAudio(.narration)
                                        },
                                        onBeginMove: {
                                            model.beginSoundEffectsEdit()
                                            onSelectProjectAudio(.narration)
                                        },
                                        onMove: { second in
                                            model.projectAudioMove(
                                                .narration, to: second,
                                                recordUndo: false
                                            )
                                        },
                                        effectID: nil,
                                        projectAudioLane: .narration
                                    )
                                }
                                ForEach(Array(model.soundEffects.enumerated()),
                                        id: \.element.id) { index, effect in
                                    trackLane(
                                        tag: "F\(index + 1)",
                                        title: effect.filename,
                                        url: effect.fileURL,
                                        sourceStart: effect.sourceStart,
                                        start: effect.start,
                                        duration: effect.duration,
                                        total: total, width: trackWidth,
                                        tint: .cyan,
                                        frames: effect.volumeKeyframes,
                                        selected: selectedSoundID == effect.id,
                                        onSelect: { onSelectSound(effect) },
                                        onBeginMove: {
                                            model.beginSoundEffectsEdit()
                                            onSelectSound(effect)
                                        },
                                        onMove: { proposed in
                                            model.moveSoundEffect(
                                                effect.id, to: proposed,
                                                recordUndo: false
                                            )
                                        },
                                        effectID: effect.id,
                                        projectAudioLane: nil
                                    )
                                }
                            }
                        }
                        .frame(height: min(CGFloat(audioRowCount) * 47,
                                           132))
                    }
                }
                .frame(width: trackWidth + labelWidth)
                .padding(.vertical, 1)
            }
            .scrollIndicators(.visible)
        }
        .task(id: model.voiceoverURL?.path ?? "") {
            voiceDurationSeconds = 0
            if let url = model.voiceoverURL,
               let length = try? await AVURLAsset(url: url)
                .load(.duration).seconds,
               length.isFinite, length > 0 {
                voiceDurationSeconds = length
            }
        }
        .frame(height: 86 + (audioRowCount > 0 ?
            min(CGFloat(audioRowCount) * 47, 132) : 0))
    }

    private func musicSpan(_ total: Double) -> Double {
        guard model.musicDuration > 0 else { return total }
        let available = max(0.1, model.musicDuration -
                            model.musicStartSeconds)
        let section = model.musicHighlightDuration > 0 ?
            min(available, model.musicHighlightDuration) : available
        return model.repeatShortMusic ?
            max(0.1, total - model.musicTimelineOffset) :
            min(max(0.1, total - model.musicTimelineOffset), section)
    }

    private func ruler(width: CGFloat, total: Double) -> some View {
        let step = max(1, Int(ceil(total / 24)))
        return HStack(spacing: 0) {
            Button {
                snapToBeat.toggle()
            } label: {
                Image(systemName: "magnet")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(snapToBeat ? Color.cyan : Color.gray)
                    .frame(width: labelWidth, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snapToBeat ?
                "Tắt hút vào mốc nhịp" : "Bật hút vào mốc nhịp")
            Canvas { context, size in
                for i in stride(from: 0, through: 24, by: 1) {
                    let time = min(total, Double(i * step))
                    let x = CGFloat(time / total) * width
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: 13))
                    line.addLine(to: CGPoint(x: x, y: 19))
                    context.stroke(line, with: .color(.gray),
                                   lineWidth: 1)
                    context.draw(Text("\(Int(time))s")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.gray),
                        at: CGPoint(x: x + 2, y: 1), anchor: .topLeading)
                    if time >= total { break }
                }
            }
            .frame(width: width, height: 20)
            .contentShape(Rectangle())
            .onTapGesture { location in
                onScrub(Double(min(width, max(0, location.x)) / width)
                        * total)
            }
        }
        .frame(height: 20)
    }

    private func videoLane(width: CGFloat, total: Double) -> some View {
        HStack(spacing: 0) {
            Text("VID")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(width: labelWidth)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.035))
                ForEach(Array(model.clips.enumerated()),
                        id: \.element.id) { index, clip in
                    Button {
                        onSelectClip(clip, index)
                    } label: {
                        ZStack {
                            TimelineThumbnail(clip: clip)
                                .frame(width: max(26, width * CGFloat(
                                    clip.renderedDuration / total)),
                                       height: 41)
                                .clipped()
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        .frame(width: max(26, width * CGFloat(
                            clip.renderedDuration / total)), height: 41)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(clip.id == selectedClipID ?
                                    Color.cyan : Color.white.opacity(0.15),
                                    lineWidth: clip.id == selectedClipID ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .offset(x: width * CGFloat(
                        model.timelineStart(of: index) / total))
                    .draggable(clip.id.uuidString)
                    .dropDestination(for: String.self) { values, _ in
                        guard let value = values.first,
                              let source = UUID(uuidString: value) else {
                            return false
                        }
                        model.reorderClip(draggedID: source,
                                          before: clip.id)
                        return true
                    }
                }
                playhead(width: width, total: total)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: 44)
            .clipped()
        }
        .frame(height: 44)
    }

    private func trackLane(
        tag: String, title: String,
        url: URL, sourceStart: Double,
        start: Double, duration: Double,
        total: Double, width: CGFloat,
        tint: Color, frames: [AudioGainKeyframe],
        selected: Bool,
        onSelect: @escaping () -> Void,
        onBeginMove: (() -> Void)?,
        onMove: ((Double) -> Void)?,
        effectID: UUID?,
        projectAudioLane: ProjectAudioLane?
    ) -> some View {
        HStack(spacing: 0) {
            Text(tag)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(width: labelWidth)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint.opacity(0.07))
                AudioWaveformTimelineRegion(
                    url: url, title: title, start: start,
                    sourceStart: sourceStart, duration: duration,
                    total: total, trackWidth: width,
                    tint: tint, frames: frames, selected: selected,
                    snapMarkers: snapToBeat ? model.timelineBeatMarkers : [],
                    onSelect: onSelect,
                    onBeginMove: onBeginMove, onMove: onMove,
                    onBeginFrame: (effectID != nil ||
                        projectAudioLane != nil) ? {
                        model.beginSoundEffectsEdit()
                    } : nil,
                    onMoveFrame: (effectID != nil ||
                        projectAudioLane != nil) ? {
                        (frame: UUID, progress: Double, gain: Float) in
                        if let id = effectID {
                            model.moveSoundVolumeKeyframe(
                                id, frameID: frame,
                                progress: progress, gain: gain
                            )
                        } else if let lane = projectAudioLane {
                            model.moveProjectAudioKeyframe(
                                lane, id: frame,
                                progress: progress, gain: gain
                            )
                        }
                    } : nil
                )
                .offset(x: width * CGFloat(max(0, start) / total))
                playhead(width: width, total: total)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: 43)
            .clipped()
        }
        .frame(height: 43)
    }

    private func playhead(width: CGFloat, total: Double) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.85))
            .frame(width: 1)
            .offset(x: width * CGFloat(
                min(total, max(0, model.timelineSecond)) / total))
    }
}

/// Audio source-region graphic with actual sampled PCM waveform, keyed
/// by source location rather than project start (dragging never re-decodes).
private struct AudioWaveformTimelineRegion: View {
    let url: URL
    let title: String
    let start: Double
    let sourceStart: Double
    let duration: Double
    let total: Double
    let trackWidth: CGFloat
    let tint: Color
    let frames: [AudioGainKeyframe]
    let selected: Bool
    let snapMarkers: [Double]
    let onSelect: () -> Void
    let onBeginMove: (() -> Void)?
    let onMove: ((Double) -> Void)?
    let onBeginFrame: (() -> Void)?
    let onMoveFrame: ((UUID, Double, Float) -> Void)?

    @State private var samples: [Double] = []
    @State private var initialDragStart: Double?
    private var regionWidth: CGFloat {
        max(24, trackWidth * CGFloat(max(0.1, duration) / max(0.1, total)))
    }
    private var waveformTaskID: String {
        "\(url.path)|\(Int(sourceStart * 10))|\(Int(min(90, duration)))"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(tint.opacity(selected ? 0.32 : 0.21))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(selected ? tint : Color.clear,
                                lineWidth: 1.5)
                }

            Canvas { context, size in
                let items = samples.isEmpty ?
                    Array(repeating: 0.12, count: 36) : samples
                // For long media, draw ONLY the sampled opening 90s.
                // Stretching those peaks over the whole duration would
                // misrepresent portions of the source we never read.
                let sampledWidth = size.width * CGFloat(
                    min(1, 90 / max(0.1, duration))
                )
                let cell = sampledWidth / CGFloat(max(1, items.count))
                for (i, peak) in items.enumerated() {
                    let height = max(2, CGFloat(peak) * 17)
                    context.fill(Path(roundedRect: CGRect(
                        x: CGFloat(i) * cell + cell * 0.15,
                        y: (22 - height) * 0.5,
                        width: max(1, cell * 0.65),
                        height: height
                    ), cornerRadius: 1), with: .color(tint))
                }
            }
            .frame(height: 23)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .gesture(DragGesture(minimumDistance: 7)
                .onChanged { value in
                    guard let onMove, let onBeginMove else { return }
                    if initialDragStart == nil {
                        initialDragStart = start
                        onBeginMove()
                    }
                    let seconds = AudioTimelineMath.draggedTime(
                        origin: initialDragStart ?? start,
                        translationPoints: Double(value.translation.width),
                        contentWidth: Double(trackWidth),
                        projectDuration: total, duration: duration,
                        snapMarkers: snapMarkers
                    )
                    onMove(seconds)
                }
                .onEnded { _ in initialDragStart = nil })

            Text(title + (duration > 90 ? " · 90s đầu" : ""))
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(maxWidth: regionWidth - 3,
                       alignment: .leading)
                .offset(y: 22)
                .allowsHitTesting(false)

            ForEach(frames) { frame in
                AudioTimelineKeyframeHandle(
                    frame: frame, duration: duration,
                    width: Double(regionWidth),
                    onBegin: { onBeginFrame?() },
                    onDrag: { p, gain in
                        onMoveFrame?(frame.id, p, gain)
                    },
                    onSelect: onSelect
                )
                .offset(x: max(0, regionWidth * CGFloat(frame.progress) - 11),
                        y: 21)
            }
        }
        .frame(width: regionWidth, height: 42)
        .task(id: waveformTaskID) {
            samples = []
            do {
                samples = try await AudioWaveformSampler.sample(
                    url: url, count: 68, from: sourceStart,
                    window: min(90, max(0.5, duration))
                )
            } catch {
                // The source may be missing or scrolling may cancel sampling.
            }
        }
    }
}

private struct AudioTimelineKeyframeHandle: View {
    let frame: AudioGainKeyframe
    let duration: Double
    let width: Double
    let onBegin: () -> Void
    let onDrag: (Double, Float) -> Void
    let onSelect: () -> Void

    @State private var gestureStart: AudioGainKeyframe?

    var body: some View {
        Image(systemName: "diamond.fill")
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .frame(width: 22, height: 21)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if gestureStart == nil {
                            gestureStart = frame
                            onBegin()
                        }
                        let base = gestureStart ?? frame
                        let next = AudioTimelineMath.draggedKeyframe(
                            initialProgress: base.progress,
                            initialGain: base.gain,
                            horizontalPoints: Double(value.translation.width),
                            verticalPoints: Double(value.translation.height),
                            regionWidth: max(1, width),
                            regionHeight: 34
                        )
                        onDrag(next.progress, next.gain)
                    }
                    .onEnded { _ in gestureStart = nil }
            )
            .accessibilityLabel("Kéo trái/phải để đổi thời điểm; lên/xuống để đổi âm lượng")
    }
}
