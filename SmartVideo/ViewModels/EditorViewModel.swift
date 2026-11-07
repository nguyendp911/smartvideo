import SwiftUI
import PhotosUI
import Photos
import AVFoundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [TimelineClip] = []
    @Published var subtitles: [SubtitleCue] = []
    @Published var transition: VideoTransition = .cut
    @Published var transitionSeconds: Double = 0.45
    @Published var subtitleX: Double = 0.5
    @Published var subtitleY: Double = 0.83
    @Published var musicURL: URL?
    @Published var voiceoverURL: URL?
    @Published var musicVolume: Float = 0.38
    @Published var musicStartSeconds: Double = 0
    @Published var musicDuration: Double = 0
    @Published var isImportingAudio = false
    @Published var isScanningMusic = false
    @Published var repeatShortMusic = true
    @Published var keepOriginalAudio = true
    @Published var quality: RenderQuality = .fullHD
    @Published var canvas: CanvasFormat = .portrait
    @Published var contentMode: CanvasContentMode = .fit
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var errorText: String?
    @Published var didSaveToPhotos = false

    var totalDuration: Double {
        let raw = clips.reduce(0) { $0 + $1.renderedDuration }
        guard transition == .dissolve, clips.count > 1 else { return raw }
        let overlaps = zip(clips, clips.dropFirst()).reduce(0.0) { total, pair in
            total + min(transitionSeconds,
                        pair.0.renderedDuration * 0.24,
                        pair.1.renderedDuration * 0.24)
        }
        return max(0, raw - overlaps)
    }

    func importSelections(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
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
                    musicStartSeconds = 0
                    musicURL = localURL
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

    func addSubtitle() {
        let start = min(totalDuration, (subtitles.last?.end ?? 0))
        let end = min(max(totalDuration, 0.5), start + 3)
        subtitles.append(SubtitleCue(start: start, end: max(start + 0.1, end), text: "Phụ đề mới"))
    }

    func exportSRT() -> URL? {
        do {
            let target = MediaStorage.exportsDirectory
                .appendingPathComponent("SmartVideo-PhuDe-\(UUID().uuidString.prefix(6)).srt")
            try SubtitleFile.makeSRT(subtitles).write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            errorText = "Không tạo được file SRT: \(error.localizedDescription)"
            return nil
        }
    }

    private func copyScoped(_ url: URL, fallbackExtension: String) throws -> URL {
        guard url.isFileURL else {
            throw SmartVideoError.invalidMedia("Nguồn âm thanh không phải tệp cục bộ.")
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try MediaStorage.copyToMedia(url, fallbackExtension: fallbackExtension)
    }

    func removeClip(id: UUID) {
        clips.removeAll { $0.id == id }
    }

    /// One-tap edit template using real motion and dissolve exports.
    /// This modifies project settings only and never touches original media.
    func applyCinematicPreset() {
        transition = .dissolve
        transitionSeconds = 0.45
        for index in clips.indices where clips[index].kind == .image {
            let motions: [ImageMotion] = [.zoomIn, .panRight, .zoomOut, .panLeft]
            clips[index].imageMotion = motions[index % motions.count]
            clips[index].imageLook = .cinematic
        }
    }

    func moveClip(id: UUID, delta: Int) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        let to = index + delta
        guard clips.indices.contains(to) else { return }
        clips.swapAt(index, to)
    }

    func export() {
        guard !clips.isEmpty, !isExporting else { return }
        isExporting = true
        exportedURL = nil
        didSaveToPhotos = false

        let workClips = clips
        let workTransition = transition
        let workTransitionSeconds = transitionSeconds
        let workMusic = musicURL
        let workMusicVolume = musicVolume
        let workMusicStart = musicStartSeconds
        let workLoop = repeatShortMusic
        let workVoice = voiceoverURL
        let workSubtitles = subtitles
        let workSubtitleX = subtitleX
        let workSubtitleY = subtitleY
        let workKeepOriginal = keepOriginalAudio
        let workQuality = quality
        let workCanvas = canvas
        let workMode = contentMode

        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try await VideoRenderer().render(
                        clips: workClips,
                        transition: workTransition,
                        transitionSeconds: workTransitionSeconds,
                        musicURL: workMusic,
                        musicVolume: workMusicVolume,
                        musicStartSeconds: workMusicStart,
                        repeatShortMusic: workLoop,
                        voiceoverURL: workVoice,
                        subtitles: workSubtitles,
                        subtitleX: workSubtitleX,
                        subtitleY: workSubtitleY,
                        keepOriginalAudio: workKeepOriginal,
                        quality: workQuality,
                        canvas: workCanvas,
                        contentMode: workMode
                    )
                }.value
                exportedURL = url
            } catch {
                errorText = error.localizedDescription
            }
            isExporting = false
        }
    }

    func saveToPhotos() async {
        guard let exportedURL else { return }
        do {
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                throw SmartVideoError.photoPermission
            }
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: exportedURL)
            }
            didSaveToPhotos = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}
