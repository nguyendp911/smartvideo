import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - AI Auto Video Creator: analyze -> edit -> export, one tap

    func startAIAutoCreator(
        clipIDs: [UUID]? = nil,
        style: AIAutoCreationStyle,
        useGemini: Bool,
        automaticallySaveToPhotos: Bool
    ) {
        guard !isRunningAIAutoCreator, !isExporting,
              !isRenderingPreview, !isImporting else {
            errorText = "Ứng dụng đang nhập hoặc xuất video khác."
            return
        }
        let originals: [TimelineClip]
        if let clipIDs {
            let ids = Set(clipIDs)
            originals = clips.filter { ids.contains($0.id) }
        } else {
            originals = clips
        }
        guard !originals.isEmpty, originals.count <= 12 else {
            errorText = "Hãy chọn từ 1 đến 12 ảnh/video."
            return
        }
        let key = GeminiAPIKeyStore.load()
        if useGemini && key.isEmpty {
            errorText = "Cần lưu Gemini API key trước khi bật phân tích đám mây. Hoặc tắt Gemini để dựng offline bằng Vision."
            return
        }
        let activeProject = projectID
        let previousCanvas = canvas
        let outputQuality = quality
        isRunningAIAutoCreator = true
        aiAutoCreatorPlan = nil
        aiAutoCreatorStatus = "Bước 1/3: Vision đang nhận diện ảnh, chọn highlight và cải thiện ánh sáng…"
        Task {
            defer {
                isRunningAIAutoCreator = false
                isExporting = false
            }
            do {
                var plan = try await AIAutoCreationAnalyzer.analyze(
                    clips: originals, style: style)
                guard projectID == activeProject else {
                    aiAutoCreatorStatus = "Dự án đã thay đổi; không xuất bản dựng cũ."
                    return
                }
                var aiWarning = ""
                if useGemini {
                    aiAutoCreatorStatus = "Bước 2/3: Gemini đang xem khung hình mẫu và chọn nội dung…"
                    do {
                        let models: [GeminiAvailableModel]
                        if aiGeminiModels.isEmpty {
                            models = try await GeminiDirectAPI.listModels(
                                apiKey: key)
                        } else {
                            models = aiGeminiModels
                        }
                        let active = models.first(where: {
                            $0.name == aiGeminiModelName &&
                            !$0.name.lowercased().contains("tts")
                        }) ?? GeminiDirectAPI.recommended(
                            models.filter {
                                !$0.name.lowercased().contains("tts")
                            })
                        guard let active else {
                            throw GeminiDirectError.noModels
                        }
                        plan = try await AIAutoCreationGemini.enrich(
                            plan: plan,
                            clips: originals,
                            apiKey: key,
                            modelName: active.name)
                    } catch {
                        aiWarning = "Gemini không khả dụng (" +
                            String(error.localizedDescription.prefix(110)) +
                            "); đã dùng phân tích Vision offline. "
                    }
                }
                guard projectID == activeProject else {
                    aiAutoCreatorStatus = "Dự án đã thay đổi; hủy bản dựng AI."
                    return
                }
                // Validate every original before starting the long render.
                _ = try AIAutoCreationAnalyzer.materialize(
                    plan: plan, sourceClips: originals)
                aiAutoCreatorPlan = plan
                aiAutoCreatorStatus = aiWarning +
                    "Bước 3/3: Đang dựng \(plan.decisions.count) cảnh và xuất MP4…"
                isExporting = true
                exportedURL = nil
                didSaveToPhotos = false
                let planToRender = plan
                let output = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try await AIAutoCreatorExporter.render(
                        plan: planToRender,
                        originalClips: originals,
                        quality: outputQuality,
                        fallbackCanvas: previousCanvas
                    )
                }.value
                guard projectID == activeProject else {
                    // Do not attach output to a different project.
                    aiAutoCreatorStatus = "Đã dựng xong nhưng dự án đã đổi. Video được lưu trong Exports của ứng dụng."
                    return
                }
                exportedURL = output
                isExporting = false
                aiAutoCreatorStatus = aiWarning +
                    "Đã xuất MP4 thành công! \(plan.decisions.count) cảnh · " +
                    String(format: "%.1f", plan.totalApproximateSeconds) +
                    " giây trước chuyển cảnh. " +
                    (plan.usedGemini ? "Nội dung Gemini + Vision." :
                     "Phân tích Vision trên thiết bị.")
                if automaticallySaveToPhotos {
                    await saveToPhotos()
                    if didSaveToPhotos {
                        aiAutoCreatorStatus += " Đã lưu vào ứng dụng Ảnh."
                    }
                }
            } catch {
                aiAutoCreatorStatus = "Tự dựng thất bại: " +
                    error.localizedDescription
                errorText = aiAutoCreatorStatus
            }
        }
    }
}
