import Foundation

enum SocialVideoSource: String, Codable, CaseIterable {
    case tiktok = "TikTok"
    case facebook = "Facebook Reels"
    case direct = "MP4 trực tiếp"
}

struct SavedSocialVideo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var source: SocialVideoSource
    var sourceLink: String
    var filename: String
    var savedAt: Date = Date()
    var duration: Double
    var fileSize: Int64

    var fileURL: URL {
        MediaStorage.downloadsDirectory.appendingPathComponent(filename)
    }

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize,
                                  countStyle: .file)
    }
}
