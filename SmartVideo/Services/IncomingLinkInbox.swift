import SwiftUI

/// Shared hand-off between the app's URL handler and the video vault panel.
@MainActor
final class IncomingLinkInbox: ObservableObject {
    static let shared = IncomingLinkInbox()
    @Published var pendingLink: String?

    func receive(_ url: URL) {
        if let link = IncomingLink.extract(from: url) { pendingLink = link }
    }
}
