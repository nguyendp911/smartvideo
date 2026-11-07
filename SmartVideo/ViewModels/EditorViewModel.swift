import SwiftUI
import PhotosUI
import Photos
import AVFoundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var clips: [TimelineClip] = []
    @Published var musicURL: URL?
    @Published var musicVolume: Float = 0.35
    @Published var keepOriginalAudio = true
    @Published var quality: RenderQuality = .fullHD
    @Published var canvas: CanvasFormat = .portrait
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var exportedURL: URL?
    @Published var errorText: String?
    @Published var didSaveToPhotos = false

    var totalDuration: Double {
        clips.reduce(0) { $0 + $1.duration }
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
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            musicURL = try MediaStorage.copyToMedia(sourceURL, fallbackExtension: "m4a")
        } catch {
            errorText = "Không nhập được âm thanh: \(error.localizedDescription)"
        }
    }

    func remove(at offsets: IndexSet) {
        clips.remove(atOffsets: offsets)
    }

    func move(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
    }

    func export() {
        guard !clips.isEmpty, !isExporting else { return }
        isExporting = true
        exportedURL = nil
        didSaveToPhotos = false

        let workClips = clips
        let workMusic = musicURL
        let workQuality = quality
        let workCanvas = canvas
        let workVolume = musicVolume
        let workKeepOriginal = keepOriginalAudio

        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try await VideoRenderer().render(
                        clips: workClips,
                        musicURL: workMusic,
                        musicVolume: workVolume,
                        keepOriginalAudio: workKeepOriginal,
                        quality: workQuality,
                        canvas: workCanvas
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
