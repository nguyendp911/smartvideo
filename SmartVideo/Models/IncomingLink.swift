import Foundation

/// Links handed to the app from outside, e.g. an iOS Shortcut that sits in
/// the Share Sheet and opens `smartvideo://import?link=<percent-encoded URL>`.
/// The link is only pre-filled in the video vault; nothing downloads until
/// the user presses the download button.
enum IncomingLink {
    static let scheme = "smartvideo"
    static let maxLength = 2048

    /// The http(s) URL carried by a `smartvideo://import?...` URL, or nil.
    static func extract(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.host?.lowercased() == "import" || parts.path == "/import",
              let raw = parts.queryItems?.first(where: {
                  ["link", "url"].contains($0.name.lowercased())
              })?.value else { return nil }
        return sanitized(raw)
    }

    /// Also used for pasted text: trims, requires http(s) with a host.
    static func sanitized(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maxLength,
              let target = URL(string: value),
              let scheme = target.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = target.host, !host.isEmpty else { return nil }
        return target.absoluteString
    }
}
