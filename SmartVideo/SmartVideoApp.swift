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
        }
    }
}
