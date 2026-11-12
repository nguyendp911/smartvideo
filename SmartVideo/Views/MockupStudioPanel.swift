import SwiftUI

/// All controls edit persistent, independently timed mockup layers.
/// Thumbnail pixels are generated locally and match the procedural textures.
struct MockupStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @State private var category: MockupCategory = .window
    @State private var selectedID: UUID?
    @State private var showPresets = false

    private var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return model.mockupOverlays.firstIndex {
            $0.id == selectedID
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mockup Ánh sáng & Bóng đổ",
                      systemImage: "sun.max.fill")
                    .font(.headline)
                Spacer()
                Text("\(model.mockupOverlays.count)/12")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("42 mẫu bóng cửa sổ, bóng cây, ánh nắng, phản sáng và bụi sáng. Có thể chồng nhiều lớp và xuất cùng MP4.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Loại hiệu ứng", selection: $category) {
                ForEach(MockupCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 9) {
                    ForEach(MockupAssetLibrary.all.filter {
                        $0.category == category
                    }) { asset in
                        Button {
                            add(asset)
                        } label: {
                            VStack(spacing: 5) {
                                Image(uiImage:
                                    MockupOverlayRenderer.texture(for: asset))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 92, height: 68)
                                    .background(
                                        Color.gray.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 7)
                                    )
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 7)
                                    )
                                Text(asset.name)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                    .frame(width: 98, height: 27)
                                if asset.animated {
                                    Label("Chuyển động",
                                          systemImage: "waveform.path")
                                        .font(.system(size: 9))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 3)
            }

            DisclosureGroup("12 preset ánh sáng điện ảnh",
                            isExpanded: $showPresets) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 8
                ) {
                    ForEach(MockupPreset.all) { preset in
                        Button(preset.name) {
                            addPreset(preset)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 5)
            }

            if !model.mockupOverlays.isEmpty {
                Text("Các lớp trên timeline")
                    .font(.caption.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(model.mockupOverlays) { layer in
                            Button {
                                selectedID = layer.id
                                model.timelineSecond = layer.start
                            } label: {
                                VStack(spacing: 2) {
                                    Text(MockupAssetLibrary.asset(
                                        layer.assetID)?.name ?? layer.assetID)
                                        .lineLimit(1)
                                    Text(String(
                                        format: "%.1fs – %.1fs",
                                        layer.start, layer.end
                                    ))
                                    .foregroundStyle(.secondary)
                                }
                                .font(.caption2)
                                .padding(7)
                                .background(
                                    selectedID == layer.id ?
                                        Color.cyan.opacity(0.25) :
                                        Color.gray.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let idx = selectedIndex {
                Divider()
                inspector(index: idx)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func inspector(index: Int) -> some View {
        let item = model.mockupOverlays[index]
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(MockupAssetLibrary.asset(item.assetID)?.name ??
                     item.assetID)
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    var copy = model.mockupOverlays[index]
                    guard model.mockupOverlays.count < 12 else { return }
                    copy.id = UUID()
                    copy.start += 0.2
                    model.mockupOverlays.append(copy)
                    selectedID = copy.id
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(model.mockupOverlays.count >= 12)
                Button(role: .destructive) {
                    model.mockupOverlays.remove(at: index)
                    selectedID = model.mockupOverlays.first?.id
                } label: {
                    Image(systemName: "trash")
                }
            }
            Toggle("Hiển thị lớp", isOn: Binding(
                get: { !model.mockupOverlays[index].isHidden },
                set: { model.mockupOverlays[index].isHidden = !$0 }
            ))
            .font(.caption)

            metric("Bắt đầu", value: item.start, suffix: "s")
            Slider(value: $model.mockupOverlays[index].start,
                   in: 0...max(0.25, model.totalDuration),
                   step: 0.05).tint(.cyan)
            metric("Thời lượng", value: item.duration, suffix: "s")
            Slider(value: $model.mockupOverlays[index].duration,
                   in: 0.25...max(0.5, model.totalDuration),
                   step: 0.05).tint(.cyan)

            Picker("Hòa trộn", selection:
                   $model.mockupOverlays[index].blendMode) {
                ForEach(MockupBlendMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)
            Picker("Độ sâu", selection:
                   $model.mockupOverlays[index].depthMode) {
                ForEach(MockupDepthMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            metric("Cường độ", value: item.opacity * 100, suffix: "%")
            Slider(value: $model.mockupOverlays[index].opacity,
                   in: 0...1).tint(.cyan)
            metric("Phóng to", value: item.scale, suffix: "×")
            Slider(value: $model.mockupOverlays[index].scale,
                   in: 0.1...3, step: 0.05).tint(.cyan)
            metric("X", value: item.centerX, suffix: "")
            Slider(value: $model.mockupOverlays[index].centerX,
                   in: 0...1).tint(.cyan)
            metric("Y", value: item.centerY, suffix: "")
            Slider(value: $model.mockupOverlays[index].centerY,
                   in: 0...1).tint(.cyan)
            metric("Góc xoay", value: item.rotationDegrees, suffix: "°")
            Slider(value: $model.mockupOverlays[index].rotationDegrees,
                   in: -180...180, step: 1).tint(.cyan)

            HStack {
                Toggle("Lật ngang",
                       isOn: $model.mockupOverlays[index].flipHorizontal)
                Toggle("Lật dọc",
                       isOn: $model.mockupOverlays[index].flipVertical)
            }.font(.caption)

            metric("Làm mềm", value: item.blurRadius, suffix: "px")
            Slider(value: $model.mockupOverlays[index].blurRadius,
                   in: 0...36).tint(.cyan)
            metric("Feather / tan mép", value: item.feather, suffix: "")
            Slider(value: $model.mockupOverlays[index].feather,
                   in: 0...1).tint(.cyan)
            metric("Độ sáng", value: item.brightness, suffix: "")
            Slider(value: $model.mockupOverlays[index].brightness,
                   in: -0.8...0.8).tint(.cyan)
            metric("Tương phản", value: item.contrast, suffix: "×")
            Slider(value: $model.mockupOverlays[index].contrast,
                   in: 0.5...2).tint(.cyan)
            metric("Độ ấm", value: item.warmth, suffix: "")
            Slider(value: $model.mockupOverlays[index].warmth,
                   in: -0.6...0.6).tint(.cyan)

            Picker("Chuyển động",
                   selection: $model.mockupOverlays[index].animationStyle) {
                ForEach(MockupAnimationStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
            if item.animationStyle != .none {
                metric("Tốc độ", value: item.animationSpeed, suffix: "×")
                Slider(value: $model.mockupOverlays[index].animationSpeed,
                       in: 0.1...3).tint(.cyan)
                metric("Biên độ", value: item.animationAmount, suffix: "")
                Slider(value: $model.mockupOverlays[index].animationAmount,
                       in: 0...2).tint(.cyan)
                Toggle("Lặp hiệu ứng",
                       isOn: $model.mockupOverlays[index].loop)
                    .font(.caption)
            }
            Button {
                model.autoFitMockup(item.id)
            } label: {
                Label("AI tự căn / tránh khuôn mặt",
                      systemImage: "face.dashed")
            }
            .buttonStyle(.borderedProminent)
            .font(.caption)
            Text("Các mockup dùng hình procedural tích hợp, xuất thật trên ảnh/video. Chế độ Sau người chỉ tách người, không tách mọi vật thể. Render thử 720p để kiểm tra trước khi xuất.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ label: String, value: Double,
                        suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.2f", value) + suffix)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func add(_ asset: MockupAsset) {
        guard model.mockupOverlays.count < 12 else {
            model.errorText = "Tối đa 12 lớp Mockup cho mỗi dự án."
            return
        }
        let item = MockupAssetLibrary.makeClip(
            asset, at: model.timelineSecond,
            duration: max(0.5, model.totalDuration -
                          model.timelineSecond)
        )
        model.mockupOverlays.append(item)
        selectedID = item.id
    }

    private func addPreset(_ preset: MockupPreset) {
        for id in preset.ids {
            guard model.mockupOverlays.count < 12,
                  let asset = MockupAssetLibrary.asset(id) else { break }
            let item = MockupAssetLibrary.makeClip(
                asset, at: model.timelineSecond,
                duration: max(0.5, model.totalDuration -
                              model.timelineSecond)
            )
            model.mockupOverlays.append(item)
            selectedID = item.id
        }
    }
}
