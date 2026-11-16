import SwiftUI
import UniformTypeIdentifiers

/// Pick / import a `.cube` LUT for one clip and set its strength.
struct ClipLUTControl: View {
    @ObservedObject var model: EditorViewModel
    let clipID: UUID

    @State private var showImporter = false
    @State private var library: [String] = LUTLibrary.list()
    @State private var message = ""

    private var index: Int? { model.clips.firstIndex(where: { $0.id == clipID }) }
    private var current: String? {
        index.flatMap { model.clips[$0].colorAdjustments.lutName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LUT màu (.cube)").font(.caption.bold())
                Spacer()
                Menu {
                    Button("Không dùng LUT") { select(nil) }
                    ForEach(library, id: \.self) { name in
                        Button(name) { select(name) }
                    }
                    Divider()
                    Button("Nhập tệp .cube…") { showImporter = true }
                    if let current {
                        Button("Xóa LUT này khỏi thư viện", role: .destructive) {
                            LUTLibrary.delete(current)
                            clearEveryUse(of: current)
                            library = LUTLibrary.list()
                        }
                    }
                } label: {
                    Label(current ?? "Chọn LUT", systemImage: "camera.filters")
                        .lineLimit(1)
                }
                .font(.caption)
            }
            if let current, let i = index {
                if !LUTLibrary.exists(current) {
                    Text("Không tìm thấy tệp LUT này trên máy; clip sẽ hiển thị không có LUT.")
                        .font(.caption2).foregroundStyle(.orange)
                }
                HStack {
                    Text("Cường độ LUT")
                    Spacer()
                    Text("\(Int(model.clips[i].colorAdjustments.lutIntensity * 100))%")
                        .monospacedDigit().foregroundStyle(.cyan)
                }
                .font(.caption2)
                Slider(value: Binding(
                    get: { model.clips[i].colorAdjustments.lutIntensity },
                    set: { model.clips[i].colorAdjustments.lutIntensity = $0 }
                ), in: 0...1).tint(.cyan)
            }
            if !message.isEmpty {
                Text(message).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data, .plainText, .data]
        ) { result in
            do {
                let name = try LUTLibrary.importLUT(from: try result.get())
                library = LUTLibrary.list()
                select(name)
                message = "Đã nhập LUT \(name)."
            } catch {
                message = "Không nhập được LUT: \(error.localizedDescription)"
            }
        }
    }

    private func select(_ name: String?) {
        guard let i = index else { return }
        model.checkpoint()
        model.clips[i].colorAdjustments.lutName = name
    }

    private func clearEveryUse(of name: String) {
        for i in model.clips.indices where model.clips[i].colorAdjustments.lutName == name {
            model.clips[i].colorAdjustments.lutName = nil
        }
    }
}
