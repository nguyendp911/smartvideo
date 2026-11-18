import Foundation

@main
struct IncomingLinkTests {
    static func main() {
        func extract(_ s: String) -> String? {
            IncomingLink.extract(from: URL(string: s)!)
        }
        let tiktok = "https://www.tiktok.com/@user/video/123?is_from_webapp=1&sender_device=pc"
        let encoded = tiktok.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics) ?? ""

        precondition(extract("smartvideo://import?link=\(encoded)") == tiktok)
        precondition(extract("smartvideo://import?url=\(encoded)") == tiktok)
        precondition(extract("SMARTVIDEO://import?LINK=\(encoded)") == tiktok)

        // Wrong scheme, wrong host, missing parameter.
        precondition(extract("https://example.com/import?link=\(encoded)") == nil)
        precondition(extract("smartvideo://other?link=\(encoded)") == nil)
        precondition(extract("smartvideo://import") == nil)
        precondition(extract("smartvideo://import?link=") == nil)

        // Only http(s) links with a host are accepted: no file://, javascript:, etc.
        for bad in ["file:///private/var/mobile/secret.mp4",
                    "javascript:alert(1)", "ftp://example.com/a.mp4",
                    "smartvideo://import?link=data:text/html,hi", "notaurl", "https://"] {
            let wrapped = bad.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics) ?? ""
            precondition(extract("smartvideo://import?link=\(wrapped)") == nil,
                         "accepted \(bad)")
            precondition(IncomingLink.sanitized(bad) == nil, "accepted \(bad)")
        }

        // Pasted text is trimmed; very long input is refused.
        precondition(IncomingLink.sanitized("  https://vm.tiktok.com/ZM123/ \n") ==
                     "https://vm.tiktok.com/ZM123/")
        precondition(IncomingLink.sanitized(
            "https://a.com/" + String(repeating: "x", count: 3000)) == nil)
        precondition(IncomingLink.sanitized("") == nil)

        print("incoming link tests passed")
    }
}
