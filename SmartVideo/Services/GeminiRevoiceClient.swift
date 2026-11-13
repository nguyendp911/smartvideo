import Foundation
import Security

/// The Gemini API key belongs only in the private gateway's secret store.
/// This keychain item holds a separate access token for the user's gateway.
enum AIGatewayCredentials {
    private static let service = "com.nguyendp911.smartvideo.ai-gateway"
    static func loadToken() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return "" }
        return token
    }
    static func saveToken(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        guard !token.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

/// Only text transcripts / captions are uploaded. Never send raw
/// video, photos, or audio through this endpoint.
struct AIRevoiceSegment: Codable {
    var id: Int
    var start: Double
    var end: Double
    var text: String
}
struct AIRevoiceRequest: Encodable {
    var style: String
    var language: String
    var instructions: String
    var segments: [AIRevoiceSegment]
}
struct AIRevoiceResponse: Decodable {
    var segments: [AIRevoiceSegment]
}
enum AIRevoiceError: LocalizedError {
    case invalidEndpoint, missingToken, emptyTranscript
    case response(String)
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Nhập địa chỉ HTTPS của AI Gateway đã triển khai."
        case .missingToken: return "Nhập access token của AI Gateway."
        case .emptyTranscript: return "Chưa có phụ đề hoặc lời nói để Gemini viết lại."
        case .response(let value): return value
        }
    }
}

enum GeminiRevoiceClient {
    static func prepare(_ captions: [SubtitleCue]) throws -> [AIRevoiceSegment] {
        let eligible = captions
            .sorted { $0.start < $1.start }
            .filter { cue in
                !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    cue.end > cue.start && cue.start.isFinite && cue.end.isFinite
            }
        guard eligible.count <= 100 else {
            throw AIRevoiceError.response(
                "Mỗi lần Gemini xử lý tối đa 100 câu. Hãy chia dự án thành đoạn ngắn."
            )
        }
        let input = eligible.enumerated().map { index, cue in
            AIRevoiceSegment(
                id: index, start: cue.start, end: cue.end,
                text: String(cue.text.trimmingCharacters(
                    in: .whitespacesAndNewlines).prefix(650))
            )
        }
        guard !input.isEmpty else { throw AIRevoiceError.emptyTranscript }
        return input
    }
    static func validate(_ segments: [AIRevoiceSegment],
                         input: [AIRevoiceSegment]) throws -> [SubtitleCue] {
        let mapped = Dictionary(segments.map { ($0.id, $0.text) },
                                uniquingKeysWith: { first, _ in first })
        guard mapped.count == input.count else {
            throw AIRevoiceError.response(
                "Gemini trả thiếu đoạn hoặc số lượng đoạn không khớp."
            )
        }
        return try input.map { segment in
            guard let output = mapped[segment.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !output.isEmpty, output.count <= 900 else {
                throw AIRevoiceError.response(
                    "Nội dung Gemini trả về không hợp lệ ở đoạn \(segment.id + 1)."
                )
            }
            return SubtitleCue(start: segment.start,
                               end: segment.end, text: output)
        }
    }
    static func rewrite(
        baseURL: String, token: String, style: String,
        language: String, instructions: String,
        captions: [SubtitleCue]
    ) async throws -> [SubtitleCue] {
        let input = try prepare(captions)
        guard let root = URL(string: baseURL),
              root.scheme?.lowercased() == "https",
              root.host != nil, root.user == nil,
              root.password == nil, root.query == nil,
              root.fragment == nil else { throw AIRevoiceError.invalidEndpoint }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AIRevoiceError.missingToken }
        let endpoint = root.appendingPathComponent("v1/revoice")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            AIRevoiceRequest(style: style, language: language,
                instructions: String(instructions.prefix(800)),
                segments: input)
        )
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIRevoiceError.response("Máy chủ không trả HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AIRevoiceError.response(
                "Gemini Gateway HTTP \(http.statusCode): " +
                String(decoding: body.prefix(350), as: UTF8.self)
            )
        }
        let decoded = try JSONDecoder().decode(AIRevoiceResponse.self, from: body)
        // Reject truncated/hallucinated responses and keep original timing;
        // never trust model-produced timestamps or word-level alignments.
        return try validate(decoded.segments, input: input)
    }
}
