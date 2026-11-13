import Foundation
import AVFoundation

/// Gemini single-speaker speech. Uses a TTS-capable model explicitly
/// returned by ListModels. Legacy generateContent returns base64 raw PCM
/// (24 kHz, signed 16-bit mono); some newer models return RIFF/WAV.
enum GeminiSpeechGenerator {
    static func availableModels(_ models: [GeminiAvailableModel]) -> [GeminiAvailableModel] {
        models.filter { $0.name.lowercased().contains("tts") }
    }

    static func generate(
        apiKey: String, model: String,
        text: String, voice: String, style: String
    ) async throws -> URL {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 2500 else {
            throw SmartVideoError.invalidMedia(
                "Gemini TTS cần lời đọc từ 1–2.500 ký tự mỗi lần.")
        }
        let name = model.hasPrefix("models/") ?
            String(model.dropFirst(7)) : model
        guard name.lowercased().contains("tts"),
              name.range(of: #"^[A-Za-z0-9._-]+$"#,
                options: .regularExpression) != nil else {
            throw SmartVideoError.invalidMedia(
                "Chọn model Gemini có hỗ trợ TTS.")
        }
        let allowedVoices = ["Kore", "Puck", "Charon",
                             "Fenrir", "Aoede", "Leda",
                             "Zephyr", "Orus"]
        let selectedVoice = allowedVoices.contains(voice) ? voice : "Kore"
        let url = URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/" +
            name + ":generateContent")!
        struct Part: Encodable { let text: String }
        struct Content: Encodable { let parts: [Part] }
        struct PrebuiltVoice: Encodable { let voiceName: String }
        struct VoiceConfig: Encodable { let prebuiltVoiceConfig: PrebuiltVoice }
        struct SpeechConfig: Encodable { let voiceConfig: VoiceConfig }
        struct GenerationConfig: Encodable {
            let responseModalities: [String]
            let speechConfig: SpeechConfig
        }
        struct Payload: Encodable {
            let contents: [Content]
            let generationConfig: GenerationConfig
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(
            contents: [Content(parts: [Part(
                text: "Read this text in Vietnamese naturally. " +
                    "Style: " + String(style.prefix(100)) + ". " + clean
            )])],
            generationConfig: GenerationConfig(
                responseModalities: ["AUDIO"],
                speechConfig: SpeechConfig(voiceConfig: VoiceConfig(
                    prebuiltVoiceConfig: PrebuiltVoice(
                        voiceName: selectedVoice)))
            )
        ))
        let (responseData, response) = try await URLSession.shared.data(
            for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw SmartVideoError.invalidMedia(
                "Gemini TTS HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0). " +
                "Kiểm tra quyền TTS, model và hạn mức API.")
        }
        struct Reply: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        struct Inline: Decodable {
                            let mimeType: String?
                            let data: String
                        }
                        let inlineData: Inline?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        let parsed = try JSONDecoder().decode(Reply.self, from: responseData)
        guard let part = parsed.candidates?.first?.content?.parts?
            .compactMap(\.inlineData).first,
              let bytes = Data(base64Encoded: part.data),
              bytes.count > 44, bytes.count < 25_000_000 else {
            throw SmartVideoError.invalidMedia(
                "Model không trả về dữ liệu âm thanh hợp lệ.")
        }
        let output = MediaStorage.mediaDirectory
            .appendingPathComponent("Gemini-AI-Voice-\(UUID().uuidString).wav")
        let data: Data = bytes.starts(with: Data("RIFF".utf8)) ?
            bytes : PCMToWAV.encode(pcm: bytes)
        try data.write(to: output, options: .atomic)
        let asset = AVURLAsset(url: output)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            try? FileManager.default.removeItem(at: output)
            throw SmartVideoError.invalidMedia(
                "Không đọc được audio Gemini. Thử model TTS khác.")
        }
        return output
    }
}

/// WAV PCM header for 24 kHz, 16-bit, single-channel Gemini legacy TTS output.
enum PCMToWAV {
    static func encode(pcm: Data, sampleRate: UInt32 = 24000) -> Data {
        var output = Data()
        func put16(_ value: UInt16) {
            output.append(UInt8(truncatingIfNeeded: value))
            output.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func put32(_ value: UInt32) {
            put16(UInt16(truncatingIfNeeded: value))
            put16(UInt16(truncatingIfNeeded: value >> 16))
        }
        let length = UInt32(min(pcm.count, Int(UInt32.max - 36)))
        output.append(contentsOf: Array("RIFF".utf8))
        put32(36 + length)
        output.append(contentsOf: Array("WAVEfmt ".utf8))
        put32(16)
        put16(1)
        put16(1)
        put32(sampleRate)
        put32(sampleRate * 2)
        put16(2)
        put16(16)
        output.append(contentsOf: Array("data".utf8))
        put32(length)
        output.append(pcm.prefix(Int(length)))
        return output
    }
}
