import Foundation
import AVFoundation

/// Saves the chosen range from an imported MP3/M4A as a new M4A file.
/// AVFoundation doesn't provide an MP3 encoder, so export is AAC/M4A.
enum MusicSegmentExporter {
    static func export(inputURL: URL,
                       start: Double,
                       duration: Double) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw SmartVideoError.invalidMedia("Nhạc không chứa track âm thanh.")
        }
        let assetDuration = try await asset.load(.duration).seconds
        guard assetDuration.isFinite, assetDuration > 0 else {
            throw SmartVideoError.invalidMedia("Không đọc được thời lượng nhạc.")
        }
        let begin = max(0, min(start, assetDuration - 0.1))
        let span = max(0, min(duration, assetDuration - begin))
        guard span >= 0.1 else {
            throw SmartVideoError.invalidMedia("Highlight quá ngắn để lưu.")
        }
        let url = MediaStorage.exportsDirectory
            .appendingPathComponent("ViePN-Music-Highlight-\(UUID().uuidString.prefix(7)).m4a")
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SmartVideoError.cannotExport("iOS không thể tạo bộ xuất nhạc M4A.")
        }
        session.outputURL = url
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: begin, preferredTimescale: 600),
            duration: CMTime(seconds: span, preferredTimescale: 600)
        )
        session.metadata = []
        session.metadataItemFilter = AVMetadataItemFilter.forSharing()
        guard session.supportedFileTypes.contains(.m4a) else {
            throw SmartVideoError.cannotExport("Bộ xuất nhạc không hỗ trợ M4A.")
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: url)
            throw SmartVideoError.cannotExport(
                session.error?.localizedDescription ?? "Không xuất được highlight nhạc."
            )
        }
        return url
    }
}
