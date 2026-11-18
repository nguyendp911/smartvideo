import SwiftUI
import AVFoundation
import Photos

extension MusicVideoStudio {
    enum ExportError: LocalizedError {
        case invalid([String])
        case codecUnsupported(String)
        case lowDisk(needed: Int64, available: Int64)
        case writerFailed(String)
        case renderFailed(Int)
        case photoPermission

        var errorDescription: String? {
            switch self {
            case .invalid(let reasons): return reasons.joined(separator: " ")
            case .codecUnsupported(let name): return "Thiết bị này không mã hóa được \(name). Hãy chọn H.264."
            case .lowDisk(let needed, let available):
                let f = ByteCountFormatter()
                return "Không đủ dung lượng trống: cần khoảng \(f.string(fromByteCount: needed)), còn \(f.string(fromByteCount: available))."
            case .writerFailed(let reason): return "Không ghi được video: \(reason)"
            case .renderFailed(let frame): return "Không dựng được khung hình \(frame)."
            case .photoPermission: return "Chưa được phép lưu vào Ảnh (Cài đặt > ViePN Smart Video > Ảnh)."
            }
        }
    }

    /// Encoding steps that do not touch the UI (they run off the main actor).
    enum ExportPipeline {
        /// The mixdown of all audio clips (same maths as live playback). false = nothing audible.
        static func mixAudio(project: VideoProject, mediaURL: @escaping (String) -> URL, to url: URL) async throws -> Bool {
            try AudioMixdown.render(project: project, mediaURL: { mediaURL($0.mediaFile) }, to: url, duration: project.duration)
        }

