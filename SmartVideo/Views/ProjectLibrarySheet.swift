import SwiftUI

/// Local project browser. Project JSON lives under Documents/Projects;
/// original media stays in Documents/Media and is not duplicated.
struct ProjectLibrarySheet: View {
    @ObservedObject var model: EditorViewModel
    var didLoad: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section("Dự án hiện tại") {
                    TextField("Tên dự án", text: $model.projectName)
                        .textInputAutocapitalization(.sentences)
                    Button {
                        model.saveProject()
                    } label: {
                        Label("Lưu dự án hiện tại", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.clips.isEmpty)
                    Button {
                        model.newProject()
                        didLoad()
                        dismiss()
                    } label: {
                        Label("Tạo dự án mới", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
                Section("Dự án đã lưu") {
                    if model.availableProjects.isEmpty {
                        Text("Chưa có dự án đã lưu.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.availableProjects) { entry in
                        HStack(spacing: 8) {
                            Button {
                                model.loadProject(entry.id)
                                if model.projectID == entry.id {
                                    didLoad()
                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.name).font(.subheadline.bold())
                                    Text("\(entry.clipCount) clip · " +
                                         entry.savedAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                         ))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) {
                                pendingDeletion = entry.id
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Text("Tệp dự án chỉ tham chiếu ảnh, video và âm thanh trong ứng dụng. Trước khi xóa app, hãy sao lưu dữ liệu; một bản JSON riêng không thay thế được các file nguồn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dự án ViePN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .onAppear { model.refreshProjects() }
            .alert("Xóa dự án đã lưu?", isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )) {
                Button("Xóa", role: .destructive) {
                    if let id = pendingDeletion { model.deleteProject(id) }
                    pendingDeletion = nil
                }
                Button("Hủy", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Chỉ xóa tệp dự án JSON, không xóa media gốc.")
            }
        }
    }
}
