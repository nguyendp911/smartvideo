import SwiftUI
import AVKit

/// Synchronized draft viewer. This plays a genuine 720p MP4 rendered by
/// the *same pipeline as export*, not a pretend real-time composition.
struct RenderedPreviewSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("Đang mở bản dựng nháp…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text("Preview 720p được dựng từ toàn bộ timeline, gồm tiếng gốc, nhạc, giọng đọc, SFX, Overlay, chuyển cảnh và VFX. Đây là MP4 đã render, không phải preview tức thời.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 15)
            }
            .background(Color.black)
            .navigationTitle("Xem thử bản dựng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear {
                if player == nil {
                    let item = AVPlayerItem(url: url)
                    let instance = AVPlayer(playerItem: item)
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
