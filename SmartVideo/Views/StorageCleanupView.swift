import SwiftUI

/// Shows how much space renders use and lets the user free it.
struct StorageCleanupView: View {
    @State private var exports = StorageCleaner.exportsSummary()
    @State private var temp = StorageCleaner.temporarySummary()
    @State private var message = ""
    @State private var confirmExports = false

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dung lượng bản dựng").font(.caption.bold())
            Text("Bản xuất MP4/ảnh: \(exports.count) tệp, \(size(exports.bytes)). Bộ nhớ tạm và cache tách nền: \(temp.count) tệp, \(size(temp.bytes)).")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button("Dọn bộ nhớ tạm") {
                    let removed = StorageCleaner.purgeAllTemporary()
                    message = "Đã xóa \(removed) tệp tạm."
                    refresh()
                }
                Button("Xóa bản xuất cũ hơn 7 ngày", role: .destructive) {
                    confirmExports = true
                }
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            if !message.isEmpty {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .confirmationDialog(
            "Xóa vĩnh viễn các bản xuất cũ hơn 7 ngày? Không thể hoàn tác; video đã lưu vào Ảnh không bị ảnh hưởng.",
            isPresented: $confirmExports, titleVisibility: .visible
        ) {
            Button("Xóa bản xuất cũ", role: .destructive) {
                let removed = StorageCleaner.purgeExports(olderThanDays: 7)
                message = "Đã xóa \(removed) bản xuất cũ."
                refresh()
            }
            Button("Hủy", role: .cancel) {}
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        exports = StorageCleaner.exportsSummary()
        temp = StorageCleaner.temporarySummary()
    }
}
