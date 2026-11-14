import Foundation

struct AIPhotoEditResult {
    let edited: TimelineClip
    let explanation: String
}

/// Conservative photo-only automatic enhancement on-device. The user can
/// export an edited copy in one tap, preserving the original project clip.
enum AIPhotoAutoEditor {
    static func analyzeAndEdit(
        _ photo: TimelineClip
    ) async throws -> AIPhotoEditResult {
        guard photo.kind == .image else {
            throw SmartVideoError.invalidMedia(
                "AI Photo Editor chỉ chỉnh sửa ảnh tĩnh.")
        }
        async let scene = PhotoPresetSuggester.suggest(
            fileURL: photo.fileURL)
        async let tune = AutoEnhanceProcessor.recommend(
            for: photo, strength: 0.65)
        async let subject = PhotoPortraitFocusProcessor.detectPerson(
            in: photo.fileURL)

        let suggestion = try? await scene
        let enhance = (try? await tune) ?? .off
        let hasPerson = (try? await subject) ?? false

        var edited = photo
        edited.autoEnhance = enhance
        let id: String
        if let suggestion,
           PhotoPresetLibrary.find(suggestion.presetID) != nil {
            id = suggestion.presetID
        } else {
            id = hasPerson ? "natural_skin" : "pastel_soft"
        }
        edited.photoPreset = PhotoPresetLibrary.find(id)
        edited.photoPresetIntensity = hasPerson ? 0.60 : 0.72
        edited.imageLook = .original
        // Keep background and human features untouched by default.
        // User can explicitly enable AI Portrait Focus/cutout in the editor.
        let category = suggestion?.reason ??
            (hasPerson ? "Ảnh có người" : "Ảnh thường")
        return AIPhotoEditResult(
            edited: edited,
            explanation: "AI chọn \(edited.photoPreset?.name ?? "màu trung tính") · " +
                category + " · tối ưu sáng, nhiễu và độ nét."
        )
    }
}
