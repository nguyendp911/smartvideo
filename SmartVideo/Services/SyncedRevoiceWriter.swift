import Foundation
import AVFoundation

/// Generates one iOS TTS segment per subtitle cue and places it at the
/// original cue's project timestamp. This is time-fitting, not forced
/// phoneme alignment and does not perform Gemini voice synthesis.
enum SyncedRevoiceWriter {
    static func render(
        cues: [SubtitleCue],
        projectDuration: Double,
        voiceIdentifier: String?,
        tone: NarrationTone,
        rate: Float,
        pitch: Float
    ) async throws -> URL {
        let ordered = cues.sorted { $0.start < $1.start }
        guard !ordered.isEmpty, ordered.count <= 500,
              projectDuration > 0 else {
            throw SmartVideoError.invalidMedia(
                "Cần 1–500 câu phụ đề trong một dự án có thời lượng hợp lệ."
            )
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw SmartVideoError.cannotCreateWriter }
        var temporaryFiles: [URL] = []
        defer {
            for url in temporaryFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }
        var generated = 0
        for index in ordered.indices {
            try Task.checkCancellation()
            let cue = ordered[index]
            let nextStart = index + 1 < ordered.count
                ? ordered[index + 1].start : projectDuration
            let start = max(0, cue.start)
            let stop = min(projectDuration, cue.end, nextStart)
            let slot = stop - start
            guard slot >= 0.18,
                  !cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty else { continue }
            let url = try await NarrationSpeechWriter().render(
                text: cue.text, voiceIdentifier: voiceIdentifier,
                tone: tone, rateAdjustment: rate,
                pitchAdjustment: pitch
            )
            temporaryFiles.append(url)
            let asset = AVURLAsset(url: url)
            guard let audio = try await asset.loadTracks(
                withMediaType: .audio).first else {
                throw SmartVideoError.invalidMedia(
                    "Không có track tiếng nói trong câu \(index + 1)."
                )
            }
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite, seconds > 0.05 else { continue }
            let sourceLength = CMTime(
                seconds: seconds, preferredTimescale: 600)
            let placement = CMTime(
                seconds: start, preferredTimescale: 600)
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: sourceLength),
                of: audio, at: placement
            )
            let slotTime = CMTime(seconds: slot, preferredTimescale: 600)
            if abs(seconds - slot) > 0.02 {
                track.scaleTimeRange(
                    CMTimeRange(start: placement, duration: sourceLength),
                    toDuration: slotTime
                )
            }
            generated += 1
        }
        guard generated > 0 else {
            throw SmartVideoError.invalidMedia(
                "Không có đoạn phụ đề đủ dài để tạo giọng đọc."
            )
        }
        let output = MediaStorage.mediaDirectory
            .appendingPathComponent("ViePN-AI-Redub-\(UUID().uuidString).m4a")
        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetAppleM4A
        ) else { throw SmartVideoError.cannotCreateWriter }
        export.outputURL = output
        export.outputFileType = .m4a
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        guard export.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw SmartVideoError.cannotExport(
                export.error?.localizedDescription ??
                    "Không thể ghép thuyết minh theo mốc phụ đề."
            )
        }
        return output
    }
}
