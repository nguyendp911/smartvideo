import Foundation
import CoreGraphics

@main
struct MockupStudioTests {
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.001, _ note: String = "") {
        precondition(a.isFinite && abs(a - b) <= tolerance, "Expected \(b) got \(a) \(note)")
    }

    static func main() throws {
        catalog()
        search()
        usage()
        mask()
        geometry()
        try clipCoding()
        print("mockup studio tests passed")
    }

    // MARK: Catalog

    static func catalog() {
        let all = MockupStudioCatalog.allAssets
        precondition(all.count == 71, "expected 71 assets, got \(all.count)")
        precondition(Set(all.map(\.id)).count == all.count, "duplicate ids")

        let expected: [MockupStudioCategory: Int] = [
            .lightShadow: 10, .natureShadow: 5, .photographyEffects: 10, .textureSurface: 9, .glassEffects: 5,
            .weatherEffects: 6, .retroEffects: 6, .background: 6, .frameMockup: 5, .productMockup: 9,
        ]
        for (category, count) in expected {
            precondition(MockupStudioCatalog.count(in: category) == count, "\(category) count")
        }
        for asset in all {
            precondition(!asset.name.isEmpty && !asset.description.isEmpty && !asset.tags.isEmpty, asset.id)
            precondition(asset.id.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }, "bad id \(asset.id)")
            precondition((0...1).contains(asset.defaultOpacity), asset.id)
            precondition(asset.pixelWidth >= 256 && asset.pixelHeight >= 256, asset.id)
            precondition(asset.imageResourceName == "ms_\(asset.id)" && asset.thumbnailResourceName == "ms_\(asset.id)_thumb")
            switch asset.kind {
            case .overlay:
                precondition(asset.slot == nil, "overlay with slot \(asset.id)")
            case .background:
                precondition(asset.category == .background && asset.slot == nil, asset.id)
            case .scene:
                precondition(asset.category == .frameMockup || asset.category == .productMockup, asset.id)
                guard let slot = asset.slot else { preconditionFailure("scene without slot \(asset.id)") }
                precondition(slot.x >= 0 && slot.y >= 0 && slot.width > 0.1 && slot.height > 0.1, asset.id)
                precondition(slot.x + slot.width <= 1.0001 && slot.y + slot.height <= 1.0001, asset.id)
            }
        }
        for category in MockupStudioCategory.allCases {
            precondition(!category.title.isEmpty && !category.englishTitle.isEmpty && !category.symbol.isEmpty)
        }
        precondition(MockupStudioCatalog.asset("window-shadow")?.defaultBlendMode == .multiply)
        precondition(MockupStudioCatalog.asset("nope") == nil)
        // The eleven blend modes the Studio promises.
        precondition(MockupBlendMode.studioModes.count == 11)
        precondition(Set(MockupBlendMode.studioModes.map(\.rawValue)).isSuperset(
            of: ["Normal", "Multiply", "Screen", "Overlay", "Soft Light", "Hard Light",
                 "Darken", "Lighten", "Color Dodge", "Color Burn", "Difference"]))
    }

    // MARK: Search / filter

    static func search() {
        let all = MockupStudioCatalog.allAssets
        precondition(MockupStudioCatalog.search("", in: all).count == all.count)
        precondition(MockupStudioCatalog.search("   ", in: all).count == all.count)

        let windows = MockupStudioCatalog.search("window", in: all)
        precondition(windows.first?.name.lowercased().contains("window") == true)
        precondition(windows.contains { $0.id == "window-shadow" })

        // Diacritics and case are ignored, including Vietnamese đ.
        precondition(MockupStudioCatalog.search("BONG CUA SO", in: all).contains { $0.id == "window-shadow" })
        precondition(MockupStudioCatalog.search("bóng cửa sổ", in: all).contains { $0.id == "window-shadow" })
        precondition(MockupStudioCatalog.search("toi goc", in: all).contains { $0.id == "vignette" })
        precondition(MockupStudioCatalog.fold("Đèn Ánh") == "den anh")

        // Every word must match.
        precondition(MockupStudioCatalog.search("window zzzzqq", in: all).isEmpty)
        let both = MockupStudioCatalog.search("window shadow", in: all)
        precondition(!both.isEmpty && both.count <= windows.count)

        // Name hits outrank tag/description hits.
        let paper = MockupStudioCatalog.search("paper", in: all)
        precondition(paper.prefix(4).allSatisfy { $0.name.lowercased().contains("paper") }, "\(paper.prefix(4).map(\.id))")

        // Category + kind + query together.
        let scenes = MockupStudioCatalog.filtered(category: .productMockup, kind: .scene, query: "")
        precondition(scenes.count == 9)
        precondition(MockupStudioCatalog.filtered(category: .productMockup, kind: .overlay, query: "").isEmpty)
        precondition(MockupStudioCatalog.filtered(category: nil, kind: .background, query: "beige").map(\.id) == ["beige-background"])

        // A caller-supplied id list keeps its order and drops unknown ids.
        let ordered = MockupStudioCatalog.filtered(category: nil, kind: nil, query: "", ids: ["vhs", "missing", "rain"])
        precondition(ordered.map(\.id) == ["vhs", "rain"])
    }

    // MARK: Favorites / recents

    static func usage() {
        var usage = MockupStudioUsage()
        precondition(usage.toggleFavorite("rain") == true && usage.isFavorite("rain"))
        precondition(usage.toggleFavorite("snow") == true)
        precondition(usage.favorites == ["snow", "rain"])
        precondition(usage.toggleFavorite("rain") == false && !usage.isFavorite("rain"))

        for i in 0..<20 { usage.recordUse("a\(i)") }
        precondition(usage.recents.count == MockupStudioUsage.maxRecents)
        precondition(usage.recents.first == "a19")
        usage.recordUse("a15")                       // re-use moves to the front, no duplicate
        precondition(usage.recents.first == "a15" && usage.recents.filter { $0 == "a15" }.count == 1)

        usage.prune(validIDs: ["snow", "a15"])
        precondition(usage.favorites == ["snow"] && usage.recents == ["a15"])

        let data = try! JSONEncoder().encode(usage)
        precondition(try! JSONDecoder().decode(MockupStudioUsage.self, from: data) == usage)
    }

    // MARK: Mask

    static func mask() {
        var m = MockupMask(kind: .none)
        near(MockupMaskMath.alpha(m, x: 0.2, y: 0.9), 1)

        m = MockupMask(kind: .fadeTop, size: 0.5, feather: 0.2)
        near(MockupMaskMath.alpha(m, x: 0.5, y: 0), 0, 0.001, "top hidden")
        near(MockupMaskMath.alpha(m, x: 0.5, y: 1), 1, 0.001, "bottom visible")
        precondition(MockupMaskMath.alpha(m, x: 0.5, y: 0.5) > MockupMaskMath.alpha(m, x: 0.5, y: 0.3))
        m.invert = true
        near(MockupMaskMath.alpha(m, x: 0.5, y: 0), 1)
        near(MockupMaskMath.alpha(m, x: 0.5, y: 1), 0)

        for (kind, hidden, visible) in [
            (MockupMaskKind.fadeBottom, (0.5, 1.0), (0.5, 0.0)),
            (.fadeLeft, (0.0, 0.5), (1.0, 0.5)),
            (.fadeRight, (1.0, 0.5), (0.0, 0.5)),
        ] {
            let edge = MockupMask(kind: kind, size: 0.5, feather: 0.2)
            near(MockupMaskMath.alpha(edge, x: hidden.0, y: hidden.1), 0, 0.001, "\(kind) hidden")
            near(MockupMaskMath.alpha(edge, x: visible.0, y: visible.1), 1, 0.001, "\(kind) visible")
        }

        let keep = MockupMask(kind: .radialKeep, size: 0.3, feather: 0.3)
        near(MockupMaskMath.alpha(keep, x: 0.5, y: 0.5), 1)
        near(MockupMaskMath.alpha(keep, x: 0, y: 0), 0)
        let hole = MockupMask(kind: .radialHole, size: 0.3, feather: 0.3)
        near(MockupMaskMath.alpha(hole, x: 0.5, y: 0.5), 0)
        near(MockupMaskMath.alpha(hole, x: 0, y: 0), 1)

        let frame = MockupMask(kind: .frame, size: 0.2, feather: 0.2)
        near(MockupMaskMath.alpha(frame, x: 0.0, y: 0.5), 1)
        near(MockupMaskMath.alpha(frame, x: 0.5, y: 0.5), 0)

        // Always within 0...1, even with NaN / out-of-range parameters.
        for kind in MockupMaskKind.allCases {
            for (size, feather) in [(0.0, 0.0), (1.0, 1.0), (Double.nan, Double.infinity), (-5.0, 9.0)] {
                for (x, y) in [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0), (0.3, 0.8)] {
                    let a = MockupMaskMath.alpha(MockupMask(kind: kind, size: size, feather: feather), x: x, y: y)
                    precondition(a.isFinite && a >= 0 && a <= 1, "\(kind) \(size) \(feather) -> \(a)")
                }
            }
        }
    }

    // MARK: Geometry

    static func geometry() {
        let canvas = CGSize(width: 400, height: 300)
        var clip = MockupOverlayClip()
        clip.centerX = 0.5; clip.centerY = 0.5; clip.scale = 0.5
        // Square side = 400 * 0.5 = 200 centred at (200,150).
        precondition(MockupStudioGeometry.overlaySide(canvas: canvas, scale: 0.5) == 200)
        precondition(MockupStudioGeometry.contains(CGPoint(x: 200, y: 150), clip: clip, canvas: canvas))
        precondition(MockupStudioGeometry.contains(CGPoint(x: 299, y: 249), clip: clip, canvas: canvas))
        precondition(!MockupStudioGeometry.contains(CGPoint(x: 305, y: 150), clip: clip, canvas: canvas))
        // Rotated 45 degrees the corner is outside but the edge midpoint stays inside.
        clip.rotationDegrees = 45
        precondition(!MockupStudioGeometry.contains(CGPoint(x: 299, y: 249), clip: clip, canvas: canvas))
        precondition(MockupStudioGeometry.contains(CGPoint(x: 200, y: 150 + 140), clip: clip, canvas: canvas))

        // Hit test: later layers win; hidden ones are skipped.
        var a = MockupOverlayClip(); a.centerX = 0.5; a.centerY = 0.5; a.scale = 1
        var b = a; b.id = UUID()
        let hit = MockupStudioGeometry.hitTest(CGPoint(x: 200, y: 150), layers: [a, b], canvas: canvas) { _ in true }
        precondition(hit?.id == b.id)
        b.isHidden = true
        precondition(MockupStudioGeometry.hitTest(CGPoint(x: 200, y: 150), layers: [a, b], canvas: canvas) { _ in true }?.id == a.id)
        precondition(MockupStudioGeometry.hitTest(CGPoint(x: 200, y: 150), layers: [a], canvas: canvas) { _ in false } == nil)

        let snapped = MockupStudioGeometry.snap(0.505)
        precondition(snapped.snapped && snapped.value == 0.5)
        precondition(!MockupStudioGeometry.snap(0.6).snapped)

        let moved = MockupStudioGeometry.moved(from: CGPoint(x: 0.5, y: 0.5), by: CGSize(width: 40, height: -30), canvas: canvas)
        near(Double(moved.x), 0.6); near(Double(moved.y), 0.4)

        near(MockupStudioGeometry.clampedScale(9, kind: .overlay), 3)
        near(MockupStudioGeometry.clampedScale(0, kind: .overlay), 0.1)
        near(MockupStudioGeometry.clampedScale(0.2, kind: .scene), 1)
        near(MockupStudioGeometry.clampedScale(9, kind: .scene), 4)
        near(MockupStudioGeometry.clampedScale(2, kind: .background), 1.2)
        near(MockupStudioGeometry.wrappedDegrees(190), -170)
        near(MockupStudioGeometry.wrappedDegrees(-190), 170)
        near(MockupStudioGeometry.wrappedDegrees(.nan), 0)

        // Cover placement: a 4:5 art on a 1:1 canvas is cropped vertically.
        let cover = MockupStudioGeometry.coverRect(art: CGSize(width: 1200, height: 1500), in: CGSize(width: 100, height: 100))
        near(Double(cover.width), 100); near(Double(cover.height), 125); near(Double(cover.minY), -12.5)
        let window = MockupStudioGeometry.windowRect(
            slot: MockupStudioSlot(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            art: CGSize(width: 1200, height: 1500), canvas: CGSize(width: 100, height: 100))
        near(Double(window.minX), 10); near(Double(window.minY), -12.5 + 25); near(Double(window.width), 50)
        let card = MockupStudioGeometry.backgroundCardRect(canvas: CGSize(width: 200, height: 100), scale: 1, centerX: 0.5, centerY: 0.5)
        near(Double(card.width), 156); near(Double(card.midX), 100)
    }

    // MARK: Project compatibility

    static func clipCoding() throws {
        // A layer saved by an older build (no saturation / mask keys) still loads.
        let legacy = #"{"assetID":"window-soft","opacity":0.4,"blendMode":"Screen","centerX":0.3}"#
        let old = try JSONDecoder().decode(MockupOverlayClip.self, from: Data(legacy.utf8))
        near(old.opacity, 0.4); near(old.centerX, 0.3); near(old.saturation, 1)
        precondition(old.blendMode == .screen && !old.mask.isActive && old.duration == 3)

        var clip = MockupOverlayClip()
        clip.assetID = "vhs"
        clip.blendMode = .colorBurn
        clip.saturation = 1.4
        clip.mask = MockupMask(kind: .radialHole, size: 0.6, feather: 0.2, invert: true)
        clip.locked = true
        let data = try JSONEncoder().encode(clip)
        let back = try JSONDecoder().decode(MockupOverlayClip.self, from: data)
        precondition(back == clip, "round trip")
        precondition(back.usesStudioAsset)

        // Raw values of the new blend modes are stable (they are persisted).
        precondition(MockupBlendMode.colorDodge.rawValue == "Color Dodge")
        precondition(MockupBlendMode.difference.rawValue == "Difference")
    }
}
