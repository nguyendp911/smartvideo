import Foundation

@main
struct StoragePolicyTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func entry(_ name: String, hoursAgo: Double, mb: Int64 = 1) -> StoragePolicy.Entry {
            .init(name: name, modified: now.addingTimeInterval(-hoursAgo * 3600),
                  bytes: mb * 1_000_000)
        }

        // Intermediates: only those older than 24 h go.
        let temp = StoragePolicy.tempFilesToDelete([
            entry("a.mov", hoursAgo: 1), entry("b.mov", hoursAgo: 30),
            entry("partial-1.mov", hoursAgo: 25), entry("c.wav", hoursAgo: 23.9)
        ], now: now)
        precondition(temp == ["b.mov", "partial-1.mov"], "got \(temp)")

        // Alpha cache survives a day but not 14 days.
        let alpha = StoragePolicy.tempFilesToDelete([
            entry("alpha-1.mov", hoursAgo: 48), entry("alpha-2.mov", hoursAgo: 15 * 24)
        ], now: now)
        precondition(alpha == ["alpha-2.mov"], "got \(alpha)")

        // Size cap removes the OLDEST alpha files first.
        let big = StoragePolicy.tempFilesToDelete([
            entry("alpha-new.mov", hoursAgo: 1, mb: 900),
            entry("alpha-mid.mov", hoursAgo: 5, mb: 500),
            entry("alpha-old.mov", hoursAgo: 9, mb: 300)
        ], now: now)
        precondition(big == ["alpha-old.mov"], "got \(big)")

        // Exports: explicit age only; invalid days delete nothing.
        let exports = [entry("SmartVideo-1.mp4", hoursAgo: 24 * 10),
                       entry("SmartVideo-2.mp4", hoursAgo: 24 * 2)]
        precondition(StoragePolicy.exportsToDelete(exports, now: now, olderThanDays: 7)
                     == ["SmartVideo-1.mp4"])
        precondition(StoragePolicy.exportsToDelete(exports, now: now, olderThanDays: 0).isEmpty)
        precondition(StoragePolicy.exportsToDelete([], now: now, olderThanDays: 7).isEmpty)

        print("storage policy tests passed")
    }
}
