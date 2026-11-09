import SwiftUI
import CoreImage
import UIKit

/// Shows the actual Core Image look of the selected photo, downsampled
/// for the phone preview. The export renderer uses the same grade function.
struct StudioLookPhotoPreview: View {
    let fileURL: URL
    let look: ImageLook
    let intensity: Double
    let adjustments: ColorAdjustments
    let contentMode: CanvasContentMode

    @State private var gradedImage: UIImage?

    var body: some View {
        Group {
            if let gradedImage {
                Image(uiImage: gradedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            } else if let original = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: original)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            } else {
                Color.black
            }
        }
        .task(id: fileURL.path + "|" + look.rawValue +
              "|" + String(format: "%.2f", intensity) + "|" +
              String(format: "%.2f|%.2f|%.2f|%.2f",
                     adjustments.exposureEV, adjustments.contrast,
                     adjustments.saturation, adjustments.warmth)) {
            gradedImage = nil
            guard let input = CIImage(
                contentsOf: fileURL,
                options: [.applyOrientationProperty: true]
            ) else { return }
            let width = max(1, input.extent.width)
            let height = max(1, input.extent.height)
            let previewScale = min(1, 900 / max(width, height))
            let prepared = input.transformed(by: CGAffineTransform(
                scaleX: previewScale, y: previewScale
            ))
            let filtered = StudioColorGrader.apply(
                prepared, look: look, intensity: intensity,
                adjustments: adjustments
            )
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let result = context.createCGImage(
                filtered, from: filtered.extent.integral
            ) else { return }
            gradedImage = UIImage(cgImage: result)
        }
    }
}
