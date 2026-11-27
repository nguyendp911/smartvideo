import Foundation

enum TimelinePeriod: String, CaseIterable {
    case day = "Ngày", month = "Tháng", year = "Năm"
    var length: Int { self == .day ? 10 : self == .month ? 7 : 4 }
}
enum TimelineScope: String, CaseIterable {
    case all = "Tất cả", picks = "Đã chọn", trash = "Thùng rác"
}
struct TimelineGroup: Identifiable {
    let key: String
    let items: [Shot]
    var id: String { key }
    var cover: Shot { items.max { a,b in a.rating == b.rating ? a.date < b.date : a.rating < b.rating } ?? items[0] }
}
enum TimelineIndex {
    static func filter(_ shots: [Shot], scope: TimelineScope, query: String = "", session: String = "", period: String = "", light: Light? = nil, minimumRating: Int = 0, newest: Bool = true) -> [Shot] {
        let words = query.split(whereSeparator: \.isWhitespace).map { String($0).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier:"vi_VN")) }
        return shots.filter { s in
            guard (scope == .trash ? s.deleted != nil : s.deleted == nil),
                  (scope != .picks || s.rating >= 4),
                  s.rating >= minimumRating,
                  session.isEmpty || s.session == session,
                  period.isEmpty || s.day.hasPrefix(period),
                  light == nil || s.light == light else { return false }
            let text = [s.day,s.session,s.tags,s.light.rawValue,s.look.rawValue,s.lens].joined(separator:" ").folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"vi_VN"))
            return words.allSatisfy { text.contains($0) }
        }.sorted {
            if $0.date == $1.date { return newest ? $0.id.uuidString > $1.id.uuidString : $0.id.uuidString < $1.id.uuidString }
            return newest ? $0.date > $1.date : $0.date < $1.date
        }
    }
    static func group(_ shots: [Shot], period: TimelinePeriod, newest: Bool) -> [TimelineGroup] {
        let groups = Dictionary(grouping: shots) { String($0.day.prefix(period.length)) }
        return groups.keys.sorted { newest ? $0 > $1 : $0 < $1 }.compactMap { key in
            groups[key].map { TimelineGroup(key:key,items:$0) }
        }
    }
    static func albums(_ shots: [Shot]) -> [TimelineGroup] {
        let groups = Dictionary(grouping: shots.filter { $0.deleted == nil && !$0.session.isEmpty }, by: \.session)
        return groups.map { TimelineGroup(key:$0.key,items:$0.value) }.sorted {
            ($0.items.map(\.date).max() ?? .distantPast) > ($1.items.map(\.date).max() ?? .distantPast)
        }
    }
    static func label(_ key: String) -> String {
        let p = key.split(separator:"-")
        if p.count == 3 { return "\(Int(p[2]) ?? 1) tháng \(Int(p[1]) ?? 1), \(p[0])" }
        if p.count == 2 { return "Tháng \(Int(p[1]) ?? 1), \(p[0])" }
        return key
    }
}
