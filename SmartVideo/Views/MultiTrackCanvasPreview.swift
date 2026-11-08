import SwiftUI

/// Editing preview is deliberately lightweight: PIP shows a video thumbnail,
/// while the exported MP4 contains the real moving video composition.
struct VideoPIPCanvasPreview: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let second: Double
    let canvas: CGSize
    let editable: Bool

    var body: some View {
        ZStack {
            ForEach(model.videoOverlays) { item in
                if second >= item.start && second <= item.end {
                    VideoPIPPreviewItem(
                        model: model, selectedID: $selectedID,
                        item: item, second: second,
                        canvas: canvas, editable: editable
                    )
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

private struct VideoPIPPreviewItem: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let item: VideoOverlayClip
    let second: Double
    let canvas: CGSize
    let editable: Bool

    private var current: OverlayKeyframe {
        let progress = (second - item.start) / max(0.1, item.duration)
        return OverlayKeyframeSampler.sample(item, atProgress: progress)
    }

    var body: some View {
        TimelineThumbnail(clip: TimelineClip(
            kind: .video, fileURL: item.fileURL,
            duration: item.sourceDuration,
            startTime: item.sourceStart,
            originalDuration: item.sourceDuration
        ))
        .frame(
            width: canvas.width * current.scale,
            height: canvas.width * current.scale * 0.58
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .opacity(current.opacity)
        .rotationEffect(.degrees(current.rotationDegrees))
        .overlay {
            if editable && selectedID == item.id {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.cyan, lineWidth: 2)
            }
        }
        .position(
            x: canvas.width * current.x,
            y: canvas.height * current.y
        )
        .gesture(
            DragGesture(minimumDistance: 0,
                        coordinateSpace: .named("captionCanvas"))
                .onChanged { value in
                    translate(to: value.location)
                }
        )
        .allowsHitTesting(editable)
    }

    private func translate(to point: CGPoint) {
        guard editable, canvas.width > 0, canvas.height > 0,
              let index = model.videoOverlays.firstIndex(where: {
                  $0.id == item.id
              }) else { return }
        selectedID = item.id
        let desiredDX = Double(point.x / canvas.width) - current.x
        let desiredDY = Double(point.y / canvas.height) - current.y
        let frames = OverlayKeyframeSampler.frames(for: item)
        let dx = max((0.03 - (frames.map(\.x).min() ?? 0.5)),
                     min(desiredDX, 0.97 - (frames.map(\.x).max() ?? 0.5)))
        let dy = max((0.03 - (frames.map(\.y).min() ?? 0.5)),
                     min(desiredDY, 0.97 - (frames.map(\.y).max() ?? 0.5)))
        if item.keyframes.isEmpty {
            model.videoOverlays[index].startX += dx
            model.videoOverlays[index].startY += dy
            model.videoOverlays[index].endX += dx
            model.videoOverlays[index].endY += dy
        } else {
            for i in model.videoOverlays[index].keyframes.indices {
                model.videoOverlays[index].keyframes[i].x += dx
                model.videoOverlays[index].keyframes[i].y += dy
            }
        }
    }
}

struct TextCanvasPreview: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let second: Double
    let canvas: CGSize
    let editable: Bool

    var body: some View {
        ZStack {
            ForEach(model.textOverlays) { item in
                if second >= item.start && second <= item.end {
                    TextOverlayPreviewItem(
                        model: model, selectedID: $selectedID,
                        item: item, second: second,
                        canvas: canvas, editable: editable
                    )
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

private struct TextOverlayPreviewItem: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let item: TextOverlayClip
    let second: Double
    let canvas: CGSize
    let editable: Bool

    private var current: OverlayKeyframe {
        let progress = (second - item.start) / max(0.1, item.duration)
        return OverlayKeyframeSampler.sample(item, atProgress: progress)
    }

    private var fontPoints: CGFloat {
        CGFloat(min(30, max(10,
            item.fontSize * Double(canvas.width) / 1080)))
    }

    private var titleColor: Color {
        Color(uiColor: TextOverlayRenderer.uiColor(hex: item.colorHex))
    }

    private var titleBackground: Color {
        item.useBackground ? Color.black.opacity(0.50) : .clear
    }

    var body: some View {
        Text(item.text)
            .font(.system(size: fontPoints, weight: .bold))
            .foregroundStyle(titleColor)
            .multilineTextAlignment(.center)
            .padding(5)
            .frame(width: canvas.width * 0.85)
            .background(
                titleBackground, in: RoundedRectangle(cornerRadius: 6)
            )
            .scaleEffect(current.scale / 0.45)
            .rotationEffect(.degrees(current.rotationDegrees))
            .opacity(current.opacity)
            .overlay {
                if editable && selectedID == item.id {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.cyan, lineWidth: 1.5)
                }
            }
            .position(
                x: canvas.width * current.x,
                y: canvas.height * current.y
            )
            .gesture(
                DragGesture(minimumDistance: 0,
                            coordinateSpace: .named("captionCanvas"))
                    .onChanged { value in
                        moveText(to: value.location)
                    }
            )
            .allowsHitTesting(editable)
    }

    private func moveText(to point: CGPoint) {
        guard editable, canvas.width > 0, canvas.height > 0,
              let index = model.textOverlays.firstIndex(where: {
                  $0.id == item.id
              }) else { return }
        selectedID = item.id
        let desiredDX = Double(point.x / canvas.width) - current.x
        let desiredDY = Double(point.y / canvas.height) - current.y
        let frames = OverlayKeyframeSampler.frames(for: item)
        let dx = max((0.03 - (frames.map(\.x).min() ?? 0.5)),
                     min(desiredDX, 0.97 - (frames.map(\.x).max() ?? 0.5)))
        let dy = max((0.03 - (frames.map(\.y).min() ?? 0.5)),
                     min(desiredDY, 0.97 - (frames.map(\.y).max() ?? 0.5)))
        if item.keyframes.isEmpty {
            model.textOverlays[index].startX += dx
            model.textOverlays[index].startY += dy
            model.textOverlays[index].endX += dx
            model.textOverlays[index].endY += dy
        } else {
            for i in model.textOverlays[index].keyframes.indices {
                model.textOverlays[index].keyframes[i].x += dx
                model.textOverlays[index].keyframes[i].y += dy
            }
        }
    }
}
