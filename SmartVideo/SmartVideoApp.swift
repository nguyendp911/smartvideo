import SwiftUI

@main
struct SmartVideoApp: App {
    var body: some Scene {
        WindowGroup {
            EditorView()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    IncomingLinkInbox.shared.receive(url)
                }
                .task {
                    // Nothing is rendering at launch: drop stale intermediates.
                    _ = await Task.detached(priority: .utility) {
                        StorageCleaner.sweepTemporary()
                    }.value
                }
        }
    }
}
