import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import Vision
import UIKit

extension EditorViewModel {
    // MARK: - Mockup Light & Shadow

    /// On-device face detection for a single media frame at the playhead.
    /// User can override the proposed position with the X/Y sliders.
    func autoFitMockup(_ id: UUID) {
        guard let selected = mockupOverlays.firstIndex(where: {
            $0.id == id
        }), !clips.isEmpty else {
            errorText = "Hãy chọn mockup và thêm ảnh/video."
            return
        }
        let snapshot = mockupOverlays[selected]
        let playTime = max(0, timelineSecond)
        guard let selectedClip = clipAtTimeline(playTime) else {
            errorText = "Không tìm thấy ảnh/video tại vị trí con trỏ."
            return
        }
        let clip = clips[selectedClip.index]
        Task {
            do {
                let image: CGImage
                if clip.kind == .image,
                   let still = UIImage(contentsOfFile: clip.fileURL.path)?
                    .cgImage {
                    image = still
                } else {
                    let generator = AVAssetImageGenerator(
                        asset: AVURLAsset(url: clip.fileURL)
                    )
                    generator.appliesPreferredTrackTransform = true
                    let at = clip.startTime +
                        selectedClip.local * clip.playbackSpeed
                    image = try generator.copyCGImage(
                        at: CMTime(seconds: max(0, at),
                                   preferredTimescale: 600),
                        actualTime: nil
                    )
                }
                let request = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(
                    cgImage: image, options: [:]
                ).perform([request])
                let faces = request.results?.map {
                    CGRect(x: $0.boundingBox.minX,
                           y: 1 - $0.boundingBox.maxY,
                           width: $0.boundingBox.width,
                           height: $0.boundingBox.height)
                } ?? []
                let location = TextAutoPlacement.bestPosition(
                    normalizedFaceBoxes: faces
                )
                guard let index = mockupOverlays.firstIndex(where: {
                    $0.id == id
                }), mockupOverlays[index] == snapshot else { return }
                checkpoint()
                mockupOverlays[index].centerX = location.x
                mockupOverlays[index].centerY = location.y
                mockupOverlays[index].avoidFace = true
            } catch {
                errorText = "Không thể tự căn mockup: \(error.localizedDescription)"
            }
        }
    }
    // MARK: - Text glyph media and AI layout

    func importTextFill(
        from sourceURL: URL, for textID: UUID, video: Bool
    ) {
        guard textOverlays.contains(where: { $0.id == textID }) else {
            errorText = "Hãy chọn một lớp chữ trước."
            return
        }
        do {
            let local = try copyScoped(
                sourceURL, fallbackExtension: video ? "mov" : "png"
            )
            Task {
                do {
                    if video {
                        let asset = AVURLAsset(url: local)
                        guard !(try await asset.loadTracks(
                            withMediaType: .video
                        )).isEmpty else {
                            throw SmartVideoError.invalidMedia(
                                "Tệp này không chứa video hợp lệ."
                            )
                        }
                    } else {
                        guard UIImage(contentsOfFile: local.path) != nil
                        else {
                            throw SmartVideoError.invalidMedia(
                                "Không đọc được ảnh dùng để tô chữ."
                            )
                        }
                    }
                    guard let index = textOverlays.firstIndex(where: {
                        $0.id == textID
                    }) else { return }
                    checkpoint()
                    textOverlays[index].fillAssetURL = local
                    textOverlays[index].fillMode = video ?
                        .video : .image
                } catch {
                    try? FileManager.default.removeItem(at: local)
                    errorText = "Không chọn được nền chữ: \(error.localizedDescription)"
                }
            }
        } catch {
            errorText = "Không mở được tệp nền chữ: \(error.localizedDescription)"
        }
    }

    /// Face-aware text position suggestions run ON DEVICE using Vision.
    /// Detects faces, then ranks clear corners; no cloud account required.
    func autoPositionText(_ textID: UUID, clip: TimelineClip?) {
        guard let clip else {
            errorText = "Hãy chọn ảnh/video trên timeline."
            return
        }
        Task {
            do {
                let image: CGImage
                if clip.kind == .image,
                   let photo = UIImage(contentsOfFile: clip.fileURL.path)?
                    .cgImage {
                    image = photo
                } else {
                    let asset = AVURLAsset(url: clip.fileURL)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    image = try generator.copyCGImage(
                        at: CMTime(
                            seconds: clip.startTime,
                            preferredTimescale: 600
                        ),
                        actualTime: nil
                    )
                }
                let request = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(
                    cgImage: image, options: [:]
                ).perform([request])
                let faces = request.results?.map {
                    CGRect(
                        x: $0.boundingBox.midX,
                        y: 1 - $0.boundingBox.midY,
                        width: $0.boundingBox.width,
                        height: $0.boundingBox.height
                    )
                } ?? []
                let point = TextAutoPlacement.bestPosition(
                    normalizedFaceBoxes: faces
                )
                guard let index = textOverlays.firstIndex(where: {
                    $0.id == textID
                }) else { return }
                checkpoint()
                textOverlays[index].startX = point.x
                textOverlays[index].startY = point.y
                textOverlays[index].endX = point.x
                textOverlays[index].endY = point.y
                textOverlays[index].keyframes = []
            } catch {
                errorText = "Không phân tích được vùng mặt: \(error.localizedDescription)"
            }
        }
    }
}
