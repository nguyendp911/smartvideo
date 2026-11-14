import SwiftUI
import UIKit
import CoreImage
import ImageIO

/// Interactive split preview using the exact color pipeline used by MP4
/// still-image export. Full resolution originals remain untouched.
struct PhotoSplitCompareView: View {
    let clip: TimelineClip
    @State private var original: UIImage?
    @State private var enhanced: UIImage?
    @State private var fraction: CGFloat = 0.5

    private var cacheID: String {
        [
            clip.fileURL.path,
            clip.imageLook.rawValue,
            String(format: "%.3f", clip.lookIntensity),
            String(describing: clip.colorAdjustments),
            String(describing: clip.autoEnhance),
            String(describing: clip.photoPreset),
            String(format: "%.3f", clip.photoPresetIntensity)
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Gốc")
                Spacer()
                Text("Kéo vạch để so sánh")
                Spacer()
                Text("Sau preset")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                let width = max(1, geometry.size.width)
                let height = max(1, geometry.size.height)
                ZStack(alignment: .topLeading) {
                    if let original, let enhanced {
                        Image(uiImage: original)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .clipped()

                        Image(uiImage: enhanced)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: height)
                            .clipped()
                            .mask(alignment: .leading) {
                                Rectangle().frame(
                                    width: width * fraction)
                            }

                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2, height: height)
                            .shadow(color: .black.opacity(0.55), radius: 2)
                            .position(x: width * fraction, y: height / 2)
                    } else {
                        Color.secondary.opacity(0.09)
                        ProgressView()
                            .position(x: width / 2, y: height / 2)
                    }
                }
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        fraction = min(1, max(0,
                            value.location.x / width))
                    })
            }
            .frame(height: 175)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("So sánh ảnh trước và sau preset")
        }
        .task(id: cacheID) {
            original = nil
            enhanced = nil
            let snapshot = clip
            let result = await Task.detached(priority: .utility) {
                Self.makePreview(snapshot)
            }.value
            guard !Task.isCancelled else { return }
            original = result?.0
            enhanced = result?.1
        }
    }

    private static func makePreview(
        _ clip: TimelineClip
    ) -> (UIImage, UIImage)? {
        guard clip.kind == .image,
              let source = CGImageSourceCreateWithURL(
                clip.fileURL as CFURL, nil),
              let frame = CGImageSourceCreateThumbnailAtIndex(
                source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 650
                ] as CFDictionary) else { return nil }
        let ciImage = CIImage(cgImage: frame)
        let result = StudioColorGrader.apply(
            ciImage,
            look: clip.imageLook,
            intensity: clip.lookIntensity,
            adjustments: clip.colorAdjustments,
            autoEnhance: clip.autoEnhance,
            photoPreset: clip.photoPreset,
            photoPresetIntensity: clip.photoPresetIntensity
        )
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(
            result, from: ciImage.extent) else { return nil }
        return (UIImage(cgImage: frame), UIImage(cgImage: rendered))
    }
}
