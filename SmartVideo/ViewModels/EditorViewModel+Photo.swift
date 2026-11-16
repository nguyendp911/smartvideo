import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - AI Photo Editor & true high-resolution photo export

    func exportPhoto(
        clipID: UUID?, autoEdit: Bool = false,
        saveToPhotos: Bool = false
    ) {
        guard !isExportingPhoto, !isExporting,
              let clip = clips.first(where: {
                  $0.id == clipID && $0.kind == .image
              }) else {
            errorText = "Hãy chọn một ảnh tĩnh để xuất."
            return
        }
        let projectAtStart = projectID
        let settings = photoExportSettings
        isExportingPhoto = true
        exportedPhotoURL = nil
        exportedPhotoFiles = []
        photoBatchZIPURL = nil
        photoExportStatus = autoEdit ?
            "AI đang phân tích và tự chỉnh ảnh…" :
            "Đang xuất ảnh chất lượng cao…"
        Task {
            defer { isExportingPhoto = false }
            do {
                var outputClip = clip
                var explanation = ""
                if autoEdit {
                    let result = try await AIPhotoAutoEditor.analyzeAndEdit(clip)
                    outputClip = result.edited
                    explanation = result.explanation + " "
                }
                guard projectID == projectAtStart else {
                    photoExportStatus = "Dự án đã thay đổi, đã dừng xuất ảnh."
                    return
                }
                photoExportStatus = explanation + "Đang render " +
                    settings.format.rawValue + "…"
                let finalClip = outputClip
                let output = try await Task.detached(
                    priority: .userInitiated
                ) {
                    try PhotoExporter.export(
                        clip: finalClip, settings: settings)
                }.value
                guard projectID == projectAtStart else {
                    photoExportStatus = "Ảnh đã được lưu trong Exports, nhưng dự án đã thay đổi."
                    return
                }
                if autoEdit, let index = clips.firstIndex(where: {
                    $0.id == clip.id &&
                    $0.fileURL == clip.fileURL
                }) {
                    checkpoint()
                    clips[index].autoEnhance = outputClip.autoEnhance
                    clips[index].photoPreset = outputClip.photoPreset
                    clips[index].photoPresetIntensity =
                        outputClip.photoPresetIntensity
                    clips[index].imageLook = .original
                }
                exportedPhotoURL = output
                exportedPhotoFiles = [output]
                photoExportStatus = explanation +
                    "Đã xuất ảnh " +
                    settings.format.rawValue + " thành công."
                if saveToPhotos {
                    try await saveExportedPhotos([output])
                    photoExportStatus += " Đã lưu vào thư viện Ảnh."
                }
            } catch {
                photoExportStatus = "Xuất ảnh thất bại: " +
                    error.localizedDescription
                errorText = photoExportStatus
            }
        }
    }

    func exportBatchPhotos(
        autoEdit: Bool = false, saveToPhotos: Bool = false
    ) {
        guard !isExportingPhoto, !isExporting else { return }
        let photos = clips.filter { $0.kind == .image }
        guard !photos.isEmpty && photos.count <= 50 else {
            errorText = "Xuất hàng loạt hỗ trợ từ 1 đến 50 ảnh."
            return
        }
        let settings = photoExportSettings
        let projectAtStart = projectID
        isExportingPhoto = true
        exportedPhotoURL = nil
        exportedPhotoFiles = []
        photoBatchZIPURL = nil
        photoExportStatus = "Chuẩn bị xuất \(photos.count) ảnh…"
        Task {
            defer { isExportingPhoto = false }
            do {
                var resultURLs: [URL] = []
                for (i, input) in photos.enumerated() {
                    try Task.checkCancellation()
                    guard projectID == projectAtStart else {
                        photoExportStatus =
                            "Dự án đã thay đổi; tạm ngừng xuất ảnh."
                        return
                    }
                    photoExportStatus = "Đang xuất ảnh \(i + 1)/\(photos.count)…"
                    var candidate = input
                    if autoEdit {
                        candidate = try await AIPhotoAutoEditor
                            .analyzeAndEdit(input).edited
                    }
                    let work = candidate
                    let output = try await Task.detached(
                        priority: .userInitiated
                    ) {
                        try PhotoExporter.export(
                            clip: work, settings: settings)
                    }.value
                    resultURLs.append(output)
                    exportedPhotoFiles = resultURLs
                }
                photoExportStatus = "Đang đóng gói ZIP…"
                let copies = resultURLs
                let archive = try await Task.detached(
                    priority: .utility
                ) {
                    try PhotoBatchZIP.create(files: copies)
                }.value
                photoBatchZIPURL = archive
                exportedPhotoURL = resultURLs.first
                photoExportStatus =
                    "Đã xuất \(resultURLs.count) ảnh " +
                    settings.format.rawValue + " và tạo ZIP."
                if saveToPhotos {
                    try await saveExportedPhotos(resultURLs)
                    photoExportStatus += " Đã lưu ảnh vào thư viện Ảnh."
                }
            } catch {
                photoExportStatus = "Xuất hàng loạt thất bại: " +
                    error.localizedDescription
                errorText = photoExportStatus
            }
        }
    }

    func savePhotoExportsToLibrary() {
        let files = exportedPhotoFiles
        guard !files.isEmpty else {
            errorText = "Chưa xuất ảnh nào để lưu."
            return
        }
        Task {
            do {
                try await saveExportedPhotos(files)
                photoExportStatus = "Đã lưu \(files.count) ảnh vào thư viện Ảnh."
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    func saveExportedPhotos(_ files: [URL]) async throws {
        let permission = await PHPhotoLibrary.requestAuthorization(
            for: .addOnly)
        guard permission == .authorized || permission == .limited else {
            throw SmartVideoError.photoPermission
        }
        try await PHPhotoLibrary.shared().performChanges {
            for url in files {
                _ = PHAssetChangeRequest
                    .creationRequestForAssetFromImage(atFileURL: url)
            }
        }
    }

    func importSelections(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        checkpoint()
        isImporting = true
        defer { isImporting = false }

        for selection in selections {
            do {
                let isMovie = selection.supportedContentTypes.contains { $0.conforms(to: .movie) }
                if isMovie {
                    guard let result = try await selection.loadTransferable(type: PickedMovie.self) else {
                        throw SmartVideoError.invalidMedia("Không tải được video từ thư viện.")
                    }
                    let asset = AVURLAsset(url: result.url)
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite && duration > 0 else {
                        throw SmartVideoError.invalidMedia("Video không có thời lượng hợp lệ.")
                    }
                    clips.append(TimelineClip(kind: .video, fileURL: result.url,
                                              duration: duration, originalDuration: duration))
                } else {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw SmartVideoError.invalidMedia("Không tải được ảnh từ thư viện.")
                    }
                    let url = try MediaStorage.storeImage(data: data)
                    clips.append(TimelineClip(kind: .image, fileURL: url,
                                              duration: 3, originalDuration: 3))
                }
            } catch {
                errorText = "Một mục không thể nhập: \(error.localizedDescription)"
            }
        }
    }

    /// Copies a downloaded social video into the editable project's Media
    /// folder; vault entries can then be deleted without losing this clip.
    func importFromDownloadLibrary(_ video: SavedSocialVideo) async -> UUID? {
        guard FileManager.default.fileExists(atPath: video.fileURL.path) else {
            errorText = "Video trong Kho đã bị mất. Hãy tải lại."
            return nil
        }
        do {
            let local = try MediaStorage.copyToMedia(
                video.fileURL, fallbackExtension: "mp4"
            )
            do {
                let asset = AVURLAsset(url: local)
                guard !(try await asset.loadTracks(
                    withMediaType: .video
                )).isEmpty else {
                    throw SmartVideoError.invalidMedia(
                        "Tệp này không có track video hợp lệ."
                    )
                }
                let duration = try await asset.load(.duration).seconds
                guard duration.isFinite && duration > 0 else {
                    throw SmartVideoError.invalidMedia(
                        "Không đọc được thời lượng video."
                    )
                }
                checkpoint()
                let clip = TimelineClip(
                    kind: .video, fileURL: local,
                    duration: duration, originalDuration: duration
                )
                clips.append(clip)
                timelineSecond = timelineStart(of: clips.count - 1)
                return clip.id
            } catch {
                try? FileManager.default.removeItem(at: local)
                throw error
            }
        } catch {
            errorText = "Không đưa vào timeline được: \(error.localizedDescription)"
            return nil
        }
    }

    func importMusic(from sourceURL: URL) {
        guard !isImportingAudio else { return }
        isImportingAudio = true
        do {
            // Copy the security-scoped URL before the Files picker finishes.
            let localURL = try copyScoped(sourceURL, fallbackExtension: "mp3")
            Task {
                defer { isImportingAudio = false }
                do {
                    let asset = AVURLAsset(url: localURL)
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard !tracks.isEmpty else {
                        throw SmartVideoError.invalidMedia("Tệp vừa chọn không có track âm thanh.")
                    }
                    let duration = try await asset.load(.duration).seconds
                    // Never publish an indefinite or NaN duration to a SwiftUI Slider.
                    guard duration.isFinite && duration > 0 else {
                        throw SmartVideoError.invalidMedia(
                            "Không đọc được thời lượng MP3. Hãy thử MP3 hoặc M4A hợp lệ."
                        )
                    }
                    musicDuration = duration
                    musicBeatSourceTimes = []
                    detectedTempoBPM = 0
                    beatConfidence = 0
                    musicStartSeconds = 0
                    musicTimelineOffset = 0
                    musicVolumeKeyframes = []
                    musicHighlightDuration = 0
            musicHighlights = []
            exportedMusicHighlightURL = nil
                    musicURL = localURL
                    originalMusicURL = nil
                    musicProcessingMessage = ""
                    musicMasteringSettings = MusicTonePreset.original.settings
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    errorText = "Không nhập được nhạc: \(error.localizedDescription)"
                }
            }
        } catch {
            isImportingAudio = false
            errorText = "Không mở được MP3: \(error.localizedDescription)"
        }
    }

    func suggestMusicCut() {
        guard let url = musicURL, !isScanningMusic else { return }
        isScanningMusic = true
        Task {
            do {
                let suggested = try await Task.detached(priority: .userInitiated) {
                    try await MusicAnalyzer.firstAudibleSecond(in: url)
                }.value
                if musicURL == url {
                    musicStartSeconds = min(suggested, max(0, musicDuration - 0.1))
                }
            } catch {
                errorText = "Không tự tìm được điểm vào nhạc: \(error.localizedDescription)"
            }
            isScanningMusic = false
        }
    }

    func importVoiceover(from sourceURL: URL) {
        do {
            let localURL = try copyScoped(sourceURL, fallbackExtension: "m4a")
            Task {
                do {
                    let asset = AVURLAsset(url: localURL)
                    let tracks = try await asset.loadTracks(withMediaType: .audio)
                    guard !tracks.isEmpty else {
                        throw SmartVideoError.invalidMedia(
                            "Tệp thuyết minh không có track âm thanh."
                        )
                    }
                    let duration = try await asset.load(.duration).seconds
                    guard duration.isFinite && duration > 0 else {
                        throw SmartVideoError.invalidMedia(
                            "Tệp thuyết minh không có thời lượng hợp lệ."
                        )
                    }
                    voiceoverURL = localURL
                    originalVoiceoverURL = nil
                    masteringMessage = ""
                } catch {
                    try? FileManager.default.removeItem(at: localURL)
                    errorText = "Không nhập được thuyết minh: \(error.localizedDescription)"
                }
            }
        } catch {
            errorText = "Không thể mở tệp giọng đọc: \(error.localizedDescription)"
        }
    }

    func importSubtitles(from sourceURL: URL) {
        do {
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: sourceURL)
            let parsed = try SubtitleFile.parse(
                data, filename: sourceURL.lastPathComponent, videoDuration: totalDuration
            )
            guard !parsed.isEmpty else {
                throw SmartVideoError.invalidMedia("Tệp TXT/SRT không có nội dung phụ đề.")
            }
            subtitles = parsed
        } catch {
            errorText = "Không nhập được phụ đề: \(error.localizedDescription)"
        }
    }
    // MARK: - Photo Preset Studio

    func applyPhotoPreset(
        _ preset: PhotoPreset, to clipID: UUID?,
        intensity: Double, allPhotos: Bool = false
    ) {
        let indices: [Int]
        if allPhotos {
            indices = clips.indices.filter { clips[$0].kind == .image }
        } else if let index = clips.firstIndex(where: {
            $0.id == clipID && $0.kind == .image
        }) {
            indices = [index]
        } else {
            photoPresetFeedback = "Chọn ảnh trên timeline trước."
            return
        }
        guard !indices.isEmpty else {
            photoPresetFeedback = "Dự án chưa có ảnh."
            return
        }
        checkpoint()
        for index in indices {
            clips[index].photoPreset = preset
            clips[index].photoPresetIntensity = min(1, max(0,
                intensity.isFinite ? intensity : 0.75))
            // Photo recipes are independent of existing video-look presets.
            // Manual color adjustments and Auto Enhance remain available.
            clips[index].imageLook = .original
        }
        photoPresetFeedback = allPhotos ?
            "Đã áp dụng \(preset.name) cho \(indices.count) ảnh." :
            "Đã áp dụng \(preset.name). Có thể tinh chỉnh cường độ."
    }

    /// A single undo checkpoint for a hand-picked set of photo clips.
    /// No video clip is modified even if an ID of one is supplied.
    func applyPhotoPresetToSelection(
        _ preset: PhotoPreset, ids: Set<UUID>, intensity: Double
    ) {
        let indices = clips.indices.filter {
            clips[$0].kind == .image && ids.contains(clips[$0].id)
        }
        guard !indices.isEmpty else {
            photoPresetFeedback = "Chưa chọn ảnh nào để áp dụng."
            return
        }
        checkpoint()
        let amount = intensity.isFinite ? min(1, max(0, intensity)) : 0.75
        for index in indices {
            clips[index].photoPreset = preset
            clips[index].photoPresetIntensity = amount
            clips[index].imageLook = .original
        }
        photoPresetFeedback = "Đã áp dụng \(preset.name) cho \(indices.count) ảnh được chọn."
    }

    func beginPhotoPresetAdjustment() { checkpoint() }

    func changePhotoPresetIntensity(clipID: UUID?, intensity: Double) {
        guard let index = clips.firstIndex(where: {
            $0.id == clipID && $0.kind == .image
        }), clips[index].photoPreset != nil else { return }
        clips[index].photoPresetIntensity = min(1, max(0,
            intensity.isFinite ? intensity : 0.75))
    }

    func clearPhotoPreset(clipID: UUID?) {
        guard let index = clips.firstIndex(where: {
            $0.id == clipID && $0.kind == .image
        }) else { return }
        checkpoint()
        clips[index].photoPreset = nil
        photoPresetFeedback = "Đã gỡ preset; ảnh gốc được giữ nguyên."
    }

    func copyPhotoPreset(clipID: UUID?) {
        guard let clip = clips.first(where: {
            $0.id == clipID && $0.kind == .image
        }), let recipe = clip.photoPreset else {
            photoPresetFeedback = "Chưa có preset trên ảnh để sao chép."
            return
        }
        copiedPhotoPreset = (recipe, clip.photoPresetIntensity)
        photoPresetFeedback = "Đã sao chép \(recipe.name). Chọn ảnh khác và nhấn Dán."
    }

    func pastePhotoPreset(clipID: UUID?) {
        guard let recipe = copiedPhotoPreset else {
            photoPresetFeedback = "Chưa sao chép preset nào."
            return
        }
        applyPhotoPreset(
            recipe.recipe, to: clipID,
            intensity: recipe.intensity
        )
    }
    // MARK: - AI Portrait Focus (still images)

    func applyPortraitFocus(
        to clipID: UUID?, settings: PhotoPortraitFocusSettings
    ) {
        guard let index = clips.firstIndex(where: {
            $0.id == clipID && $0.kind == .image
        }) else {
            photoPresetFeedback = "Hãy chọn một ảnh trước khi xóa phông."
            return
        }
        checkpoint()
        clips[index].portraitFocus = settings
        if settings.enabled {
            // Portrait Focus is exclusive with replacement backgrounds.
            clips[index].personBackground = .original
        }
        photoPresetFeedback = settings.enabled ?
            "Đã bật Portrait Focus. Kiểm tra ảnh trước khi xuất." :
            "Đã tắt Portrait Focus."
    }

    func beginPortraitFocusAdjustment() { checkpoint() }

    func updatePortraitFocus(
        clipID: UUID?, settings: PhotoPortraitFocusSettings
    ) {
        guard let index = clips.firstIndex(where: {
            $0.id == clipID && $0.kind == .image
        }) else { return }
        clips[index].portraitFocus = settings
        if settings.enabled { clips[index].personBackground = .original }
    }
    // MARK: - Smart Photo Presets (local Vision batch scan)

    func scanPhotoPresets(onlyWithoutPreset: Bool = true) {
        guard !isScanningPhotoPresets else { return }
        let candidates = clips.filter {
            $0.kind == .image &&
            (!onlyWithoutPreset || $0.photoPreset == nil)
        }
        guard !candidates.isEmpty else {
            photoAutoPresetStatus = "Không có ảnh phù hợp để phân tích."
            return
        }
        let startProject = projectID
        photoAutoPresetPlan = []
        isScanningPhotoPresets = true
        photoAutoPresetStatus = "Đang nhận diện bối cảnh từng ảnh trên iPhone…"
        photoPresetScanTask = Task {
            defer {
                isScanningPhotoPresets = false
                photoPresetScanTask = nil
            }
            var scanned = 0
            var skipped = 0
            for candidate in candidates.prefix(60) {
                if Task.isCancelled || startProject != projectID {
                    photoAutoPresetStatus = "Đã dừng quét preset."
                    return
                }
                let match = try? await PhotoPresetSuggester.suggest(
                    fileURL: candidate.fileURL)
                if Task.isCancelled || startProject != projectID {
                    photoAutoPresetStatus = "Đã dừng quét preset."
                    return
                }
                scanned += 1
                guard let current = clips.first(where: {
                    $0.id == candidate.id &&
                    $0.fileURL == candidate.fileURL &&
                    $0.kind == .image
                }) else {
                    skipped += 1
                    continue
                }
                if let match,
                   PhotoPresetLibrary.find(match.presetID) != nil {
                    photoAutoPresetPlan.append(PhotoAutoPresetProposal(
                        clipID: current.id,
                        fileURL: current.fileURL,
                        filename: current.filename,
                        presetID: match.presetID,
                        reason: match.reason
                    ))
                } else {
                    skipped += 1
                }
                photoAutoPresetStatus =
                    "Đã quét \(scanned)/\(min(candidates.count, 60)) ảnh · " +
                    "\(photoAutoPresetPlan.count) ảnh có gợi ý."
            }
            let remaining = candidates.count > 60 ?
                " Chỉ quét 60 ảnh đầu mỗi lần." : ""
            photoAutoPresetStatus =
                "Đã quét \(scanned) ảnh; \(photoAutoPresetPlan.count) ảnh " +
                "có gợi ý, \(skipped) ảnh bỏ qua vì chưa đủ chắc chắn." +
                remaining
        }
    }

    func cancelPhotoPresetScan() {
        photoPresetScanTask?.cancel()
        photoAutoPresetStatus = "Đã yêu cầu dừng quét ảnh."
    }

    func setPhotoAutoPreset(
        clipID: UUID, presetID: String
    ) {
        guard PhotoPresetLibrary.find(presetID) != nil,
              let idx = photoAutoPresetPlan.firstIndex(where: {
                  $0.clipID == clipID
              }) else { return }
        photoAutoPresetPlan[idx].presetID = presetID
    }

    func setPhotoAutoPresetSelected(
        clipID: UUID, selected: Bool
    ) {
        guard let idx = photoAutoPresetPlan.firstIndex(where: {
            $0.clipID == clipID
        }) else { return }
        photoAutoPresetPlan[idx].isSelected = selected
    }

    func applyPhotoAutoPresetPlan(
        intensity: Double, protectExisting: Bool
    ) {
        guard !isScanningPhotoPresets else {
            photoAutoPresetStatus = "Hãy kết thúc quét ảnh trước khi áp dụng."
            return
        }
        let selected = photoAutoPresetPlan.filter { $0.isSelected }
        guard !selected.isEmpty else {
            photoAutoPresetStatus = "Chưa chọn gợi ý nào để áp dụng."
            return
        }
        let planByID = selected.reduce(
            into: [UUID: PhotoAutoPresetProposal]()
        ) { result, proposal in
            result[proposal.clipID] = proposal
        }
        let indexes = clips.indices.filter { index in
            let clip = clips[index]
            guard clip.kind == .image,
                  let proposal = planByID[clip.id],
                  proposal.fileURL == clip.fileURL,
                  PhotoPresetLibrary.find(proposal.presetID) != nil else {
                return false
            }
            return !protectExisting ||
                (clip.photoPreset == nil && clip.imageLook == .original)
        }
        guard !indexes.isEmpty else {
            photoAutoPresetStatus =
                "Không còn ảnh hợp lệ hoặc các ảnh đã có preset."
            return
        }
        checkpoint()
        let amount = intensity.isFinite ?
            min(1, max(0, intensity)) : 0.75
        for index in indexes {
            guard let proposal = planByID[clips[index].id],
                  let preset = PhotoPresetLibrary.find(
                      proposal.presetID) else { continue }
            clips[index].photoPreset = preset
            clips[index].photoPresetIntensity = amount
            clips[index].imageLook = .original
        }
        photoAutoPresetStatus =
            "Đã áp dụng preset riêng cho \(indexes.count) ảnh. " +
            "Có thể hoàn tác bằng nút Hoàn tác của trình chỉnh sửa."
        photoPresetFeedback = photoAutoPresetStatus
        photoAutoPresetPlan = []
    }
}
