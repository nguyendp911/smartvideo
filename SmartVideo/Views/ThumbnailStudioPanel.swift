import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

/// A separate cover JPEG is intentional: MP4 poster artwork is not
/// consistently honoured by Photos, Facebook, TikTok or other uploaders.
struct ThumbnailStudioPanel: View {
    let videoURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cover: UIImage?
    @State private var coverURL: URL?
    @State private var duration: Double = 0
    @State private var time: Double = 0
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Chọn khung hình bất kỳ từ MP4 đã xuất hoặc tải ảnh bìa riêng. Bìa được lưu ở độ phân giải gốc, không chụp màn hình preview.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Group {
                        if let cover {
                            Image(uiImage: cover).resizable()
                                .scaledToFit()
                        } else {
                            ContentUnavailableView("Chưa có ảnh bìa",
                                systemImage: "photo.on.rectangle")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 160)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    if duration > 0 {
                        Text("Khung hình: \(time, specifier: "%.2f") giây / \(duration, specifier: "%.2f") giây")
                            .font(.caption.monospacedDigit())
                        Slider(value: $time, in: 0...max(0.01, duration - 0.05))
                            .onChange(of: time) { _ in requestFrame() }
                        Button("Lấy khung hình này") { requestFrame() }
                            .buttonStyle(.bordered)
                    }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Chọn ảnh bìa từ thư viện", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        guard let cover else { return }
                        do {
                            coverURL = try writeJPEG(cover)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Xuất ảnh bìa JPG", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cover == nil || busy)
                    if let coverURL {
                        ShareLink(item: coverURL) {
                            Label("Chia sẻ ảnh bìa", systemImage: "square.and.arrow.up")
                        }
                        Text(coverURL.lastPathComponent)
                            .font(.caption2).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if busy { ProgressView("Đang lấy khung hình…") }
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
                    }
                    Text("Lưu ý: JPG là tệp bìa riêng. Khi tải video lên TikTok, Facebook hoặc YouTube, hãy chọn ảnh này trong phần chỉnh sửa bìa của nền tảng.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Ảnh bìa video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task(id: videoURL) {
                guard let videoURL else { return }
                let asset = AVURLAsset(url: videoURL)
                duration = max(0, (try? await asset.load(.duration).seconds) ?? 0)
                requestFrame()
            }
            .onChange(of: selectedPhoto) { photo in
                guard let photo else { return }
                generation += 1
                Task {
                    do {
                        guard let data = try await photo.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else {
                            errorMessage = "Không đọc được ảnh đã chọn."
                            return
                        }
                        cover = image
                        coverURL = nil
                        errorMessage = nil
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
    }

    private func requestFrame() {
        guard let videoURL else { return }
        generation += 1
        let request = generation
        let requestedSecond = time
        busy = true
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            do {
                let image = try await Task.detached(priority: .userInitiated) {
                    let cg = try generator.copyCGImage(
                        at: CMTime(seconds: requestedSecond, preferredTimescale: 600),
                        actualTime: nil
                    )
                    return UIImage(cgImage: cg)
                }.value
                guard request == generation else { return }
                cover = image
                coverURL = nil
                errorMessage = nil
            } catch {
                guard request == generation else { return }
                errorMessage = "Không lấy được khung hình: \(error.localizedDescription)"
            }
            if request == generation { busy = false }
        }
    }

    private func writeJPEG(_ image: UIImage) throws -> URL {
        guard let data = image.jpegData(compressionQuality: 0.96) else {
            throw NSError(domain: "Thumbnail", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Không thể mã hóa ảnh bìa JPG."])
        }
        let folder = MediaStorage.exportsDirectory
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("ViePN-Cover-\(UUID().uuidString).jpg")
        try data.write(to: output, options: .atomic)
        return output
    }
}
