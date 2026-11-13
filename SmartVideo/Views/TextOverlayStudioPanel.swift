import SwiftUI

struct TextOverlayStudioPanel: View {
    @ObservedObject var model: EditorViewModel
    @Binding var selectedID: UUID?
    @State private var styleCategory = 0
    let onScrub: (Double) -> Void
    let importTextFill: (Bool) -> Void
    let autoPosition: (UUID) -> Void

    private var selected: TextOverlayClip? {
        model.textOverlays.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Lớp chữ & tiêu đề", systemImage: "textformat")
                    .font(.headline)
                Spacer()
                Button {
                    model.addTextOverlay()
                    selectedID = model.textOverlays.last?.id
                } label: {
                    Label("Thêm chữ", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }

            ForEach(model.textOverlays) { item in
                HStack(spacing: 6) {
                    Button {
                        selectedID = item.id
                    } label: {
                        HStack {
                            Text(item.text).lineLimit(1)
                            Spacer()
                            if selectedID == item.id {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(8)
                        .background(selectedID == item.id ?
                            Color.cyan.opacity(0.18) : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    Button(role: .destructive) {
                        model.removeTextOverlay(item.id)
                        selectedID = model.textOverlays.first?.id
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                }
                .font(.caption)
            }

            if let item = selected,
               let idx = model.textOverlays.firstIndex(where: { $0.id == item.id }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thư viện Style Chữ Pro • \(TextTitlePreset.allCases.count) mẫu")
                        .font(.caption.bold())
                    Picker("Nhóm style", selection: $styleCategory) {
                        Text("Cơ bản").tag(0)
                        Text("Neon & FX").tag(1)
                        Text("Kim loại").tag(2)
                        Text("Quảng cáo").tag(3)
                    }
                    .pickerStyle(.segmented)
                    let styles: [TextTitlePreset] = {
                        switch styleCategory {
                        case 1: return [.neonBlue, .neonPink, .fire, .ice, .cyberpunk]
                        case 2: return [.chrome, .royalGold, .cinematic]
                        case 3: return [.saleFlash, .laptopSale, .productName]
                        default: return [.behindPerson, .bigBold, .imagePoster,
                                         .videoReveal, .travel]
                        }
                    }()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(styles) { preset in
                                Button {
                                    preset.apply(to: &model.textOverlays[idx])
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 9)
                                                .fill(Color.black.opacity(0.9))
                                            Text("Aa")
                                                .font(.system(size: 31, weight: .black))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: [
                                                            Color.cyan.opacity(0.95),
                                                            Color.white,
                                                            Color.pink.opacity(0.8)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .shadow(color: .cyan.opacity(0.6),
                                                        radius: styleCategory == 1 ? 9 : 1)
                                        }
                                        .frame(width: 100, height: 57)
                                        Text(preset.rawValue)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 104)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("Chọn mẫu để áp dụng vào lớp chữ; có thể chỉnh tiếp viền, glow, bóng, màu và keyframe.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Picker("Vị trí theo chủ thể",
                       selection: $model.textOverlays[idx].depthMode) {
                    ForEach(TextDepthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if item.depthMode == .behindPerson {
                    Toggle(
                        "Tự mở rộng chữ để không bị người che hết",
                        isOn: $model.textOverlays[idx].behindVisibilityAssist
                    )
                    .font(.caption)
                    Text("Khi chữ nhỏ nằm đúng giữa người, cơ thể có thể che toàn bộ ký tự. Tùy chọn này tự phóng rộng chữ về hai bên người khi xuất video. Tắt để giữ nguyên cỡ chữ đã chọn.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Chữ sẽ được ghép sau người bằng Vision khi xuất video hoặc Xem thử 720p. Chỉ tách người, chưa tách các loại vật thể khác.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button {
                    autoPosition(item.id)
                } label: {
                    Label("AI gợi ý vị trí tránh khuôn mặt",
                          systemImage: "face.dashed")
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Picker("Nội dung bên trong chữ",
                       selection: $model.textOverlays[idx].fillMode) {
                    ForEach(TextFillMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                if item.fillMode == .gradient {
                    Text("Màu chuyển sắc thứ hai (HEX)")
                        .font(.caption.bold())
                    TextField("18D6F5",
                              text: $model.textOverlays[idx].gradientEndHex)
                        .textInputAutocapitalization(.characters)
                        .textFieldStyle(.roundedBorder)
                }
                if item.fillMode == .image || item.fillMode == .video {
                    HStack {
                        Button {
                            importTextFill(item.fillMode == .video)
                        } label: {
                            Label(item.fillMode == .video ?
                                  "Chọn video trong chữ" :
                                  "Chọn ảnh trong chữ",
                                  systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer(minLength: 0)
                        Text(item.fillAssetURL?.lastPathComponent ??
                             "Chưa chọn")
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    Picker("Cách đặt ảnh/video", selection:
                        $model.textOverlays[idx].maskFit) {
                        ForEach(TextMaskFit.allCases) { fit in
                            Text(fit.rawValue).tag(fit)
                        }
                    }
                    .pickerStyle(.segmented)
                    row("Phóng to nội dung trong chữ",
                        String(format: "%.1fx", item.maskScale))
                    Slider(value: $model.textOverlays[idx].maskScale,
                           in: 0.5...4, step: 0.05).tint(.cyan)
                    row("Dịch ảnh theo X",
                        String(format: "%.2f", item.maskOffsetX))
                    Slider(value: $model.textOverlays[idx].maskOffsetX,
                           in: -1...1, step: 0.02).tint(.cyan)
                    row("Dịch ảnh theo Y",
                        String(format: "%.2f", item.maskOffsetY))
                    Slider(value: $model.textOverlays[idx].maskOffsetY,
                           in: -1...1, step: 0.02).tint(.cyan)
                    if item.fillMode == .video {
                        Text("Video trong chữ lấy mẫu tối đa 32 khung từ 4 giây đầu, rồi lặp để tối ưu bộ nhớ. Xem thử 720p để kiểm tra chuyển động thực.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Hiệu ứng viền và chiều sâu")
                    .font(.caption.bold())
                row("Độ dày viền", String(format: "%.1f", item.strokeWidth))
                Slider(value: $model.textOverlays[idx].strokeWidth,
                       in: 0...12, step: 0.5).tint(.cyan)
                TextField("Màu viền (HEX)",
                          text: $model.textOverlays[idx].strokeHex)
                    .textInputAutocapitalization(.characters)
                    .textFieldStyle(.roundedBorder)
                row("Bóng đổ", "\(Int(item.shadowOpacity * 100))%")
                Slider(value: $model.textOverlays[idx].shadowOpacity,
                       in: 0...1, step: 0.05).tint(.cyan)
                row("Glow", String(format: "%.1f", item.glowRadius))
                Slider(value: $model.textOverlays[idx].glowRadius,
                       in: 0...20, step: 1).tint(.cyan)
                row("Nổi giả 3D", String(format: "%.1f", item.fauxDepth))
                Slider(value: $model.textOverlays[idx].fauxDepth,
                       in: 0...20, step: 1).tint(.cyan)
                Toggle("Chữ nhịp thở (Pulse)",
                       isOn: $model.textOverlays[idx].pulseEnabled)
                    .font(.caption)

                TextField("Nội dung chữ", text: $model.textOverlays[idx].text,
                          axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                row("Bắt đầu", "\(String(format: "%.1f", item.start))s")
                Slider(value: $model.textOverlays[idx].start,
                       in: 0...max(0.1, model.totalDuration - 0.1),
                       step: 0.1).tint(.cyan)

                row("Thời lượng", "\(String(format: "%.1f", item.duration))s")
                Slider(value: $model.textOverlays[idx].duration,
                       in: 0.1...max(0.2, model.totalDuration - item.start),
                       step: 0.1).tint(.cyan)

                MultiPointKeyframePanel(
                    keyframes: $model.textOverlays[idx].keyframes,
                    easing: $model.textOverlays[idx].easing,
                    pathMode: $model.textOverlays[idx].pathMode,
                    start: item.start, duration: item.duration,
                    timelineSecond: model.timelineSecond,
                    legacyStart: OverlayKeyframe(
                        progress: 0, x: item.startX, y: item.startY,
                        scale: 0.45, opacity: item.opacity,
                        rotationDegrees: 0
                    ),
                    legacyEnd: OverlayKeyframe(
                        progress: 1, x: item.endX, y: item.endY,
                        scale: 0.45, opacity: item.opacity,
                        rotationDegrees: 0
                    ),
                    onScrub: onScrub
                )

                row("Cỡ chữ", "\(Int(item.fontSize))")
                Slider(value: $model.textOverlays[idx].fontSize,
                       in: 20...120, step: 2).tint(.cyan)

                Text("Màu chữ (HEX)")
                    .font(.caption.bold())
                TextField("FFFFFF", text: $model.textOverlays[idx].colorHex)
                    .textInputAutocapitalization(.characters)
                    .textFieldStyle(.roundedBorder)

                Toggle("Nền tối sau chữ",
                       isOn: $model.textOverlays[idx].useBackground)
                    .font(.caption)
                if item.keyframes.isEmpty {
                row("Độ mờ", "\(Int(item.opacity * 100))%")
                Slider(value: $model.textOverlays[idx].opacity,
                       in: 0.05...1, step: 0.05).tint(.cyan)

                Picker("Đường chuyển động", selection: $model.textOverlays[idx].easing) {
                    ForEach(OverlayEasing.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.menu)

                Text("Vị trí đầu: kéo trên preview hoặc chỉnh X/Y")
                    .font(.caption.bold())
                Slider(value: $model.textOverlays[idx].startX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.textOverlays[idx].startY,
                       in: 0.05...0.95, step: 0.01)

                Text("Vị trí cuối")
                    .font(.caption.bold())
                Slider(value: $model.textOverlays[idx].endX,
                       in: 0.05...0.95, step: 0.01)
                Slider(value: $model.textOverlays[idx].endY,
                       in: 0.05...0.95, step: 0.01)

                Button("Đặt tiêu đề chính giữa") {
                    model.textOverlays[idx].startX = 0.5
                    model.textOverlays[idx].startY = 0.5
                    model.textOverlays[idx].endX = 0.5
                    model.textOverlays[idx].endY = 0.5
                }
                .buttonStyle(.bordered)
                .font(.caption)
                }
            }
        }.padding(10)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.caption)
    }
}
