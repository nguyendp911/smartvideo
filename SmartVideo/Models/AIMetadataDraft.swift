import Foundation

/// AI suggestions remain drafts until the editor explicitly applies them.
/// Do not invent legal authorship, copyright ownership, location or creation date.
struct AIMetadataDraft: Codable, Equatable {
    var title: String
    var description: String
    var keywords: [String]
    var genre: String
    var comment: String
    var hashtags: [String]

    func validated() throws -> AIMetadataDraft {
        func clean(_ string: String, limit: Int) -> String {
            String(string.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(limit))
        }
        let candidate = AIMetadataDraft(
            title: clean(title, limit: 150),
            description: clean(description, limit: 1000),
            keywords: Array(Set(keywords.map {
                clean($0.replacingOccurrences(of: ",", with: " "), limit: 55)
            }.filter { !$0.isEmpty })).sorted().prefix(20).map { $0 },
            genre: clean(genre, limit: 80),
            comment: clean(comment, limit: 240),
            hashtags: Array(Set(hashtags.map {
                let normalized = $0.replacingOccurrences(
                    of: " ", with: "").replacingOccurrences(of: "#", with: "")
                return "#" + clean(normalized, limit: 45)
            }.filter { $0 != "#" })).sorted().prefix(15).map { $0 }
        )
        guard !candidate.title.isEmpty, !candidate.description.isEmpty else {
            throw GeminiDirectError.invalidResponse
        }
        return candidate
    }

    /// Apply only editorial fields. Keep author, copyright and year user-owned.
    func applying(to current: ExportMetadata) -> ExportMetadata {
        var result = current
        result.title = title
        result.description = description
        result.keywords = keywords.joined(separator: ", ")
        result.genre = genre
        result.comment = comment
        return result
    }

    var socialCaption: String {
        ([description] + (hashtags.isEmpty ? [] : [hashtags.joined(separator: " ")]))
            .joined(separator: "\n\n")
    }
}
