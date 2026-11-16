import Foundation

/// Which cached/intermediate files may be deleted. Pure so it can be tested
/// without touching the file system. User exports are never removed here
/// unless the user explicitly asks for it.
enum StoragePolicy {
    struct Entry: Equatable {
        var name: String
        var modified: Date
        var bytes: Int64
    }

    static let tempMaxAge: TimeInterval = 24 * 3600
    static let alphaPrefix = "alpha-"
    static let alphaMaxAge: TimeInterval = 14 * 24 * 3600
    static let alphaMaxBytes: Int64 = 1_500_000_000

    /// Files in RenderTemp to delete: any intermediate older than a day, and
    /// the keyed-video cache (`alpha-*.mov`) once it is older than 14 days or
    /// beyond the size cap (oldest go first).
    static func tempFilesToDelete(_ entries: [Entry], now: Date) -> [String] {
        var doomed = Set<String>()
        var alpha: [Entry] = []
        for entry in entries {
            let age = now.timeIntervalSince(entry.modified)
            if entry.name.hasPrefix(alphaPrefix) {
                if age > alphaMaxAge { doomed.insert(entry.name) } else { alpha.append(entry) }
            } else if age > tempMaxAge {
                doomed.insert(entry.name)
            }
        }
        var total: Int64 = 0
        for entry in alpha.sorted(by: { $0.modified > $1.modified }) {
            total += entry.bytes
            if total > alphaMaxBytes { doomed.insert(entry.name) }
        }
        return doomed.sorted()
    }

    /// Exports older than `days`, only when the user asks.
    static func exportsToDelete(_ entries: [Entry], now: Date, olderThanDays days: Int) -> [String] {
        guard days >= 1 else { return [] }
        let limit = TimeInterval(days) * 24 * 3600
        return entries.filter { now.timeIntervalSince($0.modified) > limit }
            .map(\.name).sorted()
    }
}
