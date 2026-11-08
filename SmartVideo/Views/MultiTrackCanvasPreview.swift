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
                if second >= item.start && second <= item.end,
                   let index = model.textOverlays.firstIndex(where: { $0.id == item.id }) {
                    let ratio = min(1, max(0,
                        (second - item.start) / max(0.1, item.duration)))
                    let x = item.startX + (item.endX - item.startX) * ratio
                    let y = item.startY + (item.endY - item.startY) * ratio
                    Text(item.text)
                        .font(.system(size: min(30, max(10, item.fontSize *
                                                     Double(canvas.width) / 1080)),
                                      weight: .bold))
                        .foregroundStyle(Color(uiColor:
                            TextOverlayRenderer.uiColor(hex: item.colorHex)))
                        .multilineTextAlignment(.center)
                        .padding(5)
                        .frame(width: canvas.width * 0.85)
                        .background(
                            item.useBackground ?
                                Color.black.opacity(0.50) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .opacity(item.opacity)
                        .overlay {
                            if editable && selectedID == item.id {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.cyan, lineWidth: 1.5)
                                    .frame(width: canvas.width * 0.85)
                            }
                        }
                        .position(x: canvas.width * x, y: canvas.height * y)
                        .gesture(
                            DragGesture(minimumDistance: 0,
                                        coordinateSpace: .named("captionCanvas"))
                                .onChanged { value in
                                    guard editable else { return }
                                    selectedID = item.id
                                    let deltaX = Double(value.location.x / canvas.width) - x
                                    let deltaY = Double(value.location.y / canvas.height) - y
                                    model.textOverlays[index].startX =
                                        min(0.95, max(0.05, item.startX + deltaX))
                                    model.textOverlays[index].startY =
                                        min(0.95, max(0.05, item.startY + deltaY))
                                    model.textOverlays[index].endX =
                                        min(0.95, max(0.05, item.endX + deltaX))
                                    model.textOverlays[index].endY =
                                        min(0.95, max(0.05, item.endY + deltaY))
                                }
                        )
                        .allowsHitTesting(editable)
                }
            }
        }.frame(width: canvas.width, height: canvas.height)
    }
}
