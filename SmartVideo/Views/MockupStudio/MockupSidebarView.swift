import SwiftUI

/// Categories: All / Favorites / Recent plus the ten library groups.
/// Vertical on wide screens, a horizontal chip strip on phones.
struct MockupSidebarView: View {
    @ObservedObject var session: MockupStudioSession
    let axis: Axis

    var body: some View {
        if axis == .vertical {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DANH MỤC").font(.caption2.bold()).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 10)
                    ForEach(MockupStudioSession.Section.allCases) { sectionRow($0) }
                    Divider().padding(.vertical, 4)
                    ForEach(MockupStudioCategory.allCases) { categoryRow($0) }
                }
                .padding(.horizontal, 6).padding(.bottom, 12)
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MockupStudioSession.Section.allCases) { chip(title: $0.rawValue, symbol: $0.symbol,
                        selected: session.section == $0 && session.category == nil) {
                            session.section = $0; session.category = nil
                        } }
                    ForEach(MockupStudioCategory.allCases) { category in
                        chip(title: category.title, symbol: category.symbol,
                             selected: session.category == category) {
                            session.section = .all
                            session.category = session.category == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
    }

    private func sectionRow(_ section: MockupStudioSession.Section) -> some View {
        let count: Int = {
            switch section {
            case .all: return MockupStudioCatalog.allAssets.count
            case .favorites: return session.usage.favorites.count
            case .recents: return session.usage.recents.count
            }
        }()
        return row(title: section.rawValue, symbol: section.symbol, count: count,
                   selected: session.section == section && session.category == nil) {
            session.section = section
            session.category = nil
        }
    }

    private func categoryRow(_ category: MockupStudioCategory) -> some View {
        row(title: category.title, symbol: category.symbol, count: session.count(in: category),
            selected: session.category == category) {
            session.category = session.category == category ? nil : category
            if session.section != .all { session.section = .all }
        }
    }

    private func row(title: String, symbol: String, count: Int, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(selected ? Color.cyan : .secondary)
                Text(title).font(.caption).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(selected ? Color.cyan.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.caption).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(selected ? Color.cyan.opacity(0.25) : Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
