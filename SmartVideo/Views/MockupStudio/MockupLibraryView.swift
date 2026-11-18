import SwiftUI

/// Search + type filter + a lazy grid of real asset thumbnails.
struct MockupLibraryView: View {
    @ObservedObject var session: MockupStudioSession
    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 170), spacing: 10)]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Tìm theo tên, thẻ, mô tả…", text: $session.query)
                    .textFieldStyle(.plain).autocorrectionDisabled().textInputAutocapitalization(.never)
                if !session.query.isEmpty {
                    Button { session.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Xóa tìm kiếm")
                }
            }
            .padding(8).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    kindChip("Tất cả loại", nil)
                    ForEach(MockupStudioKind.allCases) { kindChip($0.title, $0) }
                }
            }

            let assets = session.visibleAssets
            if assets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(assets) { MockupCardView(asset: $0, session: session) }
                    }
                    .padding(.bottom, 12)
                }
            }
            if !session.message.isEmpty {
                Text(session.message).font(.caption2).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12).padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: session.section == .favorites ? "star" : "magnifyingglass")
                .font(.title2).foregroundStyle(.secondary)
            Text(emptyText).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyText: String {
        switch session.section {
        case .favorites where session.query.isEmpty && session.category == nil && session.kind == nil:
            return "Chưa có mẫu yêu thích. Chạm ngôi sao trên thẻ để lưu."
        case .recents where session.query.isEmpty && session.category == nil && session.kind == nil:
            return "Chưa dùng mẫu nào. Chạm vào một thẻ để thêm vào ảnh."
        default:
            return "Không có mẫu phù hợp bộ lọc."
        }
    }

    private func kindChip(_ title: String, _ kind: MockupStudioKind?) -> some View {
        let selected = session.kind == kind
        return Button { session.kind = kind } label: {
            Text(title).font(.caption2)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(selected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
