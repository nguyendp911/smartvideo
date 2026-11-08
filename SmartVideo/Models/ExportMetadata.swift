import Foundation
import AVFoundation

struct ExportMetadata: Codable {
    var title: String = ""
    var author: String = ""
    var description: String = ""
    var copyright: String = ""
    var keywords: String = ""
    var genre: String = ""
    var comment: String = ""
    var year: String = ""

    /// User-authored metadata only. Source metadata is handled independently.
    func items() -> [AVMetadataItem] {
        var data: [AVMetadataItem] = []
        func add(_ field: String, key: String) {
            let clean = String(field.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(1000))
            guard !clean.isEmpty else { return }
            let entry = AVMutableMetadataItem()
            entry.keySpace = .common
            entry.key = key as NSString
            entry.value = clean as NSString
            entry.locale = Locale(identifier: "vi_VN")
            data.append(entry)
        }
        add(title, key: "title")
        add(author, key: "creator")
        add(description, key: "description")
        add(copyright, key: "copyrights")
        add(keywords, key: "subject")
        add(genre, key: "type")
        add(comment, key: "comment")
        add(year, key: "creationDate")
        return data
    }
}
