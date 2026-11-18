import SwiftUI

/// Properties of the selected layer. Every control writes straight into the
/// layer, so the canvas, undo history, saved project and export all agree.
/// What each control means depends on the layer kind (overlay / frame / background).
struct MockupPropertiesView: View {
    @ObservedObject var session: MockupStudioSession
    @ObservedObject var model: EditorViewModel

    var body: some View {
        if let layer = session.selectedLayer {
            content(layer)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("THUỘC TÍNH").font(.caption2.bold()).foregroundStyle(.secondary)
                Text("Chọn một lớp (chạm trên canvas hoặc trong danh sách lớp) để chỉnh độ mờ, tỉ lệ, góc xoay, vị trí, chế độ hòa trộn, mask…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ layer: MockupOverlayClip) -> some View {
        let id = layer.id
        let kind = session.kindOf(layer)
        let locked = layer.locked
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(MockupOverlayRenderer.displayName(for: layer.assetID)).font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Button { session.resetSelected() } label: { Label("Đặt lại", systemImage: "arrow.counterclockwise") }
                    .font(.caption).buttonStyle(.bordered)
            }
            if locked {
                Label("Lớp đang khóa — mở khóa để chỉnh.", systemImage: "lock.fill").font(.caption).foregroundStyle(.orange)
            }

            group("Cơ bản") {
                slider("Độ mờ đục (Opacity)", session.binding(id, \.opacity, fallback: 1), 0...1) { "\(Int($0 * 100))%" }
                if kind == .overlay {
                    blendPicker(id, current: layer.blendMode)
                }
            }

            group(kind == .overlay ? "Biến đổi" : kind == .scene ? "Ảnh trong khung" : "Thẻ ảnh") {
                switch kind {
                case .overlay:
                    slider("Tỉ lệ (Scale)", session.binding(id, \.scale, fallback: 1), 0.1...3) { String(format: "%.2f×", $0) }
                    slider("Góc xoay (Rotation)", session.binding(id, \.rotationDegrees, fallback: 0), -180...180) { "\(Int($0))°" }
                    slider("Vị trí X", session.binding(id, \.centerX, fallback: 0.5), -0.2...1.2) { String(format: "%.2f", $0) }
                    slider("Vị trí Y", session.binding(id, \.centerY, fallback: 0.5), -0.2...1.2) { String(format: "%.2f", $0) }
                case .scene:
                    slider("Thu phóng ảnh", session.binding(id, \.scale, fallback: 1), 1...4) { String(format: "%.2f×", $0) }
                    slider("Dịch ngang", session.binding(id, \.centerX, fallback: 0.5), 0...1) { String(format: "%.2f", $0) }
                    slider("Dịch dọc", session.binding(id, \.centerY, fallback: 0.5), 0...1) { String(format: "%.2f", $0) }
                case .background:
                    slider("Kích thước thẻ ảnh", session.binding(id, \.scale, fallback: 1), 0.4...1.2) { String(format: "%.2f×", $0) }
                    slider("Vị trí X", session.binding(id, \.centerX, fallback: 0.5), 0.1...0.9) { String(format: "%.2f", $0) }
                    slider("Vị trí Y", session.binding(id, \.centerY, fallback: 0.5), 0.1...0.9) { String(format: "%.2f", $0) }
                }
                HStack {
                    Toggle("Lật ngang", isOn: session.binding(id, \.flipHorizontal, fallback: false, undoable: true))
                    Toggle("Lật dọc", isOn: session.binding(id, \.flipVertical, fallback: false, undoable: true))
                }
                .font(.caption)
            }

            group("Hiệu chỉnh") {
                if kind == .overlay {
                    slider("Làm mờ (Blur)", session.binding(id, \.blurRadius, fallback: 0), 0...40) { String(format: "%.0f px", $0) }
                }
                slider("Độ sáng (Brightness)", session.binding(id, \.brightness, fallback: 0), -0.8...0.8) { String(format: "%+.2f", $0) }
                slider("Tương phản (Contrast)", session.binding(id, \.contrast, fallback: 1), 0.5...2) { String(format: "%.2f×", $0) }
                slider("Bão hòa (Saturation)", session.binding(id, \.saturation, fallback: 1), 0...2) { String(format: "%.2f×", $0) }
                slider("Độ ấm (Warmth)", session.binding(id, \.warmth, fallback: 0), -0.6...0.6) { String(format: "%+.2f", $0) }
            }

            if kind == .overlay {
                group("Mask") { maskControls(id, mask: layer.mask) }
            }
        }
        .disabled(locked)
    }

    // MARK: Pieces

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        display: @escaping (Double) -> String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display(value.wrappedValue)).monospacedDigit().foregroundStyle(.cyan)
            }
            .font(.caption)
            Slider(value: value, in: range, onEditingChanged: { editing in
                if editing { session.beginEdit() }
            })
            .tint(.cyan)
        }
    }

    private func blendPicker(_ id: UUID, current: MockupBlendMode) -> some View {
        var modes = MockupBlendMode.studioModes
        if !modes.contains(current) { modes.append(current) }       // e.g. "Add" from a procedural design
        let binding = Binding<MockupBlendMode>(
            get: { session.model.mockupOverlays.first { $0.id == id }?.blendMode ?? .normal },
            set: { mode in
                session.beginEdit()
                if let i = session.model.mockupOverlays.firstIndex(where: { $0.id == id }) {
                    session.model.mockupOverlays[i].blendMode = mode
                }
            }
        )
        return HStack {
            Text("Chế độ hòa trộn").font(.caption)
            Spacer()
            Picker("Chế độ hòa trộn", selection: binding) {
                ForEach(modes) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().tint(.cyan)
        }
    }

    @ViewBuilder
    private func maskControls(_ id: UUID, mask: MockupMask) -> some View {
        let kind = Binding<MockupMaskKind>(
            get: { session.model.mockupOverlays.first { $0.id == id }?.mask.kind ?? .none },
            set: { value in
                session.beginEdit()
                if let i = session.model.mockupOverlays.firstIndex(where: { $0.id == id }) {
                    session.model.mockupOverlays[i].mask.kind = value
                }
            }
        )
        HStack {
            Text("Hình mask").font(.caption)
            Spacer()
            Picker("Hình mask", selection: kind) {
                ForEach(MockupMaskKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().tint(.cyan)
        }
        if mask.isActive {
            slider("Kích thước vùng", session.binding(id, \.mask.size, fallback: 0.35), 0...1) { "\(Int($0 * 100))%" }
            slider("Độ mềm viền", session.binding(id, \.mask.feather, fallback: 0.35), 0...1) { "\(Int($0 * 100))%" }
            Toggle("Đảo mask", isOn: session.binding(id, \.mask.invert, fallback: false, undoable: true)).font(.caption)
        }
    }
}
