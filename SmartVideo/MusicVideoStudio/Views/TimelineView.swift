import SwiftUI

extension MusicVideoStudio {
    private struct ScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    /// Multi-track timeline (named TimelineTracksView to avoid SwiftUI's own
    /// `TimelineView`): ruler, one lane per available track, playhead, zoom.
    struct TimelineTracksView: View {
        @ObservedObject var model: MusicVideoEditorModel
        let playback: PlaybackEngine

        @State private var scrollX: CGFloat = 0
        @State private var viewportWidth: CGFloat = 320
        @State private var pinchStart: Double?

        private let laneHeight: CGFloat = 48
        private let headerWidth: CGFloat = 52
        private var tracks: [TrackKind] { model.visibleTracks }

        var body: some View {
            VStack(spacing: 0) {
                zoomBar
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: TimelineRulerView.height)
                            ForEach(tracks) { header($0) }
                        }
                        .frame(width: headerWidth)
                        .background(Color.white.opacity(0.04))
                        scrollArea
                    }
                }
            }
        }

        private var zoomBar: some View {
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { log2(model.scale.pixelsPerSecond) },
                        set: { model.scale.pixelsPerSecond = pow(2, $0) }),
                    in: log2(TimelineScale.range.lowerBound)...log2(TimelineScale.range.upperBound))
                    .tint(.cyan)
                    .accessibilityLabel("Thu phóng timeline")
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                Button("Vừa") { model.fitTimeline(width: Double(viewportWidth)) }
                    .font(.caption).buttonStyle(.bordered)
            }
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 4)
        }

        private func header(_ track: TrackKind) -> some View {
            VStack(spacing: 2) {
                Image(systemName: track.symbol).font(.system(size: 14))
                Text(track.title).font(.system(size: 9))
            }
            .foregroundStyle(.secondary)
            .frame(width: headerWidth, height: laneHeight)
            .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
        }

        private var scrollArea: some View {
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        let duration = model.project.duration
                        let width = model.scale.contentWidth(duration: duration)
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                TimelineRulerView(scale: model.scale, duration: duration) { time in
                                    playback.seek(to: time)
                                }
                                ForEach(tracks) { lane($0, width: width) }
                            }
                            if let guide = model.snapGuide {
                                Rectangle().fill(Color.yellow.opacity(0.9))
                                    .frame(width: 1.5, height: TimelineRulerView.height + laneHeight * CGFloat(tracks.count))
                                    .padding(.leading, CGFloat(model.scale.x(for: guide)))
                                    .allowsHitTesting(false)
                            }
                            PlayheadView(
                                scale: model.scale, playback: playback,
                                height: TimelineRulerView.height + laneHeight * CGFloat(tracks.count),
                                viewport: geo.size.width, scrollX: scrollX, proxy: proxy)
                        }
                        .frame(width: width, alignment: .topLeading)
                        .background(GeometryReader { inner in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: -inner.frame(in: .named("mv-timeline")).minX)
                        })
                    }
                    .coordinateSpace(name: "mv-timeline")
                    .onPreferenceChange(ScrollOffsetKey.self) { scrollX = $0 }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                if pinchStart == nil { pinchStart = model.scale.pixelsPerSecond }
                                model.scale.pixelsPerSecond = (pinchStart ?? 60) * Double(value)
                            }
                            .onEnded { _ in pinchStart = nil })
                }
                .onAppear { viewportWidth = geo.size.width }
                .onChange(of: geo.size.width) { viewportWidth = $0 }
            }
            .frame(height: TimelineRulerView.height + laneHeight * CGFloat(tracks.count))
        }

        /// Only blocks near the visible part are built, so hundreds of photos stay smooth.
        private func isNearViewport(_ clip: TimelineClip) -> Bool {
            let margin: CGFloat = 400
            let left = CGFloat(model.scale.x(for: clip.range.start))
            let right = CGFloat(model.scale.x(for: clip.range.end))
            return right >= scrollX - margin && left <= scrollX + viewportWidth + margin
        }

        private func lane(_ track: TrackKind, width: CGFloat) -> some View {
            let clips = TimelineEngine.clips(in: model.project, track: track)
            return ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white.opacity(track == .photo ? 0.025 : 0.045))
                    .frame(width: width, height: laneHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { model.clearSelection() }
                ForEach(clips.filter { isNearViewport($0) }) { clip in
                    ClipBlockView(clip: clip, track: track, model: model, height: laneHeight - 8)
                        .frame(width: max(8, CGFloat(model.scale.x(for: clip.range.duration))), height: laneHeight - 8)
                        .padding(.leading, CGFloat(model.scale.x(for: clip.range.start)))
                        .padding(.top, 4)
                }
            }
            .frame(width: width, height: laneHeight, alignment: .topLeading)
            .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)
        }
    }

    /// The red playhead. Observes the clock itself so only this view redraws
    /// every frame; while playing it keeps itself scrolled into view.
    struct PlayheadView: View {
        let scale: TimelineScale
        @ObservedObject var playback: PlaybackEngine
        let height: CGFloat
        let viewport: CGFloat
        let scrollX: CGFloat
        let proxy: ScrollViewProxy

        var body: some View {
            let x = CGFloat(scale.x(for: playback.state.time))
            VStack(spacing: 0) {
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundColor(.red)
                Rectangle().fill(Color.red).frame(width: 1.5)
            }
            .frame(width: 12, height: height, alignment: .top)
            .padding(.leading, max(0, x - 6))
            .id("playhead")
            .allowsHitTesting(false)
            .onChange(of: playback.state.time) { _ in
                guard playback.state.isPlaying else { return }
                if x > scrollX + viewport - 36 || x < scrollX {
                    proxy.scrollTo("playhead", anchor: .leading)
                }
            }
        }
    }
}
