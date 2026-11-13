import Foundation
import AVFoundation
import Security

enum AIVocalSeparatorCredentials {
    private static let service = "com.nguyendp911.smartvideo.audio-separator"
    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var ref: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
    @discardableResult
    static func save(_ value: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return true }
        var request = query
        request[kSecValueData as String] = Data(value.utf8)
        request[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(request as CFDictionary, nil) == errSecSuccess
    }
}

/// Explicitly opted-in external Demucs service. No upload is made until the
/// user taps 'Tách giọng'; the original video and soundtrack are preserved.
enum AIVocalSeparatorClient {
    static func separate(
        source: URL,
        sourceStart: Double,
        duration: Double,
        serverURL: String,
        token: String
    ) async throws -> URL {
        guard duration >= 0.5, duration <= 180 else {
            throw SmartVideoError.invalidMedia(
                "Dịch vụ tách giọng hỗ trợ clip tối đa 180 giây mỗi lần.")
        }
        guard let root = URL(string: serverURL),
              root.scheme == "https", root.host != nil,
              root.user == nil, root.password == nil,
              root.query == nil, root.fragment == nil else {
            throw SmartVideoError.invalidMedia(
                "Nhập HTTPS URL của máy chủ AI Audio Separator.")
        }
        guard !token.isEmpty else {
            throw SmartVideoError.invalidMedia(
                "Cần nhập token máy chủ Audio Separator.")
        }
        let input = try await extract(
            source: source, start: sourceStart, duration: duration)
        defer { try? FileManager.default.removeItem(at: input) }
        let bytes = try Data(contentsOf: input)
        guard bytes.count <= 30 * 1024 * 1024 else {
            throw SmartVideoError.invalidMedia(
                "Âm thanh cần tách lớn hơn 30 MB.")
        }
        let boundary = "viepns-" + UUID().uuidString
        let header = "--\(boundary)\r\n" +
            "Content-Disposition: form-data; name=\"audio\"; " +
            "filename=\"source.m4a\"\r\n" +
            "Content-Type: audio/mp4\r\n\r\n"
        var payload = Data(header.utf8)
        payload.append(bytes)
        payload.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let upload = MediaStorage.temporaryDirectory
            .appendingPathComponent("StemUpload-\(UUID().uuidString).bin")
        try payload.write(to: upload, options: .atomic)
        defer { try? FileManager.default.removeItem(at: upload) }

        var request = URLRequest(
            url: root.appendingPathComponent("v1/remove-vocals"))
        request.httpMethod = "POST"
        request.timeoutInterval = 1200
        request.setValue("Bearer " + token,
                         forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        let (result, response) = try await URLSession.shared.upload(
            for: request, fromFile: upload)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              result.count > 1024,
              result.count < 60 * 1024 * 1024 else {
            throw SmartVideoError.invalidMedia(
                "Dịch vụ tách giọng lỗi HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0). " +
                "Kiểm tra server, quota và mô hình Demucs.")
        }
        let output = MediaStorage.mediaDirectory
            .appendingPathComponent("AI-Background-\(UUID().uuidString).m4a")
        try result.write(to: output, options: .atomic)
        let asset = AVURLAsset(url: output)
        guard !(try await asset.loadTracks(
            withMediaType: .audio)).isEmpty else {
            try? FileManager.default.removeItem(at: output)
            throw SmartVideoError.invalidMedia(
                "Server trả về tệp âm thanh không hợp lệ.")
        }
        return output
    }

    private static func extract(
        source: URL, start: Double, duration: Double
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard !(try await asset.loadTracks(
            withMediaType: .audio)).isEmpty else {
            throw SmartVideoError.invalidMedia(
                "Clip không có track âm thanh.")
        }
        let actual = try await asset.load(.duration).seconds
        let length = min(duration, actual - start)
        guard length > 0.4 else {
            throw SmartVideoError.invalidMedia(
                "Không đủ âm thanh trong clip được chọn.")
        }
        guard let exporter = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetAppleM4A
        ) else { throw SmartVideoError.cannotCreateWriter }
        let dest = MediaStorage.temporaryDirectory
            .appendingPathComponent("AI-Separation-\(UUID().uuidString).m4a")
        exporter.outputURL = dest
        exporter.outputFileType = .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        guard exporter.status == .completed else {
            throw SmartVideoError.cannotExport(
                exporter.error?.localizedDescription ??
                "Không thể trích âm thanh cho AI Separator.")
        }
        return dest
    }
}
