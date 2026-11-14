import Foundation

/// A suggested style for one photo, not an automatic timeline edit.
/// The user can deselect a row or replace its candidate before applying.
struct PhotoAutoPresetProposal: Identifiable, Equatable {
    var id: UUID { clipID }
    let clipID: UUID
    let fileURL: URL
    let filename: String
    var presetID: String
    let reason: String
    var isSelected: Bool = true
}
