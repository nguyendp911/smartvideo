import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Independent PIP overlay track

    func importImageOverlay(_ selection: PhotosPickerItem) async {
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw SmartVideoError.invalidMedia("Không tải được ảnh phủ.")
            }
            let file = try MediaStorage.storeOverlayImage(data: data)
            var overlay = ImageOverlayClip(fileURL: file)
            overlay.start = min(timelineSecond, max(0, totalDuration - 0.2))
            overlay.duration = min(3, max(0.2, totalDuration - overlay.start))
            imageOverlays.append(overlay)
        } catch {
            errorText = "Không thêm được overlay: \(error.localizedDescription)"
        }
    }

    /// Detect the primary face and turn its positions into real overlay
    /// keyframes. Requires the entire overlay to fit one source video clip.
    /// All computation is local through Vision/AVFoundation.
    func autoTrackFace(overlayID: UUID) async {
        guard !isTrackingFace && !isTrackingObject else { return }
        guard let overlay = imageOverlays.first(where: { $0.id == overlayID }),
              let target = clipAtTimeline(overlay.start + 0.01),
              clips.indices.contains(target.index) else {
            errorText = "Hãy chọn một overlay ảnh nằm trên đoạn video."
            return
        }
        let clip = clips[target.index]
        let clipStart = timelineStart(of: target.index)
        guard clip.kind == .video,
              overlay.start >= clipStart - 0.001,
              overlay.end <= clipStart + clip.renderedDuration + 0.01 else {
            errorText = "Để tự bám mặt, đặt overlay nằm trọn trong một clip video."
            return
        }
        let startingProject = projectID
        isTrackingFace = true
        faceTrackingMessage = "Đang dò khuôn mặt và tạo keyframe…"
        defer { isTrackingFace = false }

        do {
            let frames = try await OverlayFaceTracker.generate(
                clip: clip, overlay: overlay,
                localStart: overlay.start - clipStart,
                renderSize: canvas.size(for: .hd),
                contentMode: contentMode
            )
            guard startingProject == projectID,
                  clips.contains(where: { $0.id == clip.id && $0 == clip }),
                  let index = imageOverlays.firstIndex(where: {
                      $0.id == overlayID && $0 == overlay
                  }) else {
                throw SmartVideoError.invalidMedia(
                    "Dự án đã thay đổi khi đang phân tích. Hãy thử lại."
                )
            }
            imageOverlays[index].keyframes = frames
            imageOverlays[index].easing = .linear
            imageOverlays[index].pathMode = .straight
            imageOverlays[index].startX = frames.first?.x ?? overlay.startX
            imageOverlays[index].startY = frames.first?.y ?? overlay.startY
            imageOverlays[index].endX = frames.last?.x ?? overlay.endX
            imageOverlays[index].endY = frames.last?.y ?? overlay.endY
            faceTrackingMessage = "Đã tạo \(frames.count) keyframe bám khuôn mặt."
        } catch {
            errorText = "Không theo dõi được khuôn mặt: \(error.localizedDescription)"
            faceTrackingMessage = nil
        }
    }

    /// Vision's VNTrackObjectRequest follows the region underneath the
    /// image overlay. Unlike face detection, this tracks a selected object.
    func autoTrackObject(overlayID: UUID) async {
        guard !isTrackingFace && !isTrackingObject else { return }
        guard let overlay = imageOverlays.first(where: { $0.id == overlayID }),
              let target = clipAtTimeline(overlay.start + 0.01),
              clips.indices.contains(target.index) else {
            errorText = "Hãy chọn một ảnh phủ trên đoạn video để bám vật thể."
            return
        }
        let clip = clips[target.index]
        let clipStart = timelineStart(of: target.index)
        guard clip.kind == .video,
              overlay.start >= clipStart - 0.001,
              overlay.end <= clipStart + clip.renderedDuration + 0.01 else {
            errorText = "Đặt lớp ảnh phủ nằm trọn trong một clip video."
            return
        }
        let initialProject = projectID
        isTrackingObject = true
        objectTrackingMessage = "Đang chạy Vision Object Tracking…"
        defer { isTrackingObject = false }
        do {
            let frames = try await OverlayObjectTracker.generate(
                clip: clip, overlay: overlay,
                localStart: overlay.start - clipStart,
                renderSize: canvas.size(for: .hd),
                contentMode: contentMode
            )
            guard initialProject == projectID,
                  clips.contains(where: { $0.id == clip.id && $0 == clip }),
                  let index = imageOverlays.firstIndex(where: {
                      $0.id == overlayID && $0 == overlay
                  }) else {
                throw SmartVideoError.invalidMedia(
                    "Dự án đã được sửa. Vui lòng thực hiện lại."
                )
            }
            imageOverlays[index].keyframes = frames
            imageOverlays[index].easing = .linear
            imageOverlays[index].pathMode = .straight
            imageOverlays[index].startX = frames.first?.x ?? overlay.startX
            imageOverlays[index].startY = frames.first?.y ?? overlay.startY
            imageOverlays[index].endX = frames.last?.x ?? overlay.endX
            imageOverlays[index].endY = frames.last?.y ?? overlay.endY
            objectTrackingMessage = "Đã tạo \(frames.count) keyframe bám vật thể."
        } catch {
            errorText = "Theo dõi vật thể thất bại: \(error.localizedDescription)"
            objectTrackingMessage = nil
        }
    }
    // MARK: - Image overlay multi-point keyframe editing

    @discardableResult
    func addImageOverlayKeyframe(_ id: UUID, atTimeline second: Double) -> UUID? {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        var overlay = imageOverlays[index]
        guard overlay.duration > 0.15 else { return nil }
        let progress = min(0.985, max(0.015,
            (second - overlay.start) / overlay.duration
        ))
        if overlay.keyframes.isEmpty {
            overlay.keyframes = OverlayKeyframeSampler.frames(for: overlay)
        }
        if let existing = overlay.keyframes.first(where: {
            abs($0.progress - progress) < 0.015
        }) {
            return existing.id
        }
        guard overlay.keyframes.count < 16 else {
            errorText = "Giới hạn 16 keyframe trên mỗi lớp ảnh."
            return nil
        }
        var sample = OverlayKeyframeSampler.sample(
            overlay, atProgress: progress
        )
        sample.id = UUID()
        sample.progress = progress
        overlay.keyframes.append(sample)
        overlay.keyframes.sort { $0.progress < $1.progress }
        imageOverlays[index] = overlay
        return sample.id
    }

    func removeImageOverlayKeyframe(_ id: UUID, frameID: UUID) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard let k = imageOverlays[index].keyframes.firstIndex(where: {
            $0.id == frameID
        }) else { return }
        let frames = imageOverlays[index].keyframes
        // Endpoints anchor the visible segment, never remove them.
        guard k > 0, k < frames.count - 1 else { return }
        imageOverlays[index].keyframes.remove(at: k)
    }

    func applyImageKeyframePreset(_ id: UUID, preset: ImageKeyframePreset) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return
        }
        imageOverlays[index].keyframes = preset.makeFrames(
            from: imageOverlays[index]
        )
    }

    func clearImageKeyframes(_ id: UUID) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }) else {
            return
        }
        let current = imageOverlays[index]
        let frames = OverlayKeyframeSampler.frames(for: current)
        guard let first = frames.first, let last = frames.last else { return }
        imageOverlays[index].startX = first.x
        imageOverlays[index].startY = first.y
        imageOverlays[index].endX = last.x
        imageOverlays[index].endY = last.y
        imageOverlays[index].scale = first.scale
        imageOverlays[index].opacity = first.opacity
        imageOverlays[index].rotationDegrees = first.rotationDegrees
        imageOverlays[index].keyframes = []
    }

    func translateImageOverlay(_ id: UUID, dx: Double, dy: Double) {
        guard let index = imageOverlays.firstIndex(where: { $0.id == id }),
              dx.isFinite, dy.isFinite else { return }
        let item = imageOverlays[index]
        let frames = OverlayKeyframeSampler.frames(for: item)
        let minX = frames.map(\.x).min() ?? 0.5
        let maxX = frames.map(\.x).max() ?? 0.5
        let minY = frames.map(\.y).min() ?? 0.5
        let maxY = frames.map(\.y).max() ?? 0.5
        let shiftX = min(max(dx, 0.03 - minX), 0.97 - maxX)
        let shiftY = min(max(dy, 0.03 - minY), 0.97 - maxY)
        if item.keyframes.isEmpty {
            imageOverlays[index].startX += shiftX
            imageOverlays[index].endX += shiftX
            imageOverlays[index].startY += shiftY
            imageOverlays[index].endY += shiftY
        } else {
            for frameIndex in imageOverlays[index].keyframes.indices {
                imageOverlays[index].keyframes[frameIndex].x += shiftX
                imageOverlays[index].keyframes[frameIndex].y += shiftY
            }
        }
    }

    func removeImageOverlay(_ id: UUID) {
        imageOverlays.removeAll { $0.id == id }
    }

    func importVideoOverlay(_ selection: PhotosPickerItem) async {
        guard videoOverlays.count < 4 else {
            errorText = "Tối đa bốn lớp video PIP để tránh quá tải iPhone."
            return
        }
        do {
            guard let movie = try await selection.loadTransferable(type: PickedMovie.self) else {
                throw SmartVideoError.invalidMedia("Không tải được video PIP.")
            }
            let asset = AVURLAsset(url: movie.url)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else {
                throw SmartVideoError.invalidMedia("Tệp overlay không có hình ảnh video.")
            }
            let seconds = try await asset.load(.duration).seconds
            guard seconds.isFinite && seconds > 0.1 else {
                throw SmartVideoError.invalidMedia("Thời lượng video PIP không hợp lệ.")
            }
            var item = VideoOverlayClip(fileURL: movie.url)
            item.start = min(timelineSecond, max(0, totalDuration - 0.2))
            item.duration = min(seconds, max(0.1, totalDuration - item.start))
            item.sourceDuration = seconds
            videoOverlays.append(item)
        } catch {
            errorText = "Không nhập được video Overlay: \(error.localizedDescription)"
        }
    }

    func addTextOverlay() {
        guard totalDuration > 0 else {
            errorText = "Hãy thêm clip video/ảnh trước khi tạo lớp chữ."
            return
        }
        var item = TextOverlayClip()
        item.start = min(timelineSecond, max(0, totalDuration - 0.2))
        item.duration = min(3, max(0.1, totalDuration - item.start))
        textOverlays.append(item)
    }

    func removeVideoOverlay(_ id: UUID) {
        videoOverlays.removeAll { $0.id == id }
    }

    func removeTextOverlay(_ id: UUID) {
        textOverlays.removeAll { $0.id == id }
    }
}
