import Foundation
import AVFoundation
import CoreMedia

struct MediaInspection: Identifiable {
    let id = UUID()
    let filename: String
    let fileSize: Int64?
    let duration: Double?
    let videoCodec: String?
    let width: Int?
    let height: Int?
    let nominalFrameRate: Float?
    let minFrameDuration: Double?
    let videoBitrate: Double?
    let hasAudio: Bool
    let audioCodec: String?
    let audioSampleRate: Double?
    let audioChannels: Int?
    let isHDR: Bool?
    let warnings: [String]

    var report: String {
        var rows = [
            "ViePN Smart Video · Media Inspector",
            "Tệp: \(filename)",
            "Dung lượng: \(fileSize.map(Self.bytes) ?? "Không đọc được")",
            "Thời lượng: \(duration.map { String(format: "%.2f giây", $0) } ?? "Không đọc được")",
            "Video: \(videoCodec ?? "Không rõ codec") · \(width.map(String.init) ?? "?")×\(height.map(String.init) ?? "?")",
            "FPS danh nghĩa: \(nominalFrameRate.map { String(format: "%.3f", $0) } ?? "Không có metadata")",
            "Bitrate video: \(videoBitrate.map { Self.bits($0) } ?? "Không có metadata")",
            "HDR: \(isHDR.map { $0 ? "Có" : "Không phát hiện" } ?? "Không xác định")",
            "Âm thanh: \(hasAudio ? (audioCodec ?? "Có track, codec không rõ") : "Không có track audio")"
        ]
        if let audioSampleRate {
            rows.append("Tần số audio: \(Int(audioSampleRate.rounded())) Hz · \(audioChannels.map(String.init) ?? "?") kênh")
        }
        if let minFrameDuration, minFrameDuration > 0 {
            rows.append(String(format: "Khung hình dài nhất ghi trong metadata: %.4f giây", minFrameDuration))
        }
        rows.append(contentsOf: warnings.isEmpty
            ? ["Cảnh báo: Không phát hiện dấu hiệu phổ biến."]
            : ["Cảnh báo:"] + warnings.map { "• \($0)" })
        rows.append("Báo cáo được tạo cục bộ trên thiết bị.")
        return rows.joined(separator: "\n")
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private static func bits(_ value: Double) -> String {
        String(format: "%.2f Mbps", value / 1_000_000)
    }
}

enum MediaInspector {
    static func inspect(_ url: URL) async throws -> MediaInspection {
        let asset = AVURLAsset(url: url)
        async let videoTracksTask = asset.loadTracks(withMediaType: .video)
        async let audioTracksTask = asset.loadTracks(withMediaType: .audio)
        async let durationTask = asset.load(.duration)
        let videoTracks = try await videoTracksTask
        let audioTracks = try await audioTracksTask
        let time = try await durationTask
        let seconds = time.seconds.isFinite && time.seconds > 0 ? time.seconds : nil
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value

        var codec: String?
        var width: Int?
        var height: Int?
        var fps: Float?
        var frameDuration: Double?
        var bitrate: Double?
        var hdr: Bool?
        if let track = videoTracks.first {
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            if let description = descriptions.first {
                let mediaSubtype = CMFormatDescriptionGetMediaSubType(description)
                codec = FourCharCodeText.string(mediaSubtype)
                width = Int(CMVideoFormatDescriptionGetDimensions(description).width)
                height = Int(CMVideoFormatDescriptionGetDimensions(description).height)
                let extensions = CMFormatDescriptionGetExtensions(description) as NSDictionary
                let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
                let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String
                let hdrTransfers = [kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
                                    kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG]
                hdr = transfer.map { hdrTransfers.contains($0) }
                if hdr == nil, let primaries {
                    hdr = primaries == kCMFormatDescriptionColorPrimaries_ITU_R_2020
                }
            }
            let nominal = try? await track.load(.nominalFrameRate)
            if let nominal, nominal.isFinite, nominal > 0 { fps = nominal }
            let minDuration = try? await track.load(.minFrameDuration)
            if let minDuration, minDuration.isNumeric, minDuration.seconds.isFinite,
               minDuration.seconds > 0 { frameDuration = minDuration.seconds }
            let estimated = try? await track.load(.estimatedDataRate)
            if let estimated, estimated.isFinite, estimated > 0 { bitrate = Double(estimated) }
        }

        var audioCodec: String?
        var sampleRate: Double?
        var channels: Int?
        if let track = audioTracks.first {
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            if let description = descriptions.first {
                audioCodec = FourCharCodeText.string(CMFormatDescriptionGetMediaSubType(description))
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
                if let asbd {
                    sampleRate = asbd.mSampleRate > 0 ? asbd.mSampleRate : nil
                    channels = asbd.mChannelsPerFrame > 0 ? Int(asbd.mChannelsPerFrame) : nil
                }
            }
        }

        var warnings: [String] = []
        if videoTracks.isEmpty { warnings.append("Không có video track hợp lệ.") }
        if videoTracks.count > 1 { warnings.append("Có nhiều video track; đường dựng hiện tại có thể chỉ dùng một track chính.") }
        if audioTracks.count > 1 { warnings.append("Có nhiều audio track; một số track phụ có thể không được trộn khi dựng.") }
        if let width, let height, max(width, height) > 3840 {
            warnings.append("Độ phân giải vượt 4K; cân nhắc dùng bản 720p hoặc 1080p để giảm tải.") }
        if let fps, fps > 60 {
            warnings.append("Tốc độ khung hình trên 60 FPS; đầu ra dự án hiện tại là 30 FPS.") }
        if hdr == true {
            warnings.append("Nguồn HDR; màu hoặc độ sáng có thể đổi khi chuyển sang đầu ra SDR.") }
        if audioTracks.isEmpty { warnings.append("Không có tiếng gốc trong tệp.") }
        if let size, size > 1_500_000_000 {
            warnings.append("Tệp lớn hơn 1.5 GB; cần đủ dung lượng trống cho bản xuất và file trung gian.") }
        if seconds == nil { warnings.append("Không đọc được thời lượng hợp lệ.") }

        return MediaInspection(filename: url.lastPathComponent, fileSize: size,
                               duration: seconds, videoCodec: codec, width: width,
                               height: height, nominalFrameRate: fps,
                               minFrameDuration: frameDuration, videoBitrate: bitrate,
                               hasAudio: !audioTracks.isEmpty, audioCodec: audioCodec,
                               audioSampleRate: sampleRate, audioChannels: channels,
                               isHDR: hdr, warnings: warnings)
    }
}

private enum FourCharCodeText {
    static func string(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff), UInt8(code & 0xff)
        ]
        let value = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        return value?.isEmpty == false ? value! : String(format: "0x%08X", code)
    }
}
