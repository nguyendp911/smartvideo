import SwiftUI

/// Lightweight editor previews. The actual moving PIP video renders through
/// AVFoundation; the thumbnail shown here is intentionally a still frame.
struct VideoPIPCanvasPreview: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let second: Double
    let canvas: CGSize
    let editable: Bool

    var body: some View {
        ZStack {
            ForEach(model.videoOverlays) { item in
                if second >= item.start && second <= item.end,
                   let index = model.videoOverlays.firstIndex(where: { $0.id == item.id }) {
                    let ratio = min(1, max(0,
                        (second - item.start) / max(0.1, item.duration)))
                    let x = item.startX + (item.endX - item.startX) * ratio
                    let y = item.startY + (item.endY - item.startY) * ratio
                    TimelineThumbnail(clip: TimelineClip(
                        kind: .video, fileURL: item.fileURL,
                        duration: item.sourceDuration,
                        startTime: item.sourceStart,
                        originalDuration: item.sourceDuration
                    ))
                    .frame(width: canvas.width * item.width,
                           height: canvas.width * item.width * 0.58)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .opacity(item.opacity)
                    .overlay {
                        if editable && selectedID == item.id {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(.cyan, lineWidth: 2)
                                .frame(width: canvas.width * item.width,
                                       height: canvas.width * item.width * 0.58)
                        }
                    }
                    .position(x: canvas.width * x, y: canvas.height * y)
                    .gesture(
                        DragGesture(minimumDistance: 0,
                                    coordinateSpace: .named("captionCanvas"))
                            .onChanged { value in
                                guard editable else { return }
                                selectedID = item.id
                                let dx = Double(value.location.x / canvas.width) - x
                                let dy = Double(value.location.y / canvas.height) - y
                                model.videoOverlays[index].startX =
                                    min(0.95, max(0.05, item.startX + dx))
                                model.videoOverlays[index].startY =
                                    min(0.95, max(0.05, item.startY + dy))
                                model.videoOverlays[index].endX =
                                    min(0.95, max(0.05, item.endX + dx))
                                model.videoOverlays[index].endY =
                                    min(0.95, max(0.05, item.endY + dy))
                            }
                    )
                    .allowsHitTesting(editable)
                }
            }
        }.frame(width: canvas.width, height: canvas.height)
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

    private var fraction: Double {
        min(1, max(0, (second - item.start) / max(0.1, item.duration)))
    }
    private var currentX: Double {
        item.startX + (item.endX - item.startX) * fraction
    }
    private var currentY: Double {
        item.startY + (item.endY - item.startY) * fraction
    }
    private var fontPoints: CGFloat {
        CGFloat(min(30, max(10, item.fontSize * Double(canvas.width) / 1080)))
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
            .background(titleBackground,
                        in: RoundedRectangle(cornerRadius: 6))
            .opacity(item.opacity)
            .overlay {
                if editable && selectedID == item.id {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.cyan, lineWidth: 1.5)
                }
            }
            .position(
                x: canvas.width * currentX,
                y: canvas.height * currentY
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
        guard editable,
              let index = model.textOverlays.firstIndex(where: { $0.id == item.id }),
              canvas.width > 0, canvas.height > 0 else { return }
        selectedID = item.id
        let deltaX = Double(point.x / canvas.width) - currentX
        let deltaY = Double(point.y / canvas.height) - currentY
        model.textOverlays[index].startX =
            min(0.95, max(0.05, item.startX + deltaX))
        model.textOverlays[index].startY =
            min(0.95, max(0.05, item.startY + deltaY))
        model.textOverlays[index].endX =
            min(0.95, max(0.05, item.endX + deltaX))
        model.textOverlays[index].endY =
            min(0.95, max(0.05, item.endY + deltaY))
    }
}
