import Foundation

extension MusicVideoStudio {
    enum ExportResolution: Int, CaseIterable, Identifiable, Codable {
        case p720 = 720
        case p1080 = 1080
        case p1440 = 1440
        case p2160 = 2160

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .p720: return "720p HD"
            case .p1080: return "1080p Full HD"
            case .p1440: return "2K (1440p)"
            case .p2160: return "4K (2160p)"
            }
        }
    }

    enum ExportCodec: String, CaseIterable, Identifiable, Codable {
        case h264 = "H.264"
        case hevc = "HEVC (H.265)"
        var id: String { rawValue }
    }

    enum ExportContainer: String, CaseIterable, Identifiable, Codable {
        case mp4 = "MP4"
        case mov = "MOV"
        var id: String { rawValue }
        var fileExtension: String { self == .mp4 ? "mp4" : "mov" }
    }

    /// How the video is written. Everything about the PICTURE comes from the project itself:
    /// the export asks `TimelineEngine` for the layers at each frame time, exactly like the preview.
    struct ExportSettings: Equatable, Codable {
        var resolution = ExportResolution.p1080
        var fps = 30
        var codec = ExportCodec.h264
        var container = ExportContainer.mp4

        static let supportedFPS = [24, 30, 60]
        static let audioBitrate = 192_000
        static let maxDurationSeconds = 3_600.0

        init(resolution: ExportResolution = .p1080, fps: Int = 30, codec: ExportCodec = .h264, container: ExportContainer = .mp4) {
            self.resolution = resolution
            self.fps = fps
            self.codec = codec
            self.container = container
        }

        /// Settings with an unsupported frame rate replaced by 30.
        var sanitized: ExportSettings {
            var copy = self
            if !Self.supportedFPS.contains(copy.fps) { copy.fps = 30 }
            return copy
        }

        /// Pixel size for the project's aspect ratio; the resolution is the SHORT side (even numbers).
        func size(aspect: AspectRatio) -> (width: Int, height: Int) {
            aspect.pixelSize(shortSide: resolution.rawValue)
        }

        /// Average video bit rate (bits/s). More for H.264 than for HEVC at the same quality; capped.
        func videoBitrate(aspect: AspectRatio) -> Int {
            let s = size(aspect: aspect)
            let bitsPerPixel = codec == .hevc ? 0.085 : 0.12
            let rate = Double(s.width * s.height * sanitized.fps) * bitsPerPixel
            return min(80_000_000, max(2_000_000, Int(rate)))
        }

        /// Number of frames that cover `duration` (the last one may extend a little past it).
        func totalFrames(duration: ProjectTime) -> Int {
            guard duration.ticks > 0 else { return 0 }
            let per = ProjectTime.ticksPerFrame(fps: sanitized.fps)
            return Int((duration.ticks + per - 1) / per)
        }

        /// The project time of frame `index`: exact integer ticks, the same clock as the preview.
        func frameTime(_ index: Int) -> ProjectTime { .frame(max(0, index), fps: sanitized.fps) }

        func estimatedBytes(duration: ProjectTime, aspect: AspectRatio) -> Int64 {
            let bitsPerSecond = Double(videoBitrate(aspect: aspect) + Self.audioBitrate)
            return Int64(bitsPerSecond / 8 * max(0, duration.seconds) * 1.05)
        }

        /// Reasons the export cannot start, in plain Vietnamese. Empty = fine.
        func problems(duration: ProjectTime, hasVisuals: Bool) -> [String] {
            var found: [String] = []
            if duration.ticks <= 0 { found.append("Dự án chưa có nội dung.") }
            else if duration.seconds > Self.maxDurationSeconds { found.append("Video dài tối đa 60 phút.") }
            if !hasVisuals { found.append("Thêm ít nhất một ảnh hoặc lớp hình trước khi xuất.") }
            return found
        }

        func fileName(projectName: String, at date: Date = Date()) -> String {
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
            var base = String(projectName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
                .trimmingCharacters(in: .whitespaces)
            if base.isEmpty { base = "MusicVideo" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            return "\(base.prefix(40))-\(formatter.string(from: date)).\(container.fileExtension)"
        }
    }
}
