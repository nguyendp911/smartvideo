import SwiftUI

/// Compact professional preset catalog with searchable collections, favorites,
/// real editing recipes, and optional editable title templates.
struct PresetStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    let onEditTitle: (UUID) -> Void

    @AppStorage("ViePN.PresetStudio.Favorites")
    private var favoriteStorage = ""
    @State private var searchText = ""
    @State private var category: StudioPresetCategory?
    @State private var favoritesOnly = false
    @State private var selectedID: String?

    private let columns = [
        GridItem(.flexible(), spacing: 9),
        GridItem(.flexible(), spacing: 9)
    ]

    private var favoriteIDs: Set<String> {
        Set(favoriteStorage.split(separator: "|").map(String.init))
    }

    private var visiblePresets: [StudioPreset] {
        StudioPreset.all.filter { preset in
            (category == nil || preset.category == category) &&
            (!favoritesOnly || favoriteIDs.contains(preset.id)) &&
            (searchText.isEmpty ||
             preset.title.localizedCaseInsensitiveContains(searchText) ||
             preset.subtitle.localizedCaseInsensitiveContains(searchText) ||
             preset.category.rawValue.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var current: StudioPreset? {
        let id = selectedID ?? model.appliedStudioPresetID
        return StudioPreset.find(id) ?? visiblePresets.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            titleBar

            Text("24 công thức phối VFX, màu ảnh, chuyển cảnh và chuyển động. Tự tạo, không cần tải asset bên ngoài.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("Tìm theo phong cách hoặc cảm xúc…",
                      text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            categoryFilter

            HStack {
                Text("\(visiblePresets.count) / 24 preset")
                    .font(.caption.bold())
                Spacer()
                Toggle("Yêu thích", isOn: $favoritesOnly)
                    .font(.caption)
                    .fixedSize()
                    .tint(.cyan)
            }

            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(visiblePresets) { preset in
                    presetTile(preset)
                }
            }

            if visiblePresets.isEmpty {
                Text("Không có preset phù hợp. Hãy đổi từ khóa hoặc bộ lọc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 14)
            }

            if let preset = current {
                detailPanel(preset)
            }

            Text("Màu Core Image áp dụng trực tiếp lên clip ẢNH. Với clip VIDEO, preset dùng hiệu ứng VFX, chuyển cảnh và lớp chữ hiện có; chưa phải LUT màu video. Ảnh màu trong thẻ chỉ minh họa bảng màu, muốn kiểm tra chính xác hãy render preview 720p.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private var titleBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "wand.and.stars.inverse")
                .font(.title2)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("ViePN Preset Studio")
                    .font(.headline)
                Text("PRO COLLECTION · 24 LOOKS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("V3.9")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.cyan)
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                filterButton("Tất cả", icon: "square.grid.2x2",
                             isSelected: category == nil) {
                    category = nil
                }
                ForEach(StudioPresetCategory.allCases) { group in
                    filterButton(group.rawValue, icon: group.symbol,
                                 isSelected: category == group) {
                        category = group
                    }
                }
            }
        }
    }

    private func filterButton(
        _ text: String, icon: String, isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(text, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.black : Color.primary)
                .background(isSelected ? Color.cyan : Color.white.opacity(0.08),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func presetTile(_ preset: StudioPreset) -> some View {
        let chosen = selectedID == preset.id ||
            (selectedID == nil && model.appliedStudioPresetID == preset.id)
        let applied = model.appliedStudioPresetID == preset.id
        let colors = preset.category.colors

        return VStack(alignment: .leading, spacing: 5) {
            Button {
                selectedID = preset.id
            } label: {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(LinearGradient(
                            colors: colors.map { Color(
                                uiColor: TextOverlayRenderer.uiColor(hex: $0)
                            ) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Circle()
                        .fill(Color.white.opacity(0.13))
                        .frame(width: 95, height: 95)
                        .blur(radius: 8)
                        .offset(x: 55, y: -25)
                    Image(systemName: preset.category.symbol)
                        .font(.system(size: 30, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .center)
                    HStack(spacing: 4) {
                        Text(preset.imageLook.rawValue)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        if applied {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(7)
                }
                .frame(height: 96)
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(chosen ? .cyan : .white.opacity(0.15),
                                lineWidth: chosen ? 1.8 : 0.7)
                }
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 3) {
                Button {
                    selectedID = preset.id
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.title)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(preset.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(height: 25, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button {
                    toggleFavorite(preset.id)
                } label: {
                    Image(systemName: favoriteIDs.contains(preset.id) ?
                          "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundStyle(favoriteIDs.contains(preset.id) ?
                                         .pink : .secondary)
                        .frame(width: 27, height: 27)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đánh dấu yêu thích")
            }
        }
        .padding(7)
        .background(
            chosen ? Color.cyan.opacity(0.09) :
                Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func detailPanel(_ preset: StudioPreset) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            HStack {
                Text(preset.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(preset.category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }

            Text(preset.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 9) {
                Label("Màu: \(preset.imageLook.rawValue)",
                      systemImage: "camera.filters")
                Spacer()
                Label(preset.transition.rawValue, systemImage: "rectangle.split.2x1")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(preset.effects.isEmpty ?
                 "VFX: không dùng · tập trung bố cục sạch" :
                 "VFX: " + preset.effects.map(\.rawValue)
                    .joined(separator: " • "))
                .font(.caption2)

            HStack(spacing: 8) {
                Button {
                    model.applyStudioPreset(preset)
                } label: {
                    Label(model.appliedStudioPresetID == preset.id ?
                          "Áp dụng lại" : "Áp dụng toàn dự án",
                          systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.clips.isEmpty)

                Button {
                    if let id = model.addStudioPresetTitle(preset) {
                        onEditTitle(id)
                    }
                } label: {
                    Label("+ Tiêu đề", systemImage: "textformat")
                }
                .buttonStyle(.bordered)
                .disabled(model.clips.isEmpty)
            }
            .font(.caption)

            if let applied = StudioPreset.find(model.appliedStudioPresetID) {
                HStack {
                    Text("Đang dùng: \(applied.title)")
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan)
                    Spacer()
                    Button {
                        model.undoStudioPreset()
                    } label: {
                        Label("Hoàn tác", systemImage: "arrow.uturn.backward")
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .disabled(!model.canUndoStudioPreset)
                }
            }

            if model.appliedStudioPresetID == preset.id &&
               !model.vfxPresets.isEmpty {
                HStack {
                    Text("Cường độ VFX")
                    Spacer()
                    Text("\(Int(model.vfxIntensity * 100))%")
                        .monospacedDigit()
                }
                .font(.caption)
                Slider(value: $model.vfxIntensity,
                       in: 0.05...0.75, step: 0.05)
                    .tint(.cyan)
            }

            Button {
                model.renderSynchronizedPreview()
            } label: {
                Label(model.isRenderingPreview ?
                      "Đang dựng bản nháp…" : "Xem thử MP4 · 720p",
                      systemImage: "play.rectangle")
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .disabled(model.clips.isEmpty ||
                      model.isRenderingPreview || model.isExporting)

            if !model.studioPresetMessage.isEmpty {
                Text(model.studioPresetMessage)
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggleFavorite(_ id: String) {
        var selected = favoriteIDs
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
        favoriteStorage = selected.sorted().joined(separator: "|")
    }
}
