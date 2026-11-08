import Foundation
import AVFoundation
import Photos
import Security

/// One independent on-device video vault. Records are kept in the user's
/// Documents folder, and the actual videos are copied into Media only when
/// the user inserts them into a video-editing project.
@MainActor
final class SocialVideoLibrary: ObservableObject {
    @Published private(set) var entries: [SavedSocialVideo] = []
    @Published private(set) var isDownloading = false
    @Published var downloadStatus = ""
    @Published var errorText: String?

    private static var indexURL: URL {
        MediaStorage.downloadsDirectory.appendingPathComponent(
            "DownloadedVideos.json"
        )
    }

    init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let old = try? JSONDecoder().decode(
                [SavedSocialVideo].self, from: data
              ) else {
            entries = []
            return
        }
        entries = old.filter {
            FileManager.default.fileExists(atPath: $0.fileURL.path)
        }.sorted { $0.savedAt > $1.savedAt }
    }

    private func saveIndex() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: Self.indexURL, options: .atomic)
    }

    static func determineSource(_ string: String)
        throws -> (URL, SocialVideoSource, Bool) {
        let raw = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count <= 2048,
              let url = URL(string: raw),
              let host = url.host?.lowercased(),
              url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil else {
            throw SmartVideoError.invalidMedia(
                "Hãy dán một URL HTTPS hợp lệ, không chứa mật khẩu hoặc cổng."
            )
        }

        let tiktokHosts: Set<String> = [
            "tiktok.com", "www.tiktok.com", "m.tiktok.com",
            "vt.tiktok.com", "vm.tiktok.com",
        ]
        let facebookHosts: Set<String> = [
            "facebook.com", "www.facebook.com", "m.facebook.com",
            "web.facebook.com", "fb.watch", "www.fb.watch",
            "fb.com", "www.fb.com",
        ]
        if tiktokHosts.contains(host) {
            return (url, .tiktok, true)
        }
        if facebookHosts.contains(host) {
            return (url, .facebook, true)
        }
        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            return (url, .direct, false)
        }
        throw SmartVideoError.invalidMedia(
            "Hỗ trợ link TikTok, Facebook Reels hoặc link HTTPS trỏ thẳng đến MP4/MOV."
        )
    }

    func download(link: String, server: String, apiKey: String,
                  hasPermission: Bool) async {
        guard !isDownloading else { return }
        guard hasPermission else {
            errorText = "Hãy xác nhận bạn sở hữu hoặc có quyền tải video."
            return
        }
        isDownloading = true
        downloadStatus = "Đang kiểm tra liên kết…"
        defer { isDownloading = false }

        var destination: URL?
        do {
            let (linkURL, source, needsResolver) =
                try Self.determineSource(link)
            let request: URLRequest
            if needsResolver {
                guard let base = URL(string: server.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )), base.scheme == "https",
                    let domain = base.host, !domain.isEmpty,
                    base.user == nil, base.password == nil,
                    base.port == nil, !apiKey.isEmpty else {
                    throw SmartVideoError.invalidMedia(
                        "Link TikTok/Facebook cần máy chủ Video Resolver HTTPS " +
                        "và khóa truy cập. Hãy cấu hình trong Kho video. " +
                        "Ứng dụng không tự lấy MP4 từ trang HTML."
                    )
                }
                var components = URLComponents(
                    url: base, resolvingAgainstBaseURL: false
                )
                components?.path = "/v1/download"
                components?.query = nil
                components?.fragment = nil
                guard let endpoint = components?.url else {
                    throw SmartVideoError.invalidMedia(
                        "Địa chỉ Video Resolver không hợp lệ."
                    )
                }
                var req = URLRequest(url: endpoint)
                req.httpMethod = "POST"
                req.timeoutInterval = 900
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
                req.httpBody = try JSONSerialization.data(
                    withJSONObject: [
                        "url": linkURL.absoluteString,
                        "has_permission": true
                    ]
                )
                request = req
            } else {
                var req = URLRequest(url: linkURL)
                req.timeoutInterval = 600
                req.setValue("video/mp4, video/quicktime, */*",
                             forHTTPHeaderField: "Accept")
                request = req
            }

            downloadStatus = needsResolver
                ? "Máy chủ đang xử lý video công khai…" :
                  "Đang tải tệp video trực tiếp…"
            let (temporary, response) = try await URLSession.shared.download(
                for: request
            )
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw SmartVideoError.invalidMedia(
                    "Máy chủ không cho tải video (HTTP \(status)). " +
                    "Kiểm tra link, quyền tải hoặc cấu hình máy chủ."
                )
            }
            let contentType = (
                http.value(forHTTPHeaderField: "Content-Type") ?? ""
            ).lowercased()
            guard !contentType.contains("text/html"),
                  !contentType.contains("application/json") else {
                throw SmartVideoError.invalidMedia(
                    "Link trả về trang web/JSON, không phải tệp video. " +
                    "Hãy dùng Video Resolver cho link TikTok/Facebook."
                )
            }
            let size = try FileManager.default.attributesOfItem(
                atPath: temporary.path
            )[.size] as? NSNumber
            let bytes = size?.int64Value ?? 0
            guard bytes > 0, bytes <= 300 * 1024 * 1024 else {
                throw SmartVideoError.invalidMedia(
                    "Video trống hoặc vượt giới hạn 300 MB của kho."
                )
            }
            downloadStatus = "Đang kiểm tra video và thời lượng…"
            let suffix = !needsResolver &&
                linkURL.pathExtension.lowercased() == "mov" ? "mov" : "mp4"
            let filename = "ViePN-\(UUID().uuidString).\(suffix)"
            let local = MediaStorage.downloadsDirectory
                .appendingPathComponent(filename)
            destination = local
            try FileManager.default.moveItem(at: temporary, to: local)

            let asset = AVURLAsset(url: local)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let duration = try await asset.load(.duration).seconds
            guard !tracks.isEmpty, duration.isFinite, duration > 0 else {
                throw SmartVideoError.invalidMedia(
                    "Dữ liệu tải về không chứa track video phát được."
                )
            }

            let formattedDate = Date().formatted(
                date: .numeric, time: .shortened
            )
            let title = "\(source.rawValue) · \(formattedDate)"
            let item = SavedSocialVideo(
                title: title, source: source, sourceLink: link,
                filename: filename, duration: duration, fileSize: bytes
            )
            entries.insert(item, at: 0)
            do {
                try saveIndex()
            } catch {
                entries.removeAll { $0.id == item.id }
                throw error
            }
            destination = nil
            downloadStatus = "Đã lưu vào Kho video: \(title)"
        } catch {
            if let destination {
                try? FileManager.default.removeItem(at: destination)
            }
            errorText = "Không tải được video: \(error.localizedDescription)"
            downloadStatus = ""
        }
    }

    func rename(_ id: UUID, title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 120,
              let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        entries[index].title = cleaned
        do { try saveIndex() }
        catch { errorText = error.localizedDescription }
    }

    func delete(_ id: UUID) {
        guard let target = entries.first(where: { $0.id == id }) else {
            return
        }
        do {
            entries.removeAll { $0.id == id }
            try saveIndex()
            try FileManager.default.removeItem(at: target.fileURL)
        } catch {
            reload()
            errorText = "Không xóa được video: \(error.localizedDescription)"
        }
    }

    func saveToPhotos(_ video: SavedSocialVideo) async {
        do {
            let state = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard state == .authorized || state == .limited else {
                throw SmartVideoError.photoPermission
            }
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(
                    atFileURL: video.fileURL
                )
            }
            downloadStatus = "Đã lưu \(video.title) vào ứng dụng Ảnh."
        } catch {
            errorText = "Không lưu được vào Ảnh: \(error.localizedDescription)"
        }
    }
}

/// API token is stored in iOS Keychain, not project JSON or UserDefaults.
enum SocialDownloadTokenStore {
    private static let account = "ViePN.VideoResolver.Token"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.nguyendp911.smartvideo",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let selector: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.nguyendp911.smartvideo",
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(selector as CFDictionary)
        guard !token.isEmpty else { return true }
        var record = selector
        record[kSecValueData as String] = Data(token.utf8)
        record[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(record as CFDictionary, nil) == errSecSuccess
    }
}
