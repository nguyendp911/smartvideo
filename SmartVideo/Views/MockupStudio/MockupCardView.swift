import SwiftUI

/// One library entry: tap adds it, drag drops it at a spot on the canvas,
/// the star toggles favourite, long-press previews it on the current photo and
/// (iPad pointer) hovering shows a ghost preview directly on the canvas.
struct MockupCardView: View {
    let asset: MockupStudioAsset
    @ObservedObject var session: MockupStudioSession

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                MockupThumbnailView(asset: asset)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.1)))
                    .overlay(alignment: .topLeading) {
                        if asset.isPremium {
                            Text("PRO").font(.system(size: 9, weight: .heavy)).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange, in: Capsule()).foregroundStyle(.black).padding(5)
                        }
                    }
                Button { session.toggleFavorite(asset) } label: {
                    Image(systemName: session.isFavorite(asset) ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(session.isFavorite(asset) ? Color.yellow : .white)
                        .padding(6).background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(5)
                .accessibilityLabel(session.isFavorite(asset) ? "Bỏ yêu thích" : "Yêu thích")
            }
            Text(asset.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
        }
        .contentShape(Rectangle())
        .onTapGesture { session.add(asset) }
        .draggable("mockup:\(asset.id)") {
            MockupThumbnailView(asset: asset).frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onHover { hovering in
            if hovering { session.ghostAssetID = asset.id }
            else if session.ghostAssetID == asset.id { session.ghostAssetID = nil }
        }
        .contextMenu {
            Button { session.add(asset) } label: { Label("Thêm vào ảnh", systemImage: "plus.circle") }
            Button { session.toggleFavorite(asset) } label: {
                Label(session.isFavorite(asset) ? "Bỏ yêu thích" : "Yêu thích",
                      systemImage: session.isFavorite(asset) ? "star.slash" : "star")
            }
        } preview: {
            MockupPreviewView(asset: asset, session: session)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(asset.name)
        .accessibilityHint("Chạm hai lần để thêm vào ảnh")
        .accessibilityAddTraits(.isButton)
    }
}

/// Real thumbnail decoded off the main thread and cached.
struct MockupThumbnailView: View {
    let asset: MockupStudioAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.05)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: asset.id) {
            image = MockupThumbnailCache.cached(asset)
            if image == nil { image = await MockupThumbnailCache.load(asset) }
        }
    }
}

/// Long-press preview: the asset at its default settings on the CURRENT photo.
struct MockupPreviewView: View {
    let asset: MockupStudioAsset
    @ObservedObject var session: MockupStudioSession
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if session.hasSource {
                    ProgressView()
                } else {
                    MockupThumbnailView(asset: asset)
                }
            }
            .frame(width: 300, height: 300)
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.headline)
                Text(asset.description).font(.caption).foregroundStyle(.secondary)
                Text("\(asset.category.title) · \(asset.kind.title) · \(asset.defaultBlendMode.rawValue) \(Int(asset.defaultOpacity * 100))%")
                    .font(.caption2).foregroundStyle(.cyan)
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
            .frame(width: 300, alignment: .leading)
        }
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .task { image = await session.quickPreview(asset) }
    }
}
