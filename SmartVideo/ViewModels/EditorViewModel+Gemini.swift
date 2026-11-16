import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Gemini AI Metadata Studio

    func generateAIMetadata(apiKey: String) {
        guard !isGeneratingAIMetadata else { return }
        let transcript = subtitles
            .sorted { $0.start < $1.start }
            .map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let source = transcript.isEmpty ?
            (aiVisualReport?.summary ?? narrationText) : transcript
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorText = "Chưa có nội dung. Hãy nhận diện lời nói, nhập phụ đề hoặc lời thuyết minh trước."
            return
        }
        let available = aiGeminiModels
        guard let selected = aiGeminiModelName.isEmpty
            ? GeminiDirectAPI.recommended(available)
            : available.first(where: { $0.name == aiGeminiModelName }) else {
            errorText = "Hãy nhập Gemini API key và nhận diện danh sách model trước."
            return
        }
        let projectAtStart = projectID
        let scriptAtStart = source
        let language = aiRevoiceLanguage
        let style = aiMetadataStyle
        let instructions = aiMetadataInstructions
        aiMetadataDraft = nil
        isGeneratingAIMetadata = true
        aiMetadataStatus = "Gemini \(selected.title) đang phân tích transcript và tạo metadata…"
        Task {
            defer { isGeneratingAIMetadata = false }
            do {
                let draft = try await GeminiDirectAPI.generateMetadata(
                    apiKey: apiKey, modelName: selected.name,
                    transcript: scriptAtStart, language: language,
                    style: style, instructions: instructions
                )
                guard projectID == projectAtStart else {
                    aiMetadataStatus = "Dự án đã thay đổi. Hãy tạo lại metadata."
                    return
                }
                aiMetadataDraft = draft
                aiMetadataStatus = "Đã tạo gợi ý metadata. Hãy kiểm tra và áp dụng."
            } catch {
                aiMetadataStatus = ""
                errorText = "AI Metadata: \(error.localizedDescription)"
            }
        }
    }

    func applyAIMetadata() {
        guard let draft = aiMetadataDraft else { return }
        do {
            let checked = try draft.validated()
            checkpoint()
            metadata = checked.applying(to: metadata)
            addCustomMetadata = true
            aiMetadataDraft = checked
            aiMetadataStatus = "Đã cập nhật metadata xuất MP4. Tác giả, bản quyền, năm vẫn giữ nguyên."
        } catch {
            errorText = "Metadata không hợp lệ. Hãy kiểm tra tiêu đề và mô tả."
        }
    }
    // MARK: - AI Video Director (sampled frames + local OCR)

    func analyzeSelectedVideoWithGemini(clipID: UUID?, apiKey: String) {
        guard !isAnalyzingVisualScenes,
              let clip = clips.first(where: { $0.id == clipID }),
              clip.kind == .video else {
            errorText = "Hãy chọn một clip VIDEO trước."
            return
        }
        let available = aiGeminiModels.filter {
            !$0.name.lowercased().contains("tts")
        }
        guard let chosen = aiGeminiModelName.isEmpty
            ? GeminiDirectAPI.recommended(available)
            : available.first(where: { $0.name == aiGeminiModelName }) else {
            errorText = "Hãy nhập Gemini API key và nhận diện model trước."
            return
        }
        let transcript = subtitles
            .filter { $0.start <= totalDuration }
            .sorted { $0.start < $1.start }
            .map(\.text).joined(separator: " ")
        let currentProject = projectID
        let instructions = aiVisualInstructions
        aiVisualReport = nil
        isAnalyzingVisualScenes = true
        aiVisualStatus = "Đang trích xuất khung hình và OCR trên iPhone…"
        Task {
            defer { isAnalyzingVisualScenes = false }
            do {
                aiVisualStatus = "Đang phân tích các cảnh bằng Gemini…"
                let report = try await AIVisualDirector.analyze(
                    clip: clip, transcript: transcript,
                    apiKey: apiKey, modelName: chosen.name,
                    instructions: instructions
                )
                guard projectID == currentProject,
                      clips.contains(where: { $0.id == clip.id }) else { return }
                aiVisualClipID = clip.id
                aiVisualReport = report
                aiVisualStatus = "Đã tạo \(report.scenes.count) cảnh gợi ý. Kiểm tra trước khi áp dụng."
            } catch {
                aiVisualStatus = ""
                errorText = "AI Video Director: \(error.localizedDescription)"
            }
        }
    }

    func applyDirectorSceneNarration() {
        guard let report = aiVisualReport,
              let clipID = aiVisualClipID,
              let index = clips.firstIndex(where: { $0.id == clipID })
        else { return }
        let beginning = timelineStart(of: index)
        let duration = clips[index].renderedDuration
        let suggestions = report.scenes
            .filter { !$0.narration.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty }
            .map { scene in
                SubtitleCue(
                    start: max(beginning, beginning + scene.start),
                    end: min(totalDuration,
                             beginning + min(duration, scene.end)),
                    text: scene.narration
                )
            }.filter { $0.end > $0.start + 0.05 }
        guard !suggestions.isEmpty else {
            errorText = "Chưa có lời dẫn hợp lệ từ AI."
            return
        }
        checkpoint()
        subtitles.removeAll {
            $0.start >= beginning && $0.start < beginning + duration
        }
        subtitles.append(contentsOf: suggestions)
        subtitles.sort { $0.start < $1.start }
        narrationText = subtitles.map(\.text).joined(separator: " ")
        aiVisualStatus = "Đã đưa \(suggestions.count) câu vào phụ đề. Tạo giọng theo mốc để đồng bộ."
    }
    // MARK: - Gemini AI Video Revoice

    func discoverGeminiModels(apiKey: String) {
        guard !isLoadingGeminiModels else { return }
        isLoadingGeminiModels = true
        aiGeminiModelStatus = "Đang kiểm tra Gemini API key và tải model…"
        aiGeminiModels = []
        Task {
            defer { isLoadingGeminiModels = false }
            do {
                let models = try await GeminiDirectAPI.listModels(apiKey: apiKey)
                aiGeminiModels = models
                if !models.contains(where: { $0.name == aiGeminiModelName }) {
                    aiGeminiModelName = ""
                }
                let selected = aiGeminiModelName.isEmpty ?
                    GeminiDirectAPI.recommended(models)?.title ?? "Chưa có model" :
                    models.first(where: { $0.name == aiGeminiModelName })?.title ?? ""
                aiGeminiModelStatus = "Đã phát hiện \(models.count) model. Đề xuất: \(selected)."
            } catch {
                aiGeminiModelStatus = "Không tải được model: \(error.localizedDescription)"
            }
        }
    }

    func rewriteSubtitlesDirectGemini(apiKey: String) {
        guard !isRewritingWithGemini else { return }
        let cues = subtitles
        guard !cues.isEmpty else {
            errorText = "Hãy nhận diện lời nói hoặc nhập SRT trước."
            return
        }
        let available = aiGeminiModels
        guard let selected = aiGeminiModelName.isEmpty
            ? GeminiDirectAPI.recommended(available)
            : available.first(where: { $0.name == aiGeminiModelName }) else {
            errorText = "Hãy kiểm tra API key và tải danh sách model trước."
            return
        }
        let projectAtStart = projectID
        let style = aiRevoiceStyle
        let language = aiRevoiceLanguage
        let instructions = aiRevoiceInstructions
        aiRevoiceDraft = []
        isRewritingWithGemini = true
        aiRevoiceStatus = "Gemini \(selected.title) đang viết lại lời dẫn…"
        Task {
            defer { isRewritingWithGemini = false }
            do {
                let chunks = stride(from: 0, to: cues.count, by: 60)
                    .map { start in
                        Array(cues[start..<min(start + 60, cues.count)])
                    }
                var rewritten: [SubtitleCue] = []
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    aiRevoiceStatus = "Gemini: xử lý đoạn \(index + 1)/\(chunks.count)…"
                    let part = try await GeminiDirectAPI.rewrite(
                        apiKey: apiKey, modelName: selected.name,
                        style: style, language: language,
                        instructions: instructions, captions: chunk
                    )
                    rewritten.append(contentsOf: part)
                }
                guard projectID == projectAtStart,
                      subtitles == cues else {
                    aiRevoiceStatus = "Phụ đề đã thay đổi. Hãy chạy lại."
                    return
                }
                aiRevoiceDraft = rewritten
                aiRevoiceStatus = "Đã viết lại \(rewritten.count) đoạn bằng \(selected.title). Hãy kiểm tra trước khi áp dụng."
            } catch {
                aiRevoiceStatus = ""
                errorText = "Gemini: \(error.localizedDescription)"
            }
        }
    }

    func rewriteSubtitlesWithGemini(gatewayURL: String, token: String) {
        guard !isRewritingWithGemini else { return }
        guard !subtitles.isEmpty else {
            errorText = "Hãy nhận diện lời nói từ video hoặc nhập SRT trước."
            return
        }
        let cues = subtitles
        let projectAtStart = projectID
        let style = aiRevoiceStyle
        let language = aiRevoiceLanguage
        let instructions = aiRevoiceInstructions
        aiRevoiceDraft = []
        isRewritingWithGemini = true
        aiRevoiceStatus = "Gemini đang viết lại lời dẫn…"
        Task {
            defer { isRewritingWithGemini = false }
            do {
                let chunks = stride(from: 0, to: cues.count, by: 60)
                    .map { start in
                        Array(cues[start..<min(start + 60, cues.count)])
                    }
                var result: [SubtitleCue] = []
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    aiRevoiceStatus = "Gateway: xử lý đoạn \(index + 1)/\(chunks.count)…"
                    let part = try await GeminiRevoiceClient.rewrite(
                        baseURL: gatewayURL, token: token,
                        style: style, language: language,
                        instructions: instructions, captions: chunk
                    )
                    result.append(contentsOf: part)
                }
                guard projectID == projectAtStart,
                      subtitles == cues else {
                    aiRevoiceStatus = "Phụ đề đã thay đổi trong lúc xử lý. Hãy chạy lại."
                    return
                }
                aiRevoiceDraft = result
                aiRevoiceStatus = "Đã viết lại \(result.count) đoạn. Kiểm tra và nhấn Áp dụng."
            } catch {
                aiRevoiceStatus = ""
                errorText = "Gemini: \(error.localizedDescription)"
            }
        }
    }

    func applyGeminiRevoice(muteSourceVideo: Bool) {
        guard !aiRevoiceDraft.isEmpty else { return }
        guard aiRevoiceDraft.allSatisfy({
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            errorText = "Có câu AI còn trống. Hãy chỉnh sửa hoặc khôi phục câu gốc."
            return
        }
        let rewrittenText = aiRevoiceDraft
            .map(\.text).joined(separator: " ")
        // Long scripts can still use the per-caption synced narration mode.
        // Whole-script TTS is intentionally limited to 5,000 characters.
        if rewrittenText.count > 5000 {
            aiRevoiceStatus = "Lời dài hơn 5.000 ký tự: sử dụng chế độ tạo giọng theo từng mốc phụ đề."
        }
        checkpoint()
        subtitles = aiRevoiceDraft
        narrationText = rewrittenText
        aiRevoiceDraft = []
        // This mutes all embedded audio, not isolated speech; user must opt in.
        if muteSourceVideo {
            for index in clips.indices where clips[index].kind == .video {
                clips[index].sourceAudioMuted = true
            }
        }
        aiRevoiceStatus = rewrittenText.count > 5000 ?
            "Đã áp dụng phụ đề. Lời dài: dùng Tạo giọng theo từng mốc." :
            "Đã áp dụng lời mới. Hãy tạo giọng đọc và xem thử 720p."
    }

    func separateSelectedClipVoice(
        clipID: UUID?, serverURL: String, token: String
    ) {
        guard !isSeparatingAudio,
              let clip = clips.first(where: { $0.id == clipID }),
              clip.kind == .video else {
            errorText = "Hãy chọn một clip video có tiếng nói."
            return
        }
        guard clips.count == 1, clip.playbackSpeed == 1,
              clip.speedCurve.isEmpty else {
            errorText = "Bản tách giọng này hỗ trợ một clip, tốc độ gốc 1×. Hãy xử lý clip riêng trước khi dựng nhiều clip."
            return
        }
        let startProject = projectID
        separatedBackgroundURL = nil
        isSeparatingAudio = true
        separationStatus = "Đang tách audio và tải lên máy chủ Demucs theo yêu cầu…"
        Task {
            defer { isSeparatingAudio = false }
            do {
                let output = try await AIVocalSeparatorClient.separate(
                    source: clip.fileURL,
                    sourceStart: clip.startTime,
                    duration: clip.duration,
                    serverURL: serverURL,
                    token: token
                )
                guard projectID == startProject,
                      clips.first?.id == clip.id else {
                    try? FileManager.default.removeItem(at: output)
                    return
                }
                separatedBackgroundURL = output
                separationStatus = "Đã có nền âm thanh tách giọng. Nghe thử trước khi thay âm thanh gốc."
            } catch {
                separationStatus = ""
                errorText = "AI Audio Separation: \(error.localizedDescription)"
            }
        }
    }

    func applySeparatedBackground() {
        guard let background = separatedBackgroundURL,
              clips.count == 1, clips[0].kind == .video else { return }
        checkpoint()
        clips[0].sourceAudioMuted = true
        musicURL = background
        originalMusicURL = nil
        musicStartSeconds = 0
        musicTimelineOffset = 0
        musicHighlightDuration = 0
        musicVolume = 1
        repeatShortMusic = false
        musicRegionMode = false
        musicVolumeKeyframes = []
        Task {
            let duration = try? await AVURLAsset(
                url: background).load(.duration).seconds
            if musicURL == background {
                musicDuration = duration ?? 0
            }
        }
        separationStatus = "Đã dùng nền tách giọng làm nhạc/âm môi trường, clip gốc tắt tiếng. Có thể hoàn tác thay đổi dự án."
    }

    func generateGeminiSpeech() {
        guard !isGeneratingGeminiSpeech else { return }
        let key = GeminiAPIKeyStore.load()
        let available = GeminiSpeechGenerator.availableModels(aiGeminiModels)
        guard let model = available.first(where: {
            $0.name == geminiSpeechModelName
        }) ?? available.first else {
            errorText = "Gemini key chưa có model TTS. Làm mới danh sách model hoặc chọn giọng iOS."
            return
        }
        let text = narrationText
        let projectAtStart = projectID
        let voice = geminiSpeechVoice
        let style = geminiSpeechStyle
        isGeneratingGeminiSpeech = true
        geminiSpeechStatus = "Đang tạo giọng nói bằng \(model.title)…"
        Task {
            defer { isGeneratingGeminiSpeech = false }
            do {
                let output = try await GeminiSpeechGenerator.generate(
                    apiKey: key, model: model.name,
                    text: text, voice: voice, style: style
                )
                guard projectID == projectAtStart,
                      narrationText == text else {
                    try? FileManager.default.removeItem(at: output)
                    return
                }
                voiceoverURL = output
                originalVoiceoverURL = nil
                voiceoverOffset = 0
                geminiSpeechStatus = "Đã tạo giọng Gemini. Nghe và kiểm tra đồng bộ phụ đề trước khi xuất."
            } catch {
                errorText = "Gemini TTS: \(error.localizedDescription)"
                geminiSpeechStatus = ""
            }
        }
    }

    func generateTimeMatchedRevoice() {
        guard !isGeneratingSyncedRevoice, !subtitles.isEmpty,
              !clips.isEmpty else { return }
        let cues = subtitles
        let duration = totalDuration
        let voice = narratorVoiceID
        let tone = narratorTone
        let rate = narratorRate
        let pitch = narratorPitch
        let currentProject = projectID
        isGeneratingSyncedRevoice = true
        aiRevoiceStatus = "Đang tạo giọng theo từng mốc phụ đề…"
        Task {
            defer { isGeneratingSyncedRevoice = false }
            do {
                let output = try await SyncedRevoiceWriter.render(
                    cues: cues, projectDuration: duration,
                    voiceIdentifier: voice.isEmpty ? nil : voice,
                    tone: tone, rate: rate, pitch: pitch
                )
                guard projectID == currentProject,
                      subtitles == cues else {
                    try? FileManager.default.removeItem(at: output)
                    return
                }
                voiceoverURL = output
                originalVoiceoverURL = nil
                voiceoverOffset = 0
                aiRevoiceStatus = "Đã tạo thuyết minh theo mốc. Nghe bản xem thử 720p để kiểm tra nhịp đọc."
            } catch {
                errorText = "Đồng bộ AI Voice: \(error.localizedDescription)"
                aiRevoiceStatus = ""
            }
        }
    }
    // MARK: - Narration from text

    func generateNarrationFromText() {
        guard !isGeneratingNarration else { return }
        isGeneratingNarration = true
        let text = narrationText
        Task {
            defer { isGeneratingNarration = false }
            do {
                let url = try await NarrationSpeechWriter().render(
                    text: text,
                    voiceIdentifier: narratorVoiceID.isEmpty ? nil : narratorVoiceID,
                    tone: narratorTone,
                    rateAdjustment: narratorRate,
                    pitchAdjustment: narratorPitch
                )
                voiceoverURL = url
                originalVoiceoverURL = nil
                masteringMessage = ""
            } catch {
                errorText = "Không tạo được giọng thuyết minh: \(error.localizedDescription)"
            }
        }
    }

    func removeSilenceFromNarration() {
        guard let source = voiceoverURL, !isRemovingSilence else { return }
        isRemovingSilence = true
        let threshold = silenceThreshold
        let gap = silenceGap
        Task {
            defer { isRemovingSilence = false }
            do {
                let cleaned = try await Task.detached(priority: .userInitiated) {
                    try await VoiceSilenceEditor.removeSilence(
                        from: source, thresholdDecibels: threshold,
                        minimumGap: gap, padding: 0.12
                    )
                }.value
                // Don't replace audio if a different take was selected.
                if voiceoverURL == source {
                    voiceoverURL = cleaned.url
                    originalVoiceoverURL = nil
                    masteringMessage = ""
                    lastSilenceRemoved = cleaned.removedDuration
                }
            } catch {
                errorText = "Không xóa được khoảng lặng: \(error.localizedDescription)"
            }
        }
    }

    func applyVoiceMastering() {
        guard !isMasteringVoice, !isRemovingSilence,
              let current = voiceoverURL else {
            if voiceoverURL == nil {
                errorText = "Hãy thu, nhập hoặc tạo giọng thuyết minh trước."
            }
            return
        }
        let source = originalVoiceoverURL ?? current
        let settings = masteringSettings
        isMasteringVoice = true
        masteringMessage = ""
        Task {
            defer { isMasteringVoice = false }
            do {
                let target = try await Task.detached(priority: .userInitiated) {
                    try VoiceMasteringProcessor.process(
                        sourceURL: source, settings: settings
                    )
                }.value
                // Avoid switching the narration if the user imported a
                // different take while processing was still running.
                guard voiceoverURL == current else {
                    try? FileManager.default.removeItem(at: target)
                    return
                }
                originalVoiceoverURL = source
                voiceoverURL = target
                masteringMessage = "Đã xử lý EQ + compressor" +
                    (settings.noiseGateEnabled ? " + noise gate" : "") +
                    ". Bản gốc vẫn được giữ."
            } catch {
                errorText = "Không xử lý được giọng đọc: \(error.localizedDescription)"
            }
        }
    }

    func normalizeNarration() {
        guard !isMasteringVoice, let current = voiceoverURL else {
            if voiceoverURL == nil {
                errorText = "Hãy chọn bản thuyết minh để chuẩn hóa."
            }
            return
        }
        let source = current
        isMasteringVoice = true
        masteringMessage = ""
        Task {
            defer { isMasteringVoice = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try AudioLoudnessNormalizer.normalize(
                        sourceURL: source, targetDBFS: -20
                    )
                }.value
                guard voiceoverURL == source else {
                    try? FileManager.default.removeItem(at: result.outputURL)
                    return
                }
                originalVoiceoverURL = originalVoiceoverURL ?? source
                voiceoverURL = result.outputURL
                masteringMessage = String(
                    format: "Chuẩn hóa giọng: %.1f → %.1f dBFS RMS (gain %+.1f dB).",
                    result.inputRMSDBFS, result.outputRMSDBFS, result.appliedGainDB
                )
            } catch {
                errorText = "Không chuẩn hóa được thuyết minh: \(error.localizedDescription)"
            }
        }
    }

    func applyMusicMastering() {
        guard !isProcessingMusic, let current = musicURL else {
            if musicURL == nil { errorText = "Chọn nhạc nền trước." }
            return
        }
        isProcessingMusic = true
        musicProcessingMessage = ""
        var settings = musicMasteringSettings
        settings.noiseGateEnabled = false
        let source = originalMusicURL ?? current
        Task {
            defer { isProcessingMusic = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try VoiceMasteringProcessor.process(
                        sourceURL: source, settings: settings
                    )
                }.value
                guard musicURL == current else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                originalMusicURL = source
                musicURL = url
                musicProcessingMessage = "Đã áp dụng EQ/compressor vào nhạc nền. Giữ nguyên bản gốc."
            } catch {
                errorText = "Không xử lý được nhạc: \(error.localizedDescription)"
            }
        }
    }

    func normalizeMusic() {
        guard !isProcessingMusic, let current = musicURL else {
            if musicURL == nil { errorText = "Chọn nhạc nền trước." }
            return
        }
        isProcessingMusic = true
        musicProcessingMessage = ""
        let source = current
        Task {
            defer { isProcessingMusic = false }
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try AudioLoudnessNormalizer.normalize(
                        sourceURL: source, targetDBFS: -18
                    )
                }.value
                guard musicURL == source else {
                    try? FileManager.default.removeItem(at: report.outputURL)
                    return
                }
                originalMusicURL = originalMusicURL ?? source
                musicURL = report.outputURL
                musicProcessingMessage = String(
                    format: "Chuẩn hóa nhạc: %.1f → %.1f dBFS RMS (gain %+.1f dB).",
                    report.inputRMSDBFS, report.outputRMSDBFS,
                    report.appliedGainDB
                )
            } catch {
                errorText = "Không chuẩn hóa được nhạc: \(error.localizedDescription)"
            }
        }
    }

    func restoreOriginalMusic() {
        guard !isProcessingMusic, let original = originalMusicURL else {
            return
        }
        musicURL = original
        originalMusicURL = nil
        musicProcessingMessage = "Đã khôi phục nhạc gốc."
    }

    func restoreOriginalNarration() {
        guard !isMasteringVoice, let original = originalVoiceoverURL else {
            return
        }
        voiceoverURL = original
        originalVoiceoverURL = nil
        masteringMessage = "Đã khôi phục bản thuyết minh gốc."
    }

    func createSubtitlesFromNarrationText() {
        let text = narrationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, totalDuration > 0 else {
            errorText = "Cần nhập lời thuyết minh và thêm ảnh/video vào timeline."
            return
        }
        let formatted = text.replacingOccurrences(
            of: #"(?<=[.!?。！？])\s+"#, with: "\n",
            options: .regularExpression
        )
        guard let data = formatted.data(using: .utf8) else { return }
        do {
            subtitles = try SubtitleFile.parse(
                data, filename: "narration.txt", videoDuration: totalDuration
            )
        } catch {
            errorText = "Không tạo được phụ đề: \(error.localizedDescription)"
        }
    }
}
