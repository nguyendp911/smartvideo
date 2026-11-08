import SwiftUI

struct MetadataPanel: View {
    @ObservedObject var model: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Metadata khi xuất MP4", systemImage: "tag")
                .font(.headline)

            Toggle("Lọc metadata của tệp nguồn", isOn: $model.stripMetadata)
                .font(.caption)

            Toggle("Gắn metadata do tôi nhập", isOn: $model.addCustomMetadata)
                .font(.caption)
                .tint(.cyan)

            if model.addCustomMetadata {
                Group {
                    field("Tiêu đề", text: $model.metadata.title, hint: "Tên video")
                    field("Tác giả", text: $model.metadata.author, hint: "Người tạo")
                    field("Mô tả", text: $model.metadata.description, hint: "Giới thiệu video")
                    field("Bản quyền", text: $model.metadata.copyright, hint: "© Chủ sở hữu")
                    field("Từ khóa", text: $model.metadata.keywords, hint: "gameplay, cinematic")
                    field("Thể loại", text: $model.metadata.genre, hint: "Ví dụ: Education")
                    field("Ghi chú", text: $model.metadata.comment, hint: "Thông tin bổ sung")
                    field("Năm", text: $model.metadata.year, hint: "2026")
                }
                Button("Điền thông tin ViePN mẫu") {
                    model.metadata.title = "ViePN Smart Video"
                    model.metadata.author = "ViePN"
                    model.metadata.description = "Video được dựng bằng ViePN Smart Video"
                    model.metadata.keywords = "ViePN, video"
                    model.metadata.genre = "Video"
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            Text("Dữ liệu mới được ghi vào container MP4 khi xuất nếu định dạng hỗ trợ; từng ứng dụng có thể không hiển thị tất cả trường. Lọc metadata nguồn không xóa các thông số kỹ thuật như thời lượng, codec hoặc độ phân giải.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func field(_ label: String, text: Binding<String>,
                       hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.bold())
            TextField(hint, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
        }
    }
}
