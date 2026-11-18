import SwiftUI

extension MusicVideoStudio {
    /// Inspector controls of the selected record.
    struct VinylCustomizationView: View {
        @ObservedObject var model: MusicVideoEditorModel
        let layer: VinylLayer

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kiểu đĩa").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(VinylStyle.allCases) { style in
                            Button {
                                model.beginEdit()
                                model.vinylBinding(\.style, fallback: .classic).wrappedValue = style
                            } label: {
                                Text(style.rawValue).font(.caption2.bold())
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(layer.style == style ? Color.cyan : Color.white.opacity(0.1), in: Capsule())
                                    .foregroundStyle(layer.style == style ? Color.black : Color.white)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if layer.style == .colored || layer.style == .splatter || layer.style == .neon {
                    ColorPicker("Màu đĩa", selection: colorBinding(\.discColorHex, "#7E57C2")).font(.caption)
                }
                if layer.style == .splatter {
                    ColorPicker("Màu vẩy thứ hai", selection: colorBinding(\.accentColorHex, "#FFD54F")).font(.caption)
                }
                Toggle("Kim đĩa (hạ xuống, chạy vào trong, nhấc lên)", isOn: model.vinylBinding(\.tonearm, fallback: false)).font(.caption)
                Toggle("Bệ máy quay đĩa", isOn: model.vinylBinding(\.turntable, fallback: false)).font(.caption)
                slider("Tăng tốc lúc đầu", model.vinylBinding(\.spinUp, fallback: 0), VinylLayer.spinUpRange) { String(format: "%.1f s", $0) }
                slider("Tốc độ quay", model.vinylBinding(\.rpm, fallback: 33.33), VinylLayer.rpmRange) { String(format: "%.0f vòng/phút", $0) }
                slider("Kích thước", model.vinylBinding(\.size, fallback: 0.55), VinylLayer.sizeRange) { String(format: "%.0f%%", $0 * 100) }
                slider("Nhãn giữa", model.vinylBinding(\.labelScale, fallback: 0.38), 0.15...0.7) { String(format: "%.0f%%", $0 * 100) }
                slider("Bóng đổ", model.vinylBinding(\.shadow, fallback: 0.5), 0...1) { String(format: "%.0f%%", $0 * 100) }
                slider("Phát sáng", model.vinylBinding(\.glow, fallback: 0.3), 0...1) { String(format: "%.0f%%", $0 * 100) }
                slider("Phản chiếu", model.vinylBinding(\.reflection, fallback: 0.45), 0...1) { String(format: "%.0f%%", $0 * 100) }
                ColorPicker("Màu phát sáng", selection: colorBinding(\.glowColorHex, "#4DD0E1")).font(.caption)
                ColorPicker("Màu nhãn", selection: colorBinding(\.labelColorHex, "#C0392B")).font(.caption)
                Text("Theo nhạc").font(.caption.bold()).foregroundStyle(.secondary)
                if model.project.audios.isEmpty {
                    Text("Thêm nhạc để đĩa phồng theo nhịp và có vòng cột nhạc.").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Picker("Nhạc", selection: model.vinylBinding(\.audioLayerID, fallback: nil)) {
                        Text("Không gắn").tag(UUID?.none)
                        ForEach(model.project.audios) { Text($0.originalName).tag(Optional($0.core.id)) }
                    }.pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                    slider("Phồng theo nhịp", model.vinylBinding(\.beatPulse, fallback: 0), 0...1) { String(format: "%.0f%%", $0 * 100) }
                    Toggle("Vòng cột nhạc quanh đĩa", isOn: model.vinylBinding(\.equalizerRing, fallback: false)).font(.caption)
                    if layer.equalizerRing {
                        ColorPicker("Màu vòng cột", selection: colorBinding(\.ringColorHex, "#4DD0E1")).font(.caption)
                    }
                }
                Text("Bìa đĩa").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        coverChip(nil)
                        ForEach(model.project.photos) { photo in coverChip(photo) }
                    }
                }
                Text("Đĩa quay theo đúng thời gian của đồng hồ chủ: tạm dừng thì đứng yên, tua thì đúng góc.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }

        private func coverChip(_ photo: PhotoLayer?) -> some View {
            let selected = layer.coverFile == photo?.mediaFile
            return Button {
                model.beginEdit()
                model.vinylBinding(\.coverFile, fallback: nil).wrappedValue = photo?.mediaFile
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                    if let photo {
                        PhotoThumbnailView(url: model.mediaURL(for: photo)).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "nosign").foregroundStyle(.secondary)
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.cyan : .clear, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }

        private func colorBinding(_ keyPath: WritableKeyPath<VinylLayer, String>, _ fallback: String) -> Binding<Color> {
            let hex = model.vinylBinding(keyPath, fallback: fallback)
            return Binding(
                get: { let c = HexColor.components(hex.wrappedValue) ?? (0.5, 0.5, 0.5); return Color(red: c.r, green: c.g, blue: c.b) },
                set: { color in
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                    UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
                    model.beginEdit()
                    hex.wrappedValue = HexColor.string(r: Double(r), g: Double(g), b: Double(b))
                })
        }

        private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                            display: @escaping (Double) -> String) -> some View {
            VStack(spacing: 2) {
                HStack { Text(title); Spacer(); Text(display(value.wrappedValue)).monospacedDigit().foregroundStyle(.cyan) }.font(.caption)
                Slider(value: value, in: range, onEditingChanged: { if $0 { model.beginEdit() } }).tint(.cyan)
            }
        }
    }
}
