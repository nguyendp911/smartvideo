import SwiftUI
import UIKit
import CoreImage
import ImageIO
import PhotosUI
import UniformTypeIdentifiers

/// A dedicated still-photo editor. Video looks remain independent.
struct PhotoPresetStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let selectedClipID: UUID?
    @Binding var compareOriginal: Bool

    @AppStorage("ViePN.PhotoPreset.Favorites") private var favorites = ""
    @AppStorage("ViePN.PhotoPreset.CustomLibrary") private var savedCustomJSON = ""
    @State private var category: PhotoPresetCategory? = nil
    @State private var favoritesOnly = false
    @State private var searchText = ""
    @State private var intensity = 0.75
    @State private var customName = ""
    @State private var suggestion: PhotoPresetSuggestion?
    @State private var suggestionStatus = ""
    @State private var isSuggesting = false
    @State private var referenceImage: PhotosPickerItem?
    @State private var referencePreset: PhotoPreset?
    @State private var referenceStatus = ""
    @State private var referenceName = "Màu từ ảnh mẫu"
    @State private var matchingReference = false
    @State private var showPhotoSelection = false
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var showImportPresets = false
    @State private var showExportPresets = false
    @State private var transferStatus = ""
    @State private var scanOnlyUngraded = true
    @State private var protectExistingLooks = true
    @State private var showSmartBatch = false
    @State private var showSplitCompare = false

    private var selectedPhoto: TimelineClip? {
        model.clips.first { $0.id == selectedClipID && $0.kind == .image }
    }
    private var savedCustom: [PhotoPreset] {
        guard let data = savedCustomJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PhotoPreset].self, from: data)) ?? []
    }
    private var allPresets: [PhotoPreset] {
        PhotoPresetLibrary.all + savedCustom
    }
    private var favoriteIDs: Set<String> {
        Set(favorites.split(separator: "|").map(String.init))
    }
    private var shown: [PhotoPreset] {
        allPresets.filter { preset in
            (category == nil || preset.category == category) &&
            (!favoritesOnly || favoriteIDs.contains(preset.id)) &&
            (searchText.isEmpty ||
             preset.name.localizedCaseInsensitiveContains(searchText) ||
             preset.category.rawValue.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Photo Preset Studio", systemImage: "camera.filters")
                .font(.headline)
            Text("Bộ màu riêng cho ảnh — \(PhotoPresetLibrary.all.count) preset dựng sẵn, preset cá nhân và xem trước bằng chính ảnh của bạn.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let photo = selectedPhoto {
                Text("Ảnh đang chọn: \(photo.filename)")
                    .font(.caption.bold())
                    .lineLimit(1)
            } else {
                Text("Chọn một ẢNH trên timeline để xem và áp dụng preset. Video không bị thay đổi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Tìm Đi biển, Hoàng hôn, Tone Hàn…", text: $searchText)
                .textFieldStyle(.roundedBorder)
            categoryStrip
            if let photo = selectedPhoto, photo.photoPreset != nil {
                DisclosureGroup("So sánh ảnh trước/sau bằng thanh kéo",
                                isExpanded: $showSplitCompare) {
                    PhotoSplitCompareView(clip: photo)
                }
                .font(.subheadline.bold())
            }
            smartBatchEditor
            referenceEditor

            HStack {
                Text("\(shown.count) / \(allPresets.count) preset")
                    .font(.caption.bold())
                Spacer()
                Toggle("Yêu thích", isOn: $favoritesOnly)
                    .font(.caption)
                    .fixedSize()
            }
            if let photo = selectedPhoto {
                Button {
                    let id = photo.id
                    let url = photo.fileURL
                    isSuggesting = true
                    suggestion = nil
                    suggestionStatus = "Vision đang nhận diện bối cảnh ảnh…"
                    Task {
                        defer { isSuggesting = false }
                        do {
                            let result = try await PhotoPresetSuggester.suggest(
                                fileURL: url)
                            guard selectedPhoto?.id == id else { return }
                            suggestion = result
                            suggestionStatus = result == nil ?
                                "Chưa đủ chắc chắn để tự gợi ý. Hãy chọn preset thủ công." :
                                "Gợi ý: \(PhotoPresetLibrary.find(result!.presetID)?.name ?? "Preset ảnh") — \(result!.reason)"
                        } catch {
                            suggestionStatus = "Không nhận diện được ảnh: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    Label(isSuggesting ? "Đang nhận diện ảnh…" :
                          "AI gợi ý preset phù hợp",
                          systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(isSuggesting)
                if isSuggesting { ProgressView() }
                if !suggestionStatus.isEmpty {
                    Text(suggestionStatus)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let suggestion,
                   let recommended = PhotoPresetLibrary.find(suggestion.presetID) {
                    Button {
                        apply(recommended, allPhotos: false)
                    } label: {
                        Label("Dùng gợi ý: \(recommended.name)",
                              systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 9) {
                ForEach(shown) { preset in
                    presetTile(preset)
                }
            }
            if shown.isEmpty {
                Text("Không có preset phù hợp. Hãy đổi bộ lọc hoặc từ khóa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            strengthControls
            batchAndClipboard
            personalPresetEditor
            if !model.photoPresetFeedback.isEmpty {
                Text(model.photoPresetFeedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Photo Preset chỉ áp dụng cho ảnh tĩnh. Ảnh gốc không thay đổi; màu của MP4 xuất dùng chính bộ xử lý Core Image trong bản xem trước.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 12))
        .onAppear { intensity = selectedPhoto?.photoPresetIntensity ?? 0.75 }
        .onChange(of: selectedClipID) { _ in
            intensity = selectedPhoto?.photoPresetIntensity ?? 0.75
            suggestion = nil
            suggestionStatus = ""
            referencePreset = nil
            referenceStatus = ""
            referenceImage = nil
        }
        .onChange(of: referenceImage) { item in
            guard let item else { return }
            analyzeReference(item)
        }
        .onChange(of: intensity) { newValue in
            guard selectedPhoto?.photoPreset != nil else { return }
            model.changePhotoPresetIntensity(
                clipID: selectedClipID, intensity: newValue)
        }
        .fileExporter(
            isPresented: $showExportPresets,
            document: PhotoPresetTransferDocument(presets: savedCustom),
            contentType: .json,
            defaultFilename: "ViePN-Photo-Presets"
        ) { result in
            switch result {
            case .success:
                transferStatus = "Đã xuất thư viện preset JSON."
            case .failure(let error):
                transferStatus = "Không xuất được preset: " +
                    error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showImportPresets,
            allowedContentTypes: [.json]
        ) { result in
            do {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                let data = try Data(contentsOf: url)
                guard data.count <= 256_000 else {
                    transferStatus = "Tệp quá lớn; giới hạn 256 KB."
                    return
                }
                let decoded = try JSONDecoder().decode(
                    [PhotoPreset].self, from: data)
                let incoming = PhotoPresetTransferDocument.sanitized(
                    decoded)
                guard !incoming.isEmpty else {
                    transferStatus = "Tệp JSON không có preset hợp lệ."
                    return
                }
                var combined = incoming + savedCustom
                combined = Array(combined.prefix(40))
                guard let output = try? JSONEncoder().encode(combined),
                      let json = String(data: output, encoding: .utf8) else {
                    transferStatus = "Không thể lưu thư viện preset nhập."
                    return
                }
                savedCustomJSON = json
                transferStatus = "Đã nhập \(incoming.count) preset; thư viện giữ tối đa 40 preset."
            } catch {
                transferStatus = "Nhập preset thất bại: " +
                    error.localizedDescription
            }
        }
    }

    private var smartBatchEditor: some View {
        DisclosureGroup("Smart Batch • AI tự chọn preset từng ảnh",
                        isExpanded: $showSmartBatch) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Vision quét ảnh ngay trên iPhone rồi gợi ý phong cách riêng cho từng ảnh. Bạn có thể đổi preset hoặc bỏ chọn trước khi áp dụng.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Chỉ quét ảnh chưa có preset",
                       isOn: $scanOnlyUngraded)
                    .font(.caption)
                Toggle("Không thay preset đang có khi áp dụng",
                       isOn: $protectExistingLooks)
                    .font(.caption)
                HStack(spacing: 8) {
                    Button {
                        model.scanPhotoPresets(
                            onlyWithoutPreset: scanOnlyUngraded)
                    } label: {
                        Label(model.isScanningPhotoPresets ?
                              "Đang quét ảnh…" : "Quét và gợi ý cho ảnh",
                              systemImage: "sparkles.rectangle.stack")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScanningPhotoPresets ||
                              !model.clips.contains(
                                  where: { $0.kind == .image }))
                    if model.isScanningPhotoPresets {
                        Button("Dừng") {
                            model.cancelPhotoPresetScan()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if model.isScanningPhotoPresets { ProgressView() }
                if !model.photoAutoPresetStatus.isEmpty {
                    Text(model.photoAutoPresetStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !model.photoAutoPresetPlan.isEmpty {
                    Text("Xem và sửa đề xuất trước khi áp dụng")
                        .font(.caption.bold())
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            ForEach(model.photoAutoPresetPlan) { proposal in
                                smartBatchRow(proposal)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    HStack {
                        Button("Chọn tất cả") {
                            for proposal in model.photoAutoPresetPlan {
                                model.setPhotoAutoPresetSelected(
                                    clipID: proposal.clipID, selected: true)
                            }
                        }
                        Button("Bỏ chọn tất cả") {
                            for proposal in model.photoAutoPresetPlan {
                                model.setPhotoAutoPresetSelected(
                                    clipID: proposal.clipID, selected: false)
                            }
                        }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    Button {
                        model.applyPhotoAutoPresetPlan(
                            intensity: intensity,
                            protectExisting: protectExistingLooks)
                        compareOriginal = false
                    } label: {
                        Label("Áp dụng preset AI cho các ảnh đã duyệt",
                              systemImage: "checkmark.square.stack")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScanningPhotoPresets ||
                        !model.photoAutoPresetPlan.contains(
                            where: { $0.isSelected }))
                }
            }
            .padding(.vertical, 6)
        }
        .font(.subheadline.bold())
        .padding(10)
        .background(Color.cyan.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func smartBatchRow(_ proposal: PhotoAutoPresetProposal)
        -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: Binding(
                get: {
                    model.photoAutoPresetPlan.first {
                        $0.clipID == proposal.clipID
                    }?.isSelected ?? false
                },
                set: {
                    model.setPhotoAutoPresetSelected(
                        clipID: proposal.clipID, selected: $0)
                }
            )) {
                Text(proposal.filename)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            Text(proposal.reason)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("Đổi preset", selection: Binding(
                get: {
                    model.photoAutoPresetPlan.first {
                        $0.clipID == proposal.clipID
                    }?.presetID ?? proposal.presetID
                },
                set: {
                    model.setPhotoAutoPreset(
                        clipID: proposal.clipID, presetID: $0)
                }
            )) {
                ForEach(PhotoPresetLibrary.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private var referenceEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Match Color • Học màu từ ảnh mẫu",
                  systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.bold())
            Text("Chọn một ảnh có tone màu đẹp. Ứng dụng đo độ sáng, độ tương phản, độ bão hòa và sắc ấm/lạnh ngay trên iPhone để tạo công thức tương tự cho ảnh đang chỉnh.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $referenceImage, matching: .images) {
                Label("Chọn ảnh mẫu từ thư viện",
                      systemImage: "photo.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(selectedPhoto == nil || matchingReference)
            if matchingReference { ProgressView() }
            if !referenceStatus.isEmpty {
                Text(referenceStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let recipe = referencePreset {
                TextField("Đặt tên preset từ ảnh mẫu", text: $referenceName)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 7) {
                    Button {
                        apply(recipe, allPhotos: false)
                    } label: {
                        Label("Áp dụng màu mẫu", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        var stored = recipe
                        stored.id = "custom-" + UUID().uuidString
                        stored.name = String(referenceName.trimmingCharacters(
                            in: .whitespacesAndNewlines).prefix(42))
                        guard !stored.name.isEmpty else {
                            referenceStatus = "Hãy đặt tên cho preset ảnh mẫu."
                            return
                        }
                        if storePersonalPreset(stored) {
                            referenceStatus = "Đã lưu công thức vào Preset cá nhân."
                        } else {
                            referenceStatus = "Không lưu được preset ảnh mẫu."
                        }
                    } label: {
                        Label("Lưu preset", systemImage: "bookmark")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption2)
                Text("Match Color là phép ghép màu dựa trên thống kê, không sao chép cảnh vật, da người hay ánh sáng từng vùng. Kết quả cần chỉnh lại nếu ảnh gốc và ảnh mẫu rất khác nhau.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(Color.cyan.opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func analyzeReference(_ item: PhotosPickerItem) {
        guard let photo = selectedPhoto else {
            referenceStatus = "Hãy chọn ảnh trong timeline."
            return
        }
        let photoID = photo.id
        referencePreset = nil
        matchingReference = true
        referenceStatus = "Đang học công thức màu từ ảnh mẫu…"
        Task {
            defer { matchingReference = false }
            do {
                guard let data = try await item.loadTransferable(
                    type: Data.self) else {
                    referenceStatus = "Không đọc được ảnh mẫu."
                    return
                }
                let result = try await PhotoReferenceMatcher.createPreset(
                    fromReferenceData: data,
                    forSourceURL: photo.fileURL,
                    name: referenceName
                )
                guard selectedPhoto?.id == photoID else {
                    referenceStatus = "Ảnh đang chỉnh đã đổi. Chọn lại ảnh mẫu."
                    return
                }
                referencePreset = result
                referenceStatus = "Đã phân tích màu. Nhấn Áp dụng màu mẫu để xem trước."
            } catch {
                referenceStatus = "Lỗi đọc ảnh mẫu: " +
                    error.localizedDescription
            }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button("Tất cả") { category = nil }
                    .tint(category == nil ? .cyan : .gray)
                ForEach(PhotoPresetCategory.allCases) { item in
                    Button {
                        category = item
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                    }
                    .tint(category == item ? .cyan : .gray)
                }
            }
            .buttonStyle(.bordered)
            .font(.caption)
        }
    }

    private func presetTile(_ preset: PhotoPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                apply(preset, allPhotos: false)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    if let fileURL = selectedPhoto?.fileURL {
                        PhotoPresetThumbnail(
                            fileURL: fileURL, preset: preset)
                            .frame(height: 94)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.cyan.opacity(0.12))
                            .frame(height: 94)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                    HStack(spacing: 4) {
                        Text(preset.name)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer(minLength: 1)
                        if selectedPhoto?.photoPreset?.id == preset.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            HStack {
                Text(preset.category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    toggleFavorite(preset.id)
                } label: {
                    Image(systemName:
                          favoriteIDs.contains(preset.id) ?
                          "heart.fill" : "heart")
                        .foregroundStyle(favoriteIDs.contains(preset.id) ?
                                         .pink : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Yêu thích \(preset.name)")
            }
        }
        .padding(7)
        .background(
            selectedPhoto?.photoPreset?.id == preset.id ?
                Color.cyan.opacity(0.12) : Color.secondary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var strengthControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cường độ preset")
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(intensity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }
            Slider(value: $intensity, in: 0...1, step: 0.05,
                   onEditingChanged: { editing in
                if editing && selectedPhoto?.photoPreset != nil {
                    model.beginPhotoPresetAdjustment()
                }
            })
            .tint(.cyan)
            Toggle("So sánh ảnh gốc / sau preset",
                   isOn: $compareOriginal)
                .font(.caption)
            if selectedPhoto?.photoPreset != nil {
                Button(role: .destructive) {
                    model.clearPhotoPreset(clipID: selectedClipID)
                    compareOriginal = false
                } label: {
                    Label("Gỡ preset khỏi ảnh này",
                          systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var batchAndClipboard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sao chép và áp dụng hàng loạt")
                .font(.caption.bold())
            HStack(spacing: 7) {
                Button {
                    model.copyPhotoPreset(clipID: selectedClipID)
                } label: {
                    Label("Sao chép", systemImage: "doc.on.doc")
                }
                .disabled(selectedPhoto?.photoPreset == nil)
                Button {
                    model.pastePhotoPreset(clipID: selectedClipID)
                    intensity = selectedPhoto?.photoPresetIntensity ?? intensity
                    compareOriginal = false
                } label: {
                    Label("Dán preset", systemImage: "doc.on.clipboard")
                }
                .disabled(selectedPhoto == nil || !model.hasCopiedPhotoPreset)
            }
            .buttonStyle(.bordered)
            .font(.caption)

            if let applied = selectedPhoto?.photoPreset {
                Button {
                    apply(applied, allPhotos: true)
                } label: {
                    Label("Áp dụng cho toàn bộ ảnh trong dự án",
                          systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.clips.contains(where: { $0.kind == .image }))
            }

            DisclosureGroup("Áp dụng cho các ảnh được chọn",
                            isExpanded: $showPhotoSelection) {
                let photos = model.clips.filter { $0.kind == .image }
                let allIDs = Set(photos.map { $0.id })
                let selectedCount = selectedPhotoIDs.intersection(allIDs).count
                HStack {
                    Text("\(selectedCount) / \(photos.count) ảnh")
                        .font(.caption2)
                    Spacer()
                    Button("Chọn hết") {
                        selectedPhotoIDs = allIDs
                    }
                    Button("Bỏ chọn") { selectedPhotoIDs = [] }
                }
                .font(.caption2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(photos) { photo in
                            Toggle(isOn: Binding(
                                get: { selectedPhotoIDs.contains(photo.id) },
                                set: { selected in
                                    if selected {
                                        selectedPhotoIDs.insert(photo.id)
                                    } else {
                                        selectedPhotoIDs.remove(photo.id)
                                    }
                                }
                            )) {
                                Text(photo.filename)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 195)
                if let chosen = selectedPhoto?.photoPreset {
                    Button {
                        model.applyPhotoPresetToSelection(
                            chosen, ids: selectedPhotoIDs,
                            intensity: intensity
                        )
                    } label: {
                        Label("Áp dụng cho ảnh đã chọn",
                              systemImage: "checkmark.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedPhotoIDs.isEmpty)
                } else {
                    Text("Áp dụng một preset lên ảnh hiện tại trước khi dùng hàng loạt.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.bold())
        }
    }

    private var personalPresetEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preset cá nhân")
                .font(.caption.bold())
            TextField("Đặt tên preset riêng…", text: $customName)
                .textFieldStyle(.roundedBorder)
            Button {
                savePersonalPreset()
            } label: {
                Label("Lưu công thức ảnh đang chọn",
                      systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
            .disabled(selectedPhoto == nil ||
                      customName.trimmingCharacters(
                        in: .whitespacesAndNewlines).isEmpty)
            HStack(spacing: 8) {
                Button {
                    showImportPresets = true
                } label: {
                    Label("Nhập JSON", systemImage: "square.and.arrow.down")
                }
                Button {
                    showExportPresets = true
                } label: {
                    Label("Xuất JSON", systemImage: "square.and.arrow.up")
                }
                .disabled(savedCustom.isEmpty)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            if !transferStatus.isEmpty {
                Text(transferStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !savedCustom.isEmpty {
                ForEach(savedCustom) { preset in
                    HStack {
                        Text(preset.name).font(.caption)
                        Spacer()
                        Button("Áp dụng") {
                            apply(preset, allPhotos: false)
                        }
                        .disabled(selectedPhoto == nil)
                        Button(role: .destructive) {
                            removeCustom(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                }
            }
        }
    }

    private func apply(_ preset: PhotoPreset, allPhotos: Bool) {
        compareOriginal = false
        model.applyPhotoPreset(
            preset, to: selectedClipID,
            intensity: intensity, allPhotos: allPhotos
        )
    }
    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if !ids.insert(id).inserted { ids.remove(id) }
        favorites = ids.sorted().joined(separator: "|")
    }
    private func savePersonalPreset() {
        guard let clip = selectedPhoto else { return }
        var custom = clip.photoPreset ??
            PhotoPresetLibrary.snapshot(name: customName, from: clip)
        custom.id = "custom-" + UUID().uuidString
        custom.name = String(customName.trimmingCharacters(
            in: .whitespacesAndNewlines).prefix(42))
        custom.category = .lifestyle
        if storePersonalPreset(custom) {
            customName = ""
        }
    }

    @discardableResult
    private func storePersonalPreset(_ preset: PhotoPreset) -> Bool {
        var list = savedCustom
        list.insert(preset, at: 0)
        list = Array(list.prefix(40))
        guard let bytes = try? JSONEncoder().encode(list),
              let json = String(data: bytes, encoding: .utf8) else {
            return false
        }
        savedCustomJSON = json
        return true
    }

    private func removeCustom(_ id: String) {
        let remaining = savedCustom.filter { $0.id != id }
        if let bytes = try? JSONEncoder().encode(remaining),
           let json = String(data: bytes, encoding: .utf8) {
            savedCustomJSON = json
        }
        var ids = favoriteIDs
        ids.remove(id)
        favorites = ids.sorted().joined(separator: "|")
    }
}

/// Thumbnail uses the SAME recipe as final MP4 export. Source decoding
/// is downsampled, keeping memory use low even for large original photos.
private struct PhotoPresetThumbnail: View {
    let fileURL: URL
    let preset: PhotoPreset
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.08))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .task(id: fileURL.path + "|" + preset.id) {
            thumbnail = nil
            let url = fileURL
            let recipe = preset
            let result = await Task.detached(priority: .utility) {
                Self.render(url: url, preset: recipe)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = result
        }
    }

    private static func render(url: URL, preset: PhotoPreset) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let frame = CGImageSourceCreateThumbnailAtIndex(
                source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 300,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary) else { return nil }
        let input = CIImage(cgImage: frame)
        let result = PhotoPresetProcessor.apply(
            input, preset: preset, intensity: 0.8)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(
            result, from: result.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
