import SwiftUI

/// Compact grid for a 6.7-inch iPhone screen. Settings are non-destructive:
/// tapping presets only updates render parameters; originals are untouched.
struct VFXLibraryPanel: View {
    @ObservedObject var model: EditorViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Thư viện VFX", systemImage: "sparkles.tv")
                    .font(.subheadline.bold())
                Spacer()
                if !model.vfxPresets.isEmpty {
                    Button("Xóa tất cả") {
                        model.vfxPresets = []
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Text("Chọn nhiều hiệu ứng để phối hợp. Hình xem trước là bản mô phỏng tĩnh; chuyển động được tạo trong video khi xuất.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(VFXPreset.allCases) { preset in
                    presetTile(preset)
                }
            }

            HStack {
                Text("Cường độ VFX")
                    .font(.caption.bold())
                Spacer()
                Text("\(Int(model.vfxIntensity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }

            Slider(value: $model.vfxIntensity, in: 0.10...1.0, step: 0.05)
                .tint(.cyan)
                .disabled(model.vfxPresets.isEmpty)

            HStack(spacing: 7) {
                presetButton("Phim điện ảnh", effects: [.grain, .vignette, .cinemaBars])
                presetButton("Mộng mơ", effects: [.dust, .lightLeak])
            }
            Text("Ưu tiên 1–3 hiệu ứng cùng lúc khi render 1080p trên iPhone 12 Pro Max. Đối với video dài, hạ xuống 720p nếu máy nóng.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !model.vfxPresets.isEmpty {
                Text("Đang bật \(model.vfxPresets.count) hiệu ứng: " +
                     VFXPreset.allCases.filter { model.vfxPresets.contains($0) }
                        .map(\.rawValue).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.cyan)
            }
        }
        .padding(10)
    }

    private func presetTile(_ preset: VFXPreset) -> some View {
        let selected = model.vfxPresets.contains(preset)
        return Button {
            var next = model.vfxPresets
            if selected {
                next.remove(preset)
            } else {
                next.insert(preset)
            }
            model.vfxPresets = next
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(uiColor: preset.tint).opacity(0.62),
                                    Color(red: 0.09, green: 0.11, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: preset.symbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(.cyan)
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: .topTrailing)
                            .padding(5)
                    }
                }
                .frame(height: 66)

                Text(preset.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text(preset.description)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .background(
                selected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.cyan : Color.white.opacity(0.1),
                            lineWidth: selected ? 1.4 : 0.6)
            }
        }
        .buttonStyle(.plain)
    }

    private func presetButton(_ title: String, effects: Set<VFXPreset>) -> some View {
        Button(title) {
            model.vfxPresets = effects
            model.vfxIntensity = 0.55
        }
        .font(.caption)
        .buttonStyle(.bordered)
    }
}

/// Lightweight preview hint. Moving VFX (particles/light) are exported
/// with Core Animation; this overlay is intentionally an approximation.
struct VFXPreviewOverlay: View {
    let presets: Set<VFXPreset>
    let intensity: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let strength = min(1, max(0, intensity))

            ZStack {
                if presets.contains(.vignette) {
                    RadialGradient(
                        colors: [
                            .clear,
                            Color.black.opacity(0.1 * strength),
                            Color.black.opacity(0.68 * strength)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.72
                    )
                }

                if presets.contains(.lightLeak) {
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.44 * strength),
                            Color.pink.opacity(0.20 * strength),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                if presets.contains(.flash) {
                    Color.white.opacity(0.08 * strength)
                }

                if presets.contains(.grain) {
                    ForEach(0..<70, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ?
                                  Color.white.opacity(0.22 * strength) :
                                  Color.black.opacity(0.20 * strength))
                            .frame(width: 1.5, height: 1.5)
                            .position(
                                x: width * CGFloat((index * 37 + 17) % 101) / 101,
                                y: height * CGFloat((index * 73 + 11) % 103) / 103
                            )
                    }
                }

                if presets.contains(.snow) {
                    ForEach(0..<22, id: \.self) { index in
                        Circle()
                            .fill(.white.opacity(0.65 * strength))
                            .frame(width: 2.5 + CGFloat(index % 3), height: 2.5 + CGFloat(index % 3))
                            .position(
                                x: width * CGFloat((index * 23 + 7) % 99) / 99,
                                y: height * CGFloat((index * 41 + 3) % 97) / 97
                            )
                    }
                }

                if presets.contains(.rain) {
                    ForEach(0..<25, id: \.self) { index in
                        Capsule()
                            .fill(Color.cyan.opacity(0.42 * strength))
                            .frame(width: 1.2, height: 9)
                            .rotationEffect(.degrees(-15))
                            .position(
                                x: width * CGFloat((index * 19 + 7) % 97) / 97,
                                y: height * CGFloat((index * 47 + 3) % 101) / 101
                            )
                    }
                }

                if presets.contains(.sparks) {
                    ForEach(0..<15, id: \.self) { index in
                        Circle()
                            .fill(Color.yellow.opacity(0.8 * strength))
                            .frame(width: 2.5 + CGFloat(index % 3), height: 2.5 + CGFloat(index % 3))
                            .shadow(color: .orange.opacity(0.9), radius: 4)
                            .position(
                                x: width * CGFloat((index * 43 + 7) % 97) / 97,
                                y: height * CGFloat((index * 31 + 3) % 101) / 101
                            )
                    }
                }

                if presets.contains(.dust) {
                    ForEach(0..<20, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(0.25 * strength))
                            .frame(width: 3.5, height: 3.5)
                            .position(
                                x: width * CGFloat((index * 37 + 9) % 99) / 99,
                                y: height * CGFloat((index * 23 + 5) % 97) / 97
                            )
                    }
                }

                if presets.contains(.cinemaBars) {
                    VStack(spacing: 0) {
                        Color.black.frame(height: height * 0.08)
                        Spacer(minLength: 0)
                        Color.black.frame(height: height * 0.08)
                    }
                }
            }
            .frame(width: width, height: height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
