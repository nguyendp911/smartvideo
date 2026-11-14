import SwiftUI
import PhotosUI

/// Distinct photo-only workflow. Nothing here routes to MP4.
struct AIPhotoEditorPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?

    @State private var importedPhoto: PhotosPickerItem?
    @State private var importingPhoto = false
    @State private var saveAfterExport = false

    private var selectedPhotoID: UUID? {
        guard let selectedClipID,
              model.clips.contains(where: {
                  $0.id == selectedClipID && $0.kind == .image
              }) else {
            return model.clips.first(where: {
                $0.kind == .image
            })?.id
        }
        return selectedClipID
    }

    private var photosCount: Int {
        model.clips.filter { $0.kind == .image }.count
    }

    private var working: Bool {
        importingPhoto || model.isImporting ||
        model.isExportingPhoto || model.isExporting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("AI Photo Editor • Xuất ảnh HQ",
                  systemImage: "photo.artframe")
                .font(.headline)
            Text("Ảnh vào → AI chỉnh sáng, màu, độ nét → xuất JPG/PNG/HEIC thực. Giữ nguyên ảnh gốc, không tạo MP4.")
                .font(.caption)
                .foregroundStyle(.secondary)

            PhotosPicker(
                selection: $importedPhoto,
                matching: .images
            ) {
                Label("Nhập ảnh mới để AI chỉnh và xuất",
                      systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(working)

            if let id = selectedPhotoID,
               let photo = model.clips.first(where: { $0.id == id }) {
                Text("Đang chọn: " + photo.filename)
                    .font(.caption.bold())
                    .lineLimit(1)
            } else {
                Text("Chưa có ảnh. Hãy nhập một ảnh để bắt đầu.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Picker("Định dạng", selection: $model.photoExportSettings.format) {
                    ForEach(PhotoExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.menu)
                Picker("Độ phân giải",
                       selection: $model.photoExportSettings.resolution) {
                    ForEach(PhotoResolution.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)
            }
            .font(.caption)

            if model.photoExportSettings.resolution == .custom {
                HStack(spacing: 8) {
                    TextField("Rộng", value: $model.photoExportSettings.customWidth,
                              format: .number)
                        .keyboardType(.numberPad)
                    Text("×")
                    TextField("Cao", value: $model.photoExportSettings.customHeight,
                              format: .number)
                        .keyboardType(.numberPad)
                }
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            }

            Picker("Phóng ảnh", selection: $model.photoExportSettings.upscaleFactor) {
                Text("1× Gốc").tag(1)
                Text("2× Lanczos").tag(2)
                Text("4× Lanczos").tag(4)
            }
            .pickerStyle(.menu)
            .font(.caption)

            HStack {
                Text("Chất lượng JPG / HEIC")
                    .font(.caption)
                Spacer()
                Text("\(Int(model.photoExportSettings.quality * 100))%")
                    .font(.caption.monospacedDigit())
            }
            Slider(value: $model.photoExportSettings.quality,
                   in: 0.65...1.0, step: 0.05)
                .tint(.cyan)
                .disabled(model.photoExportSettings.format == .png)

            Toggle("Xóa EXIF / vị trí khi xuất",
                   isOn: $model.photoExportSettings.removeSourceMetadata)
                .font(.caption)
            Toggle("Tách người – PNG nền trong suốt",
                   isOn: $model.photoExportSettings.transparentPersonBackground)
                .font(.caption)
                .onChange(of: model.photoExportSettings.transparentPersonBackground) { enabled in
                    if enabled { model.photoExportSettings.format = .png }
                }
            Toggle("Tự lưu vào thư viện Ảnh",
                   isOn: $saveAfterExport)
                .font(.caption)

            if model.photoExportSettings.transparentPersonBackground {
                Text("Cần ảnh có người rõ ràng. Định dạng bắt buộc PNG; Vision có thể cắt chưa hoàn hảo quanh tóc.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("2K–8K là kích thước cạnh dài; ảnh luôn giữ tỷ lệ. 2×/4× dùng nội suy Lanczos, không phục hồi chi tiết AI thực. Giới hạn 64 MP, tối đa 8192 px mỗi cạnh.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                model.exportPhoto(
                    clipID: selectedPhotoID,
                    autoEdit: true,
                    saveToPhotos: saveAfterExport
                )
            } label: {
                Label("AI tự chỉnh và xuất ảnh hoàn chỉnh",
                      systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 43)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(working || selectedPhotoID == nil)

            Button {
                model.exportPhoto(
                    clipID: selectedPhotoID,
                    autoEdit: false,
                    saveToPhotos: saveAfterExport
                )
            } label: {
                Label("Xuất ảnh đang chỉnh (không tự đổi preset)",
                      systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(working || selectedPhotoID == nil)

            Divider()

            Text("Xuất ảnh hàng loạt")
                .font(.subheadline.bold())
            HStack(spacing: 7) {
                Button {
                    model.exportBatchPhotos(
                        autoEdit: false,
                        saveToPhotos: saveAfterExport
                    )
                } label: {
                    Label("Xuất \(photosCount) ảnh", systemImage: "square.stack")
                }
                .buttonStyle(.bordered)
                Button {
                    model.exportBatchPhotos(
                        autoEdit: true,
                        saveToPhotos: saveAfterExport
                    )
                } label: {
                    Label("AI chỉnh + ZIP", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption)
            .disabled(working || photosCount == 0 || photosCount > 50)

            if working { ProgressView() }
            if !model.photoExportStatus.isEmpty {
                Text(model.photoExportStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let file = model.exportedPhotoURL {
                ShareLink(item: file) {
                    Label("Chia sẻ ảnh đã xuất",
                          systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            if let archive = model.photoBatchZIPURL {
                ShareLink(item: archive) {
                    Label("Chia sẻ ZIP ảnh chất lượng cao",
                          systemImage: "archivebox")
                }
                .buttonStyle(.borderedProminent)
            }
            if !model.exportedPhotoFiles.isEmpty {
                Button {
                    model.savePhotoExportsToLibrary()
                } label: {
                    Label("Lưu \(model.exportedPhotoFiles.count) ảnh vào Ảnh",
                          systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(working)
            }
        }
        .padding(12)
        .background(Color.cyan.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: importedPhoto) { item in
            guard let item, !working else { return }
            importingPhoto = true
            Task {
                let known = Set(model.clips.map(\.id))
                await model.importSelections([item])
                let newPhoto = model.clips.first(where: {
                    !known.contains($0.id) && $0.kind == .image
                })?.id
                importedPhoto = nil
                importingPhoto = false
                if let newPhoto {
                    model.exportPhoto(
                        clipID: newPhoto,
                        autoEdit: true,
                        saveToPhotos: saveAfterExport
                    )
                }
            }
        }
    }
}