        private static func run(_ session: AVAssetExportSession) async throws {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    session.exportAsynchronously { continuation.resume() }
                }
            } onCancel: {
                session.cancelExport()
            }
            try Task.checkCancellation()
            guard session.status == .completed else {
                throw ExportError.writerFailed(session.error?.localizedDescription ?? "không rõ nguyên nhân")
            }
        }

        static func encodeAAC(_ source: URL, to url: URL) async throws {
            try? FileManager.default.removeItem(at: url)
            guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else {
                throw ExportError.writerFailed("không tạo được bộ mã hóa âm thanh")
            }
            session.outputURL = url
            session.outputFileType = .m4a
            try await run(session)
        }

        /// Joins the picture and the sound without re-encoding either.
        static func mux(video: URL, audio: URL?, to url: URL, container: ExportContainer) async throws {
            try? FileManager.default.removeItem(at: url)
            guard let audio else {
                try FileManager.default.moveItem(at: video, to: url)
                return
            }
            let videoAsset = AVURLAsset(url: video), audioAsset = AVURLAsset(url: audio)
            guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
                throw ExportError.writerFailed("video không có hình")
            }
            let composition = AVMutableComposition()
            let videoDuration = try await videoAsset.load(.duration)
            guard let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw ExportError.writerFailed("không ghép được hình")
            }
            try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
            compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
            if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let audioDuration = try await audioAsset.load(.duration)
                try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(audioDuration, videoDuration)),
                                                     of: audioTrack, at: .zero)
            }
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                throw ExportError.writerFailed("không tạo được bộ ghép")
            }
            session.outputURL = url
            session.outputFileType = container == .mov ? .mov : .mp4
            session.shouldOptimizeForNetworkUse = true
            try await run(session)
        }

        static func saveToPhotos(_ url: URL) async throws {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { throw ExportError.photoPermission }
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }

    /// Renders the project to a video file: every frame is the SAME SwiftUI composition the
    /// preview shows (`ProjectFrameView`), asked for at exact frame times, then encoded with
    /// AVAssetWriter; the audio is the offline mixdown. Runs in the foreground with progress and cancel.
    @MainActor
    final class ProjectExporter: ObservableObject {
        enum Phase: Equatable {
            case idle
            case preparing(String)
            case rendering(done: Int, total: Int)
            case encodingAudio
            case finishing
            case finished(URL)
            case failed(String)
            case cancelled
        }

        @Published private(set) var phase = Phase.idle
        @Published private(set) var saveMessage: String?
        private var task: Task<Void, Never>?

        var isRunning: Bool {
            switch phase {
            case .preparing, .rendering, .encodingAudio, .finishing: return true
            default: return false
            }
        }

        /// 0...1 over the whole job; rendering frames is the bulk of it.
        var fraction: Double {
            switch phase {
            case .idle, .cancelled, .failed: return 0
            case .preparing: return 0.02
            case .rendering(let done, let total): return 0.05 + 0.88 * Double(done) / Double(max(1, total))
            case .encodingAudio: return 0.94
            case .finishing: return 0.97
            case .finished: return 1
            }
        }

        func start(model: MusicVideoEditorModel, settings: ExportSettings) {
            guard !isRunning else { return }
            saveMessage = nil
            task = Task { [weak self] in await self?.run(model: model, settings: settings) }
        }

        func cancel() { task?.cancel() }

        func reset() { if !isRunning { phase = .idle; saveMessage = nil } }

        func saveToPhotos() async {
            guard case .finished(let url) = phase else { return }
            do {
                try await ExportPipeline.saveToPhotos(url)
                saveMessage = "Đã lưu vào Ảnh."
            } catch {
                saveMessage = error.localizedDescription
            }
        }

        private func run(model: MusicVideoEditorModel, settings: ExportSettings) async {
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            do {
                phase = .finished(try await export(model: model, settings: settings))
            } catch {
                phase = (error is CancellationError || Task.isCancelled) ? .cancelled : .failed(error.localizedDescription)
            }
        }

        /// Does the whole export and returns the finished file. Throws `CancellationError` when cancelled.
        func export(model: MusicVideoEditorModel, settings rawSettings: ExportSettings) async throws -> URL {
            let settings = rawSettings.sanitized
            let project = model.project
            let size = settings.size(aspect: project.aspect)
            let hasVisuals = project.photos.count + project.texts.count + project.vinyls.count + project.lyrics.count
                + project.visualizers.count + project.effects.count > 0
            let problems = settings.problems(duration: project.duration, hasVisuals: hasVisuals)
            guard problems.isEmpty else { throw ExportError.invalid(problems) }

            phase = .preparing("Phân tích âm thanh…")
            let spectra = await model.loadSpectra()
            let manager = model.manager, projectID = project.id
            let mediaURL: (String) -> URL = { manager.mediaURL(projectID: projectID, file: $0) }
            let resources = FrameResources(project: project, spectra: spectra, mediaURL: mediaURL)

            let estimate = settings.estimatedBytes(duration: project.duration, aspect: project.aspect)
            let free = (try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage
            if let free, free < estimate * 2 + 50_000_000 { throw ExportError.lowDisk(needed: estimate * 2, available: free) }

            let work = FileManager.default.temporaryDirectory.appendingPathComponent("mv-export-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let videoURL = work.appendingPathComponent("video.\(settings.container.fileExtension)")
            let mixURL = work.appendingPathComponent("mix.caf"), aacURL = work.appendingPathComponent("mix.m4a")

            var hasAudio = false
            if !project.audios.isEmpty {
                phase = .preparing("Trộn âm thanh…")
                hasAudio = try await ExportPipeline.mixAudio(project: project, mediaURL: mediaURL, to: mixURL)
            }
            try await renderVideo(resources: resources, settings: settings, size: size, to: videoURL)
            if hasAudio {
                phase = .encodingAudio
                try await ExportPipeline.encodeAAC(mixURL, to: aacURL)
            }
            phase = .finishing
            let final = MediaStorage.exportsDirectory.appendingPathComponent(settings.fileName(projectName: project.name))
            try await ExportPipeline.mux(video: videoURL, audio: hasAudio ? aacURL : nil, to: final, container: settings.container)
            return final
        }

        // MARK: Frames

        private func preload(_ items: [RenderItem], resources: FrameResources, bucket: Int) async {
            for item in items {
                switch item {
                case .photo(let layer):
                    let url = resources.photoURL(layer)
                    if PhotoImageCache.shared.cached(url, maxPixel: bucket) == nil { _ = await PhotoImageCache.shared.load(url, maxPixel: bucket) }
                case .vinyl(let layer):
                    guard let file = layer.coverFile else { continue }
                    let url = resources.mediaURL(file)
                    if PhotoImageCache.shared.cached(url, maxPixel: 512) == nil { _ = await PhotoImageCache.shared.load(url, maxPixel: 512) }
                default: break
                }
            }
        }

        private static func draw(_ image: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int) -> Bool {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let base = CVPixelBufferGetBaseAddress(buffer),
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        private func renderVideo(resources: FrameResources, settings: ExportSettings, size: (width: Int, height: Int), to url: URL) async throws {
            let width = size.width, height = size.height
            let total = settings.totalFrames(duration: resources.project.duration)
            let codec: AVVideoCodecType = settings.codec == .hevc ? .hevc : .h264
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: settings.videoBitrate(aspect: resources.project.aspect),
                AVVideoExpectedSourceFrameRateKey: settings.fps,
                AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
            ]
            if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            let outputSettings: [String: Any] = [
                AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression,
            ]
            try? FileManager.default.removeItem(at: url)
            let writer = try AVAssetWriter(outputURL: url, fileType: settings.container == .mov ? .mov : .mp4)
            guard writer.canApply(outputSettings: outputSettings, forMediaType: .video) else {
                throw ExportError.codecUnsupported(settings.codec.rawValue)
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
            guard writer.canAdd(input) else { throw ExportError.writerFailed("không thêm được luồng hình") }
            writer.add(input)
            guard writer.startWriting() else { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "không bắt đầu được") }
            writer.startSession(atSourceTime: .zero)

            do {
                let canvas = CGSize(width: width, height: height)
                let bucket = PhotoImageCache.bucket(CGFloat(max(width, height)))
                let renderer = ImageRenderer(content: ProjectFrameView(resources: resources, canvas: canvas, time: .zero, renderScale: 1))
                renderer.scale = 1
                phase = .rendering(done: 0, total: total)
                for index in 0..<total {
                    try Task.checkCancellation()
                    let time = settings.frameTime(index)
                    await preload(TimelineEngine.renderItems(in: resources.project, at: time), resources: resources, bucket: bucket)
                    renderer.content = ProjectFrameView(resources: resources, canvas: canvas, time: time, renderScale: 1)
                    guard let image = renderer.cgImage, let pool = adaptor.pixelBufferPool else { throw ExportError.renderFailed(index) }
                    var created: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
                    guard let buffer = created, Self.draw(image, into: buffer, width: width, height: height) else {
                        throw ExportError.renderFailed(index)
                    }
                    while !input.isReadyForMoreMediaData {
                        try Task.checkCancellation()
                        if writer.status == .failed { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "bộ ghi dừng đột ngột") }
                        try await Task.sleep(nanoseconds: 4_000_000)
                    }
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(settings.fps))) else {
                        throw ExportError.writerFailed(writer.error?.localizedDescription ?? "không ghi được khung \(index)")
                    }
                    if index % 3 == 0 || index == total - 1 { phase = .rendering(done: index + 1, total: total) }
                }
                input.markAsFinished()
                await writer.finishWriting()
                guard writer.status == .completed else {
                    throw ExportError.writerFailed(writer.error?.localizedDescription ?? "không hoàn tất được tệp")
                }
            } catch {
                writer.cancelWriting()
                throw error
            }
        }
    }
}
