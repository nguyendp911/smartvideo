import SwiftUI

/// Full-screen Mockup Studio. Wide screens get categories | library | canvas |
/// properties; phones get the canvas on top (or beside, in landscape) and a
/// tabbed bottom/side panel. All panes share one `MockupStudioSession`.
struct MockupStudioView: View {
    @ObservedObject var model: EditorViewModel
    @StateObject private var session: MockupStudioSession
    @Environment(\.dismiss) private var dismiss
    @State private var compactTab: CompactTab = .library

    enum CompactTab: String, CaseIterable, Identifiable {
        case library = "Thư viện", layers = "Lớp", properties = "Chỉnh"
        var id: String { rawValue }
    }

    init(model: EditorViewModel) {
        self.model = model
        _session = StateObject(wrappedValue: MockupStudioSession(model: model))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                MockupToolbarView(session: session, model: model, onClose: { dismiss() })
                Divider().overlay(Color.white.opacity(0.08))
                if geo.size.width >= 980 {
                    wideLayout
                } else if geo.size.width > geo.size.height {
                    HStack(spacing: 0) {
                        MockupCanvasView(session: session, model: model)
                        Divider().overlay(Color.white.opacity(0.08))
                        compactPanel.frame(width: min(400, geo.size.width * 0.46))
                    }
                } else {
                    VStack(spacing: 0) {
                        MockupCanvasView(session: session, model: model)
                            .frame(height: geo.size.height * 0.44)
                        Divider().overlay(Color.white.opacity(0.08))
                        compactPanel
                    }
                }
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.075).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { session.refreshSource() }
        .onChange(of: model.mockupOverlays) { _ in session.scheduleRender() }
        .onChange(of: model.timelineSecond) { _ in session.refreshSource() }
        .onChange(of: model.clips) { _ in session.refreshSource() }
        .onChange(of: session.ghostAssetID) { _ in session.scheduleRender() }
    }

    private var wideLayout: some View {
        HStack(spacing: 0) {
            MockupSidebarView(session: session, axis: .vertical)
                .frame(width: 176)
            Divider().overlay(Color.white.opacity(0.08))
            MockupLibraryView(session: session)
                .frame(width: 318)
            Divider().overlay(Color.white.opacity(0.08))
            MockupCanvasView(session: session, model: model)
            Divider().overlay(Color.white.opacity(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MockupLayerListView(session: session, model: model)
                    MockupPropertiesView(session: session, model: model)
                }
                .padding(12)
            }
            .frame(width: 322)
        }
    }

    private var compactPanel: some View {
        VStack(spacing: 0) {
            Picker("Bảng", selection: $compactTab) {
                ForEach(CompactTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.vertical, 8)
            switch compactTab {
            case .library:
                MockupSidebarView(session: session, axis: .horizontal)
                MockupLibraryView(session: session)
            case .layers:
                ScrollView { MockupLayerListView(session: session, model: model).padding(12) }
            case .properties:
                ScrollView { MockupPropertiesView(session: session, model: model).padding(12) }
            }
        }
        .onChange(of: session.selectedID) { id in
            if id != nil, compactTab == .library { compactTab = .properties }
        }
    }
}
