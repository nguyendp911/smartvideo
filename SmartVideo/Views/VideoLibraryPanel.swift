import SwiftUI
import AVKit
import PhotosUI
import UIKit

private enum VideoVaultFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case tiktok = "TikTok"
    case facebook = "Reels"
    case direct = "MP4"
    var id: String { rawValue }
    var source: SocialVideoSource? {
        switch self {
        case .all: return nil
        case .tiktok: return .tiktok
        case .facebook: return .facebook
        case .direct: return .direct
        }
    }
}

/// Saves authorized media in an independent vault. Link-to-MP4 extraction
/// requires a configured, separately hosted resolver; no API keys are shipped
/// inside the app binary.
struct VideoLibraryPanel: View {
    @ObservedObject var model: EditorViewModel
    let onImported: (UUID) -> Void

    @StateObject private var library = SocialVideoLibrary()
    @AppStorage("ViePN.Resolver.BaseURL") private var resolverBaseURL = ""
    @State private var resolverToken = ""
    @State private var linkText = ""
    @State private var photoSelection: PhotosPickerItem?
    @State private var showFilesImporter = false
    @State private var hasPermission = false
    @State private var showServerOptions = false
    @State private var tokenMessage = ""
    @State private var filter: VideoVaultFilter = .all
    @State private var previewItem: SavedSocialVideo?
    @State private var renameTarget: SavedSocialVideo?
    @State private var renameTitle = ""
    @State private var showRename = false
    @State private var pendingDelete: SavedSocialVideo?
    @State private var showDelete = false

