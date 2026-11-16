import Foundation

/// File-system side of StoragePolicy.
enum StorageCleaner {
    private static func entries(in directory: URL) -> [StoragePolicy.Entry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        )) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { return nil }
            return StoragePolicy.Entry(
                name: url.lastPathComponent,
                modified: values.contentModificationDate ?? Date(),
                bytes: Int64(values.fileSize ?? 0)
            )
        }
    }

    private static func delete(_ names: [String], in directory: URL) -> Int {
        var removed = 0
        for name in names {
            // Names come from a directory listing; never follow a path.
            let safe = (name as NSString).lastPathComponent
            if (try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(safe)
            )) != nil { removed += 1 }
        }
        return removed
    }

    /// Run at launch: nothing is mid-render then, so stale intermediates go.
    @discardableResult
    static func sweepTemporary(now: Date = Date()) -> Int {
        let dir = MediaStorage.temporaryDirectory
        return delete(StoragePolicy.tempFilesToDelete(entries(in: dir), now: now), in: dir)
    }

    static func exportsSummary() -> (count: Int, bytes: Int64) {
        let all = entries(in: MediaStorage.exportsDirectory)
        return (all.count, all.reduce(0) { $0 + $1.bytes })
    }

    static func temporarySummary() -> (count: Int, bytes: Int64) {
        let all = entries(in: MediaStorage.temporaryDirectory)
        return (all.count, all.reduce(0) { $0 + $1.bytes })
    }

    /// User-triggered only.
    @discardableResult
    static func purgeExports(olderThanDays days: Int, now: Date = Date()) -> Int {
        let dir = MediaStorage.exportsDirectory
        return delete(StoragePolicy.exportsToDelete(entries(in: dir), now: now,
                                                    olderThanDays: days), in: dir)
    }

    @discardableResult
    static func purgeAllTemporary() -> Int {
        let dir = MediaStorage.temporaryDirectory
        return delete(entries(in: dir).map(\.name), in: dir)
    }
}
