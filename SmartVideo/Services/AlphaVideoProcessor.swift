import Foundation
import AVFoundation
import CoreImage
import CoreVideo

/// Gives PIP videos a real alpha channel before they are composited.
///
/// AVFoundation's built-in compositor cannot key a track, so every keyed PIP
/// is transcoded once (only the part the project uses) into an HEVC-with-alpha
/// MOV, frame by frame through Core Image: chroma key, or the Vision person
/// matte. The result is cached by content, so re-exporting is instant and
/// the source file is never modified. `resolve` returns overlays whose
/// `fileURL` already points at the transparent copy.
enum AlphaVideoProcessor {
    static let maxSeconds = 60.0
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func resolve(_ overlays: [VideoOverlayClip]) async throws -> [VideoOverlayClip] {
        var output: [VideoOverlayClip] = []
        for overlay in overlays {
            guard overlay.alphaMode != .none else {
                output.append(overlay)
                continue
            }
            try Task.checkCancellation()
            var next = overlay
            next.fileURL = try await keyedCopy(of: overlay)
            // The copy contains only the used range, starting at zero.
            next.sourceStart = 0
            next.alphaMode = .none
            output.append(next)
        }
        return output
    }

    static func keyedCopy(of overlay: VideoOverlayClip) async throws -> URL {
        let asset = AVURLAsset(url: overlay.fileURL)
        guard let track = try await asset.loadTracks(
            withMediaType: .video
        ).first else {
            throw SmartVideoError.missingVideoTrack(overlay.filename)
        }
        let total = try await asset.load(.duration).seconds
        guard total.isFinite, total > 0.05 else {
            throw SmartVideoError.invalidMedia("Overlay video có thời lượng lỗi.")
        }
        let from = min(max(0, overlay.sourceStart), max(0, total - 0.05))
        let length = min(maxSeconds, overlay.duration, total - from)
        guard length > 0.04 else {
            throw SmartVideoError.invalidMedia("Overlay video quá ngắn để tách nền.")
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let width = (Int(natural.width) / 2) * 2
        let height = (Int(natural.height) / 2) * 2
        guard width >= 16, height >= 16 else {
            throw SmartVideoError.invalidMedia("Kích thước overlay video không hợp lệ.")
        }

        let target = MediaStorage.temporaryDirectory.appendingPathComponent(
            "alpha-\(cacheKey(overlay, from: from, length: length)).mov"
        )
        if FileManager.default.fileExists(atPath: target.path) { return target }
        let partial = target.deletingLastPathComponent()
            .appendingPathComponent("partial-\(UUID().uuidString).mov")

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: from, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        guard reader.canAdd(readerOutput) else { throw SmartVideoError.cannotCreateWriter }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw SmartVideoError.cannotExport(
                "Thiết bị này không mã hóa được HEVC có kênh alpha nên chưa tách nền được video overlay."
            )
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        // Frames are read un-rotated; keep the original orientation flag so
        // the composition's existing PIP transform math stays valid.
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw SmartVideoError.cannotCreateWriter }
        writer.add(input)

        guard reader.startReading() else {
            throw reader.error ?? SmartVideoError.invalidMedia("Không đọc được overlay video.")
        }
        guard writer.startWriting() else {
            throw writer.error ?? SmartVideoError.cannotCreateWriter
        }
        writer.startSession(atSourceTime: .zero)

        do {
            let origin = CMTime(seconds: from, preferredTimescale: 600)
            while let sample = readerOutput.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
                let time = CMTimeSubtract(
                    CMSampleBufferGetPresentationTimeStamp(sample), origin
                )
                guard time.seconds > -0.001 else { continue }

                let frame = apply(overlay.alphaMode,
                                  to: CIImage(cvPixelBuffer: pixels),
                                  tolerance: overlay.chromaTolerance,
                                  softness: overlay.chromaSoftness)
                guard let pool = adaptor.pixelBufferPool else {
                    throw SmartVideoError.cannotCreateWriter
                }
                var created: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created)
                guard let buffer = created else { throw SmartVideoError.cannotCreateWriter }
                context.render(
                    frame, to: buffer,
                    bounds: CGRect(x: 0, y: 0, width: width, height: height),
                    colorSpace: CGColorSpaceCreateDeviceRGB()
                )
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 4_000_000)
                }
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw writer.error ?? SmartVideoError.cannotExport(
                        "Không ghi được khung hình có alpha."
                    )
                }
            }
            if reader.status == .failed, let error = reader.error { throw error }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? SmartVideoError.cannotExport(
                    "Không hoàn tất được video overlay có alpha."
                )
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: partial, to: target)
            return target
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    private static func apply(
        _ mode: VideoAlphaMode, to source: CIImage,
        tolerance: Double, softness: Double
    ) -> CIImage {
        switch mode {
        case .none:
            return source
        case .chromaGreen:
            return ChromaKeyProcessor.keyed(source, color: .green,
                                            tolerance: tolerance, softness: softness)
        case .chromaBlue:
            return ChromaKeyProcessor.keyed(source, color: .blue,
                                            tolerance: tolerance, softness: softness)
        case .person:
            let clear = CIImage(color: .clear).cropped(to: source.extent)
            // A frame without a detectable person becomes fully transparent.
            guard let mask = try? PersonCutoutProcessor.personMask(source) else {
                return clear
            }
            return source.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: clear,
                kCIInputMaskImageKey: mask
            ])
        }
    }

    /// Stable across launches (unlike `hashValue`), so the cache survives.
    private static func cacheKey(
        _ overlay: VideoOverlayClip, from: Double, length: Double
    ) -> String {
        let modified = (try? overlay.fileURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate?.timeIntervalSince1970) ?? 0
        let text = [
            overlay.fileURL.path, "\(modified)", "\(from)", "\(length)",
            overlay.alphaMode.rawValue,
            "\(overlay.chromaTolerance)", "\(overlay.chromaSoftness)"
        ].joined(separator: "|")
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