    private var filtered: [SavedSocialVideo] {
        library.entries.filter {
            filter.source == nil || $0.source == filter.source
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            downloader
            serverSettings
            vaultList
            Text("Các video trong Kho được lưu trên iPhone. Khi đưa vào " +
                 "timeline, ứng dụng tạo một bản sao trong Media của dự án; " +
                 "xóa khỏi Kho không xóa bản sao đã nhập.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .onAppear {
            library.reload()
            resolverToken = SocialDownloadTokenStore.load()
        }
        .onChange(of: photoSelection?.itemIdentifier) { _ in
            guard let selection = photoSelection else { return }
            Task {
                await library.importFromPhotosPicker(selection)
                photoSelection = nil
            }
        }
        .fileImporter(
            isPresented: $showFilesImporter,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await library.importFromFiles(url) }
                }
            case .failure(let error):
                library.errorText = "Không thể chọn video: \(error.localizedDescription)"
            }
        }
        .sheet(item: $previewItem) { item in
            SavedVideoPreviewSheet(video: item)
        }
        .alert("ViePN Video Downloader",
               isPresented: Binding(
                get: { library.errorText != nil },
                set: { if !$0 { library.errorText = nil } }
               )) {
            Button("Đóng", role: .cancel) {
                library.errorText = nil
            }
        } message: {
            Text(library.errorText ?? "")
        }
        .alert("Đổi tên video", isPresented: $showRename) {
            TextField("Tên video", text: $renameTitle)
            Button("Lưu") {
                if let target = renameTarget {
                    library.rename(target.id, title: renameTitle)
                }
            }
            Button("Hủy", role: .cancel) { }
        }
        .confirmationDialog(
            "Xóa video này khỏi Kho?", isPresented: $showDelete,
            titleVisibility: .visible
        ) {
            Button("Xóa khỏi Kho", role: .destructive) {
                if let target = pendingDelete {
                    library.delete(target.id)
                }
                pendingDelete = nil
            }
            Button("Hủy", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("Các bản sao đã thêm vào timeline hoặc ứng dụng Ảnh được giữ nguyên.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.to.line.compact")
                .font(.title2)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("ViePN Video Downloader")
                    .font(.headline)
                Text("TikTok · Facebook Reels · MP4")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(library.entries.count) video")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.cyan)
        }
    }

    private var downloader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Dán liên kết video")
                .font(.subheadline.bold())

            HStack(spacing: 7) {
                TextField("https://www.tiktok.com/... hoặc facebook.com/reel/...",
                          text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button {
                    if let value = UIPasteboard.general.string {
                        linkText = value.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                    }
                } label: {
                    Label("Dán", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            Toggle("Tôi sở hữu video hoặc được phép tải và lưu",
                   isOn: $hasPermission)
                .font(.caption)
                .tint(.cyan)

            Button {
                let text = linkText
                Task {
                    await library.download(
                        link: text, server: resolverBaseURL,
                        apiKey: resolverToken,
                        hasPermission: hasPermission
                    )
                }
            } label: {
                HStack {
                    Spacer()
                    Label(
                        library.isDownloading ? "Đang tải video..." :
                            "Tải về Kho video",
                        systemImage: "square.and.arrow.down.fill"
                    )
                    .font(.subheadline.bold())
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(linkText.trimmingCharacters(
                in: .whitespacesAndNewlines).isEmpty ||
                !hasPermission || library.isDownloading)

            PhotosPicker(selection: $photoSelection, matching: .videos) {
                HStack {
                    Spacer()
                    Label("Nhập video đã lưu từ Ảnh",
                          systemImage: "photo.on.rectangle.angled")
                        .font(.caption.bold())
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(library.isDownloading)

            Button {
                showFilesImporter = true
            } label: {
                HStack {
                    Spacer()
                    Label("Nhập MP4/MOV từ Files hoặc Safari",
                          systemImage: "folder.badge.plus")
                        .font(.caption.bold())
                    Spacer()
                }
            }
            .buttonStyle(.bordered)
            .disabled(library.isDownloading)

            if library.isDownloading {
                ProgressView("Đang nhận video…")
                    .font(.caption)
            }
            if !library.downloadStatus.isEmpty {
                Text(library.downloadStatus)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            Text("Link HTTPS đến tệp .mp4/.mov tải trực tiếp. Link bài đăng " +
                 "TikTok/Facebook cần một máy chủ Video Resolver riêng " +
                 "được bạn cấu hình; không thể tải trang HTML như MP4.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 11))
    }

    private var serverSettings: some View {
        DisclosureGroup(isExpanded: $showServerOptions) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Máy chủ xử lý link TikTok/Facebook do bạn tự triển khai. " +
                     "Chỉ hỗ trợ nội dung công khai và được phép tải. " +
                     "Không sử dụng cookie, đăng nhập hoặc vượt quyền riêng tư.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("https://video.example.com",
                          text: $resolverBaseURL)
                    .font(.caption)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Khóa truy cập máy chủ", text: $resolverToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button {
                    if SocialDownloadTokenStore.save(resolverToken) {
                        tokenMessage = "Đã lưu khóa trong iOS Keychain."
                    } else {
                        tokenMessage = "Không thể lưu khóa vào Keychain."
                    }
                } label: {
                    Label("Lưu khóa bảo mật",
                          systemImage: "lock.shield")
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if !tokenMessage.isEmpty {
                    Text(tokenMessage)
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
                Text("Mã triển khai server nằm trong thư mục " +
                     "backend/video_resolver trên GitHub. " +
                     "Nếu chưa vận hành máy chủ, hãy dùng nút " +
                     "Save video chính thức của nền tảng rồi nhập từ Ảnh.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 7)
        } label: {
            Label("Thiết lập máy chủ tải TikTok / Facebook",
                  systemImage: "server.rack")
                .font(.subheadline.bold())
        }
        .tint(.cyan)
        .padding(10)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 11))
    }

    private var vaultList: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Kho video đã tải", systemImage: "square.stack.3d.up")
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    library.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            Picker("Nguồn", selection: $filter) {
                ForEach(VideoVaultFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if filtered.isEmpty {
                Text("Chưa có video đã lưu cho nhóm này.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 75)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { item in
                        SavedVideoVaultRow(
                            video: item,
                            onAddToTimeline: {
                                Task {
                                    if let id = await model.importFromDownloadLibrary(item) {
                                        onImported(id)
                                    }
                                }
                            },
                            onPreview: { previewItem = item },
                            onSavePhotos: {
                                Task { await library.saveToPhotos(item) }
                            },
                            onRename: {
                                renameTarget = item
                                renameTitle = item.title
                                showRename = true
                            },
                            onDelete: {
                                pendingDelete = item
                                showDelete = true
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct SavedVideoVaultRow: View {
    let video: SavedSocialVideo
    let onAddToTimeline: () -> Void
    let onPreview: () -> Void
    let onSavePhotos: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            TimelineThumbnail(clip: TimelineClip(
                kind: .video, fileURL: video.fileURL,
                duration: video.duration, originalDuration: video.duration
            ))
            .frame(width: 76, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onTapGesture(perform: onPreview)

            VStack(alignment: .leading, spacing: 5) {
                Text(video.title)
                    .font(.caption.bold())
                    .lineLimit(2)
                Text("\(video.source.rawValue) · " +
                     "\(video.fileSizeText) · " +
                     String(format: "%.0fs", video.duration))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Button {
                        onAddToTimeline()
                    } label: {
                        Label("Chỉnh sửa", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onPreview()
                    } label: {
                        Label("Xem", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption2)

                HStack(spacing: 6) {
                    Button {
                        onSavePhotos()
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    .accessibilityLabel("Lưu vào ứng dụng Ảnh")

                    ShareLink(item: video.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Chia sẻ video")

                    Button {
                        onRename()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Đổi tên")

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Xóa")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SavedVideoPreviewSheet: View {
    let video: SavedSocialVideo
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 9) {
                if let player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Đang mở video…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text("\(video.title) · \(video.fileSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .background(Color.black)
            .navigationTitle("Video trong Kho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                if player == nil {
                    let instance = AVPlayer(url: video.fileURL)
                    player = instance
                    instance.play()
                }
            }
            .onDisappear {
                player?.pause()
                player?.replaceCurrentItem(with: nil)
                player = nil
            }
        }
    }
}
