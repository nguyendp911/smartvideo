import Foundation

// MARK: - Library model (Mockup Studio)
//
// The 71 assets are real WebP files shipped in the app bundle
// (Resources/MockupStudio/ms_<id>.webp + ms_<id>_thumb.webp). The data lives in
// MockupStudioCatalogData.swift, GENERATED from scripts/mockup-assets/catalog.mjs.

enum MockupStudioCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case lightShadow, natureShadow, photographyEffects, textureSurface, glassEffects
    case weatherEffects, retroEffects, background, frameMockup, productMockup

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .lightShadow: return "sun.max.fill"
        case .natureShadow: return "leaf.fill"
        case .photographyEffects: return "camera.filters"
        case .textureSurface: return "square.stack.3d.up.fill"
        case .glassEffects: return "drop.fill"
        case .weatherEffects: return "cloud.rain.fill"
        case .retroEffects: return "film"
        case .background: return "rectangle.fill.on.rectangle.fill"
        case .frameMockup: return "photo.on.rectangle"
        case .productMockup: return "shippingbox.fill"
        }
    }

    var englishTitle: String { MockupStudioCatalog.categoryTitles[self]?.english ?? rawValue }
    var title: String { MockupStudioCatalog.categoryTitles[self]?.vietnamese ?? rawValue }
}

/// How the asset takes part in the composition.
enum MockupStudioKind: String, CaseIterable, Codable, Identifiable, Hashable {
    /// Transparent/texture layer over the photo (light, shadow, grain, weather...).
    case overlay
    /// Opaque backdrop; the photo becomes an inset card on top of it.
    case background
    /// Full-canvas scene with a transparent window; the photo fills the window.
    case scene

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overlay: return "Lớp phủ"
        case .background: return "Nền"
        case .scene: return "Khung / Sản phẩm"
        }
    }
    /// Position, scale and rotation only make sense for free-floating overlays.
    var isFreeTransform: Bool { self == .overlay }
}

enum MockupStudioFileType: String, Codable, Hashable {
    case webp, png, jpg
}

/// Window of a scene mockup, normalised to the asset (origin top-left).
struct MockupStudioSlot: Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct MockupStudioAsset: Identifiable, Hashable {
    let id: String
    let name: String
    let category: MockupStudioCategory
    let kind: MockupStudioKind
    let fileType: MockupStudioFileType
    let tags: [String]
    let description: String
    let defaultOpacity: Double
    let defaultBlendMode: MockupBlendMode
    let isPremium: Bool
    let slot: MockupStudioSlot?
    let pixelWidth: Int
    let pixelHeight: Int

    var aspectRatio: Double { Double(pixelWidth) / Double(max(1, pixelHeight)) }
    var imageResourceName: String { "ms_\(id)" }
    var thumbnailResourceName: String { "ms_\(id)_thumb" }

    var imageURL: URL? {
        Bundle.main.url(forResource: imageResourceName, withExtension: fileType.rawValue)
    }
    var thumbnailURL: URL? {
        Bundle.main.url(forResource: thumbnailResourceName, withExtension: "webp")
    }
}

enum MockupStudioCatalog {
    private static let index: [String: MockupStudioAsset] = Dictionary(
        allAssets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
    )

    static func asset(_ id: String) -> MockupStudioAsset? { index[id] }
    static func contains(_ id: String) -> Bool { index[id] != nil }

    static func count(in category: MockupStudioCategory) -> Int {
        allAssets.lazy.filter { $0.category == category }.count
    }

    /// Lower-case, strip diacritics (including Vietnamese đ).
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .lowercased()
    }

    /// Every whitespace-separated word of `query` must appear in the asset's
    /// name, tags, description or category title (diacritic/case-insensitive).
    /// Name matches rank first, then tags, then the rest; order is stable.
    static func search(_ query: String, in assets: [MockupStudioAsset]) -> [MockupStudioAsset] {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return assets }
        var scored: [(offset: Int, score: Int, asset: MockupStudioAsset)] = []
        for (offset, asset) in assets.enumerated() {
            let name = fold(asset.name)
            let tags = asset.tags.map(fold).joined(separator: " ")
            let rest = fold(asset.description + " " + asset.category.title + " " + asset.category.englishTitle)
            var score = 0
            var matchedAll = true
            for word in words {
                if name.contains(word) { score += 4 }
                else if tags.contains(word) { score += 2 }
                else if rest.contains(word) { score += 1 }
                else { matchedAll = false; break }
            }
            if matchedAll { scored.append((offset, score, asset)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.map { $0.asset }
    }

    /// Library filter used by the sidebar, chips and search box together.
    static func filtered(
        category: MockupStudioCategory?, kind: MockupStudioKind?,
        query: String, ids: [String]? = nil
    ) -> [MockupStudioAsset] {
        var list: [MockupStudioAsset]
        if let ids {
            list = ids.compactMap(asset)        // keeps the caller's order (recents / favorites)
        } else {
            list = allAssets
        }
        if let category { list = list.filter { $0.category == category } }
        if let kind { list = list.filter { $0.kind == kind } }
        return search(query, in: list)
    }
}

// MARK: - Favorites + recently used

/// Pure value type; `MockupStudioUsageStore` persists it.
struct MockupStudioUsage: Codable, Equatable {
    static let maxRecents = 12
    static let maxFavorites = 200

    /// Newest first.
    var favorites: [String] = []
    var recents: [String] = []

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    /// Returns the new state of the star.
    @discardableResult
    mutating func toggleFavorite(_ id: String) -> Bool {
        if let index = favorites.firstIndex(of: id) {
            favorites.remove(at: index)
            return false
        }
        favorites.insert(id, at: 0)
        if favorites.count > Self.maxFavorites { favorites.removeLast() }
        return true
    }

    mutating func recordUse(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
    }

    mutating func prune(validIDs: Set<String>) {
        favorites.removeAll { !validIDs.contains($0) }
        recents.removeAll { !validIDs.contains($0) }
    }
}

enum MockupStudioUsageStore {
    private static let key = "ViePN.MockupStudio.Usage.v1"

    static func load() -> MockupStudioUsage {
        guard let data = UserDefaults.standard.data(forKey: key),
              var usage = try? JSONDecoder().decode(MockupStudioUsage.self, from: data) else {
            return MockupStudioUsage()
        }
        usage.prune(validIDs: Set(MockupStudioCatalog.allAssets.map(\.id)))
        return usage
    }

    static func save(_ usage: MockupStudioUsage) {
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
