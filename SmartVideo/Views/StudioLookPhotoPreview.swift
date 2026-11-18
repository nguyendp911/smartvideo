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
    let autoEnhance: AutoEnhanceSettings
    let photoPreset: PhotoPreset?
    let photoPresetIntensity: Double
    let portraitFocus: PhotoPortraitFocusSettings
    let personBackground: PersonBackground
    let contentMode: CanvasContentMode

    @State private var gradedImage: UIImage?
    @State private var cutoutError: String?

    var body: some View {
        Group {
            if let gradedImage {
                Image(uiImage: gradedImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            } else if personBackground != .original {
                VStack(spacing: 6) {
                    ProgressView()
                    Text(cutoutError ?? "Đang tách nền người bằng Vision…")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            } else if let original = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: original)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            } else {
                Color.black
            }
        }
        .task(id: fileURL.path + "|" + look.rawValue +
              "|" + personBackground.rawValue + "|" +
              String(format: "%.2f", intensity) + "|" +
              String(format: "%.2f|%.2f|%.2f|%.2f",
                     adjustments.exposureEV, adjustments.contrast,
                     adjustments.saturation, adjustments.warmth) + "|" +
              String(format: "%d|%.2f|%.2f|%.2f|%.2f|%.2f",
                     autoEnhance.enabled ? 1 : 0, autoEnhance.exposureEV,
                     autoEnhance.contrast, autoEnhance.saturation,
                     autoEnhance.noiseReduction, autoEnhance.sharpness) + "|" +
              (photoPreset?.id ?? "none") + "|" +
              String(format: "%.3f", photoPresetIntensity) + "|" +
              String(describing: portraitFocus)) {
            gradedImage = nil
            cutoutError = nil
            let url = fileURL
            let targetLook = look
            let targetIntensity = intensity
            let targetAdjustments = adjustments
            let targetAutoEnhance = autoEnhance
            let targetPhotoPreset = photoPreset
            let targetPhotoPresetIntensity = photoPresetIntensity
            let targetPortraitFocus = portraitFocus
            let targetPersonBackground = personBackground

            let result: Result<UIImage?, Error> = await Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return .success(nil) }
                guard let input = CIImage(
                    contentsOf: url,
                    options: [.applyOrientationProperty: true]
                ) else { return .success(nil) }
                let width = max(1, input.extent.width)
                let height = max(1, input.extent.height)
                let previewScale = min(1, 900 / max(width, height))
                let prepared = input.transformed(by: CGAffineTransform(
                    scaleX: previewScale, y: previewScale
                ))
                let graded = StudioColorGrader.apply(
                    prepared, look: targetLook, intensity: targetIntensity,
                    adjustments: targetAdjustments,
                    autoEnhance: targetAutoEnhance,
                    photoPreset: targetPhotoPreset,
                    photoPresetIntensity: targetPhotoPresetIntensity
                )
                let filtered: CIImage
                do {
                    filtered = try PersonCutoutProcessor.apply(
                        prepared, mode: targetPersonBackground, foreground: graded,
                        portraitFocus: targetPortraitFocus
                    )
                } catch {
                    return .failure(error)
                }
                guard !Task.isCancelled else { return .success(nil) }
                let context = CIContext(options: [.cacheIntermediates: false])
                guard let cgImage = context.createCGImage(
                    filtered, from: filtered.extent.integral
                ) else { return .success(nil) }
                return .success(UIImage(cgImage: cgImage))
            }.value

            guard !Task.isCancelled else { return }
            switch result {
            case .success(let image):
                gradedImage = image
            case .failure(let error):
                cutoutError = "Không thể tách nền: " + error.localizedDescription
            }
        }
    }
}
