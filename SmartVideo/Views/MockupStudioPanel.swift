import SwiftUI

/// Complete on-device light/shadow studio; every control modifies the
/// actual non-destructive layers consumed by MockupFrameRenderer on export.
struct MockupStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    let onScrub: (Double) -> Void
    let onAutoFit: (UUID) -> Void
    let onImport: () -> Void

    @State private var category: MockupCategory = .windows
    @State private var showPresets = true

    private let tiles = [
        GridItem(.flexible(), spacing: 7),
        GridItem(.flexible(), spacing: 7)
    ]

    private var selected: MockupOverlayClip? {
        model.mockupOverlays.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Mockup Ánh sáng & Bóng", systemImage: "sun.horizon.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(model.mockupOverlays.count)/12 lớp")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.cyan)
            }

            Text("42 bóng cửa, bóng lá, nắng, vệt đèn, kính và bụi sáng. Không cần tải asset; chồng nhiều lớp lên ảnh/video, giữ nguyên file gốc.")
                .font(.caption2).foregroundStyle(.secondary)

            DisclosureGroup(
                "12 phong cách 1 chạm",
                isExpanded: $showPresets
            ) {
                LazyVGrid(columns: tiles, spacing: 7) {
                    ForEach(MockupMoodPreset.all) { preset in
                        Button {
                            selectedID = model.applyMockupMood(preset)
                            if let id = selectedID,
                               let item = model.mockupOverlays.first(
                                where: { $0.id == id }
                               ) {
                                onScrub(item.start)
                            }
                        } label: {
                            Label(preset.name,
                                  systemImage: "sparkles.rectangle.stack")
                                .font(.caption2)
                                .frame(maxWidth: .infinity,
                                       minHeight: 33)
                                .lineLimit(2)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MockupCategory.allCases) { item in
                        Button(item.rawValue) {
                            category = item
                        }
                        .buttonStyle(.bordered)
                        .tint(category == item ? .orange : .gray)
                        .font(.caption)
                    }
                }
            }

            LazyVGrid(columns: tiles, spacing: 8) {
                ForEach(MockupAssetLibrary.all.filter {
                    $0.category == category
                }) { def in
                    Button {
                        selectedID = model.addMockup(def)
                        if let selectedID,
                           let item = model.mockupOverlays.first(
                            where: { $0.id == selectedID }
                           ) {
                            onScrub(item.start)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack {
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.75, green: 0.66, blue: 0.55),
                                        Color(red: 0.25, green: 0.35, blue: 0.45)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                if let image = MockupProceduralTexture.artwork(
                                    id: def.id, preview: true
                                ) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .blendMode(blend(def.blend))
                                }
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .shadow(radius: 3)
                                    .frame(maxWidth: .infinity,
                                           maxHeight: .infinity,
                                           alignment: .topTrailing)
                                    .padding(5)
                            }
                            .frame(height: 86)
                            .clipped()
                            .clipShape(
                                RoundedRectangle(cornerRadius: 8)
                            )
                            Text(def.name).font(.caption2.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !model.mockupOverlays.isEmpty {
                Divider()
                Text("Các lớp đang dùng")
                    .font(.caption.bold())
                ForEach(model.mockupOverlays) { item in
                    HStack(spacing: 6) {
                        Button {
                            selectedID = item.id
                            onScrub(item.start)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName:
                                      item.depthMode == .behindPerson ?
                                      "person.crop.rectangle.stack" :
                                      "sun.max")
                                Text(item.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if item.muted {
                                    Image(systemName: "eye.slash")
                                }
                                if item.id == selectedID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.cyan)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(
                                item.id == selectedID ?
                                Color.cyan.opacity(0.16) :
                                Color.white.opacity(0.065),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                        Button {
                            selectedID = model.duplicateMockup(item.id)
                        } label: {
                            Image(systemName: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            model.removeMockup(item.id)
                            selectedID = model.mockupOverlays.first?.id
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            if let item = selected,
               let index = model.mockupOverlays.firstIndex(
                   where: { $0.id == item.id }
               ) {
                Divider()
                HStack {
                    Text("Chỉnh lớp: \(item.name)")
                        .font(.caption.bold())
                    Spacer()
                    Button {
                        onAutoFit(item.id)
                    } label: {
                        Label("AI Tự căn", systemImage: "face.dashed")
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption2)
                }
                Button {
                    onImport()
                } label: {
                    Label("Thay bằng ảnh PNG/JPEG tự chọn",
                          systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if item.assetURL != nil {
                    Button("Trở về họa tiết mặc định") {
                        model.mockupOverlays[index].assetURL = nil
                        model.mockupOverlays[index].name =
                            MockupAssetLibrary.find(item.effectID)?.name ??
                            "Mockup"
                    }
                    .font(.caption2)
                }

                Picker("Độ sâu",
                       selection: $model.mockupOverlays[index].depthMode) {
                    ForEach(MockupDepthMode.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Hòa trộn",
                       selection: $model.mockupOverlays[index].blendMode) {
                    ForEach(MockupBlendMode.allCases) { b in
                        Text(b.rawValue).tag(b)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Tránh che mặt bằng Vision",
                       isOn: $model.mockupOverlays[index].avoidFace)
                    .font(.caption)
                Toggle("Ẩn lớp trong video",
                       isOn: $model.mockupOverlays[index].muted)
                    .font(.caption)
                Toggle("Khóa lớp",
                       isOn: $model.mockupOverlays[index].locked)
                    .font(.caption)

                if item.depthMode == .behindPerson {
                    Text("Bóng nằm dưới người thật khi xuất video. Xem thử 720p để thấy chính xác lớp người được Vision tách. Preview nhanh chỉ hiển thị vị trí overlay.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                control("Độ đậm", item.opacity, 0...1, step: 0.02,
                        binding: $model.mockupOverlays[index].opacity)
                control("Phóng to", item.scale, 0.25...5, step: 0.05,
                        binding: $model.mockupOverlays[index].scale)
                control("X", item.centerX, -0.5...1.5, step: 0.01,
                        binding: $model.mockupOverlays[index].centerX)
                control("Y", item.centerY, -0.5...1.5, step: 0.01,
                        binding: $model.mockupOverlays[index].centerY)
                control("Xoay", item.rotationDegrees, -180...180,
                        step: 1,
                        binding: $model.mockupOverlays[index].rotationDegrees)
                HStack {
                    Toggle("Lật ngang",
                           isOn: $model.mockupOverlays[index].flipHorizontal)
                    Toggle("Lật dọc",
                           isOn: $model.mockupOverlays[index].flipVertical)
                }
                .font(.caption2)
                control("Mờ mềm", item.blurRadius, 0...35, step: 1,
                        binding: $model.mockupOverlays[index].blurRadius)
                control("Feather", item.feather, 0...30, step: 1,
                        binding: $model.mockupOverlays[index].feather)
                control("Độ sáng", item.brightness, -1...1, step: 0.05,
                        binding: $model.mockupOverlays[index].brightness)
                control("Tương phản", item.contrast, 0...2, step: 0.05,
                        binding: $model.mockupOverlays[index].contrast)
                control("Ấm/lạnh", item.warmth, -1...1, step: 0.05,
                        binding: $model.mockupOverlays[index].warmth)
                control("Tint", item.tint, -1...1, step: 0.05,
                        binding: $model.mockupOverlays[index].tint)

                Picker("Chuyển động",
                       selection: $model.mockupOverlays[index].animationStyle) {
                    ForEach(MockupAnimationStyle.allCases) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                .pickerStyle(.menu)
                control("Tốc độ", item.animationSpeed, 0.1...4,
                        step: 0.1,
                        binding: $model.mockupOverlays[index].animationSpeed)
                control("Biên độ", item.animationAmount, 0...2,
                        step: 0.05,
                        binding: $model.mockupOverlays[index].animationAmount)
                Toggle("Lặp chuyển động",
                       isOn: $model.mockupOverlays[index].loopEnabled)
                    .font(.caption)

                Text("Vị trí trên timeline")
                    .font(.caption.bold())
                control("Bắt đầu", item.start,
                        0...max(0.01, model.totalDuration - 0.1),
                        step: 0.1,
                        binding: $model.mockupOverlays[index].start)
                control("Thời lượng", item.duration,
                        0.1...max(0.11, model.totalDuration),
                        step: 0.1,
                        binding: $model.mockupOverlays[index].duration)
                Button("Đưa con trỏ đến lớp Mockup") {
                    onScrub(item.start)
                }.font(.caption).buttonStyle(.bordered)
            }
            Text("Nhập ảnh PNG trong suốt hoặc chọn mockup mặc định. Ảnh và video xuất sẽ sử dụng cùng lõi Core Image; chuyển động mượt hơn ở MP4. Có thể áp dụng nhiều mockup và 9 chế độ hòa trộn.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }

    private func control(
        _ name: String, _ value: Double,
        _ range: ClosedRange<Double>, step: Double,
        binding: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                Spacer()
                Text(String(format: "%.2f", value))
                    .monospacedDigit()
                    .foregroundStyle(.cyan)
            }
            .font(.caption2)
            Slider(value: binding, in: range, step: step)
                .tint(.orange)
        }
    }

    private func blend(_ mode: MockupBlendMode) -> BlendMode {
        switch mode {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .add: return .plusLighter
        case .darken: return .darken
        case .lighten: return .lighten
        }
    }
}
