import SwiftUI
import UIKit

/// Small async preview of an image with optional green/blue chroma removal.
/// The original PNG is never modified.
struct KeyedOverlayImage: View {
    let overlay: ImageOverlayClip
    @State private var rendered: UIImage?

    private var token: String {
        "\(overlay.fileURL.path):\(overlay.chromaEnabled):\(overlay.chromaColor.rawValue):\(overlay.chromaTolerance):\(overlay.chromaSoftness)"
    }

    var body: some View {
        Group {
            if let image = rendered {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").resizable().scaledToFit()
                    .foregroundStyle(.gray)
            }
        }
        .task(id: token) {
            let url = overlay.fileURL
            let enabled = overlay.chromaEnabled
            let color = overlay.chromaColor
            let tolerance = overlay.chromaTolerance
            let softness = overlay.chromaSoftness
            rendered = await Task.detached(priority: .utility) {
                guard let source = UIImage(contentsOfFile: url.path) else {
                    return Optional<UIImage>.none
                }
                return ChromaKeyProcessor.render(
                    source, enabled: enabled, color: color,
                    tolerance: tolerance, softness: softness
                )
            }.value
        }
    }
}
