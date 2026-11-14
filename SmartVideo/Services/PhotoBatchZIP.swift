import Foundation

/// Streaming, uncompressed ZIP (store method): no external libraries,
/// doesn't load 8K images into memory and preserves each photo's bytes.
enum PhotoBatchZIP {
    static func create(files: [URL]) throws -> URL {
        guard !files.isEmpty, files.count <= 50 else {
            throw SmartVideoError.invalidMedia(
                "ZIP hỗ trợ 1–50 ảnh trong mỗi lượt.")
        }
        let output = MediaStorage.exportsDirectory
            .appendingPathComponent("ViePN-Photos-" +
                UUID().uuidString.prefix(8) + ".zip")
        FileManager.default.createFile(
            atPath: output.path, contents: nil)
        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }
        var total: UInt64 = 0
        var directory = Data()
        var entries: UInt16 = 0
        do {
            for (index, file) in files.enumerated() {
                try Task.checkCancellation()
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: file.path)
                guard let length = attributes[.size] as? NSNumber,
                      length.uint64Value <= 512_000_000,
                      total + length.uint64Value <= 1_500_000_000 else {
                    throw SmartVideoError.invalidMedia(
                        "ZIP quá lớn; hãy xuất ít ảnh hơn.")
                }
                let name = String(format: "ViePN-%03d", index + 1) +
                    "." + file.pathExtension.lowercased()
                let nameBytes = Data(name.utf8)
                let (size, crc) = try checksum(of: file)
                guard size <= UInt32.max, nameBytes.count <= 65535,
                      total <= UInt32.max else {
                    throw SmartVideoError.invalidMedia(
                        "Kích thước ZIP vượt giới hạn định dạng.")
                }
                let start = UInt32(total)
                var header = Data()
                header.put32(0x04034b50)
                header.put16(20)
                header.put16(0)
                header.put16(0) // store (already compressed JPG/HEIC/PNG)
                header.put16(0)
                header.put16(0)
                header.put32(crc)
                header.put32(UInt32(size))
                header.put32(UInt32(size))
                header.put16(UInt16(nameBytes.count))
                header.put16(0)
                header.append(nameBytes)
                try writer.write(contentsOf: header)
                total += UInt64(header.count)
                let reader = try FileHandle(forReadingFrom: file)
                defer { try? reader.close() }
                while true {
                    let chunk = try reader.read(upToCount: 65536) ?? Data()
                    if chunk.isEmpty { break }
                    try writer.write(contentsOf: chunk)
                    total += UInt64(chunk.count)
                }
                var central = Data()
                central.put32(0x02014b50)
                central.put16(20)
                central.put16(20)
                central.put16(0)
                central.put16(0)
                central.put16(0)
                central.put16(0)
                central.put32(crc)
                central.put32(UInt32(size))
                central.put32(UInt32(size))
                central.put16(UInt16(nameBytes.count))
                central.put16(0)
                central.put16(0)
                central.put16(0)
                central.put16(0)
                central.put32(0)
                central.put32(start)
                central.append(nameBytes)
                directory.append(central)
                entries += 1
            }
            guard total + UInt64(directory.count) + 22 <= UInt32.max else {
                throw SmartVideoError.invalidMedia(
                    "ZIP lớn hơn giới hạn 4 GB.")
            }
            try writer.write(contentsOf: directory)
            var footer = Data()
            footer.put32(0x06054b50)
            footer.put16(0)
            footer.put16(0)
            footer.put16(entries)
            footer.put16(entries)
            footer.put32(UInt32(directory.count))
            footer.put32(UInt32(total))
            footer.put16(0)
            try writer.write(contentsOf: footer)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }

    private static func checksum(of file: URL) throws -> (UInt64, UInt32) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var crc: UInt32 = 0xffffffff
        var length: UInt64 = 0
        while true {
            let chunk = try handle.read(upToCount: 65536) ?? Data()
            if chunk.isEmpty { break }
            length += UInt64(chunk.count)
            for byte in chunk {
                crc ^= UInt32(byte)
                for _ in 0..<8 {
                    crc = (crc >> 1) ^
                        ((crc & 1) == 1 ? 0xedb88320 : 0)
                }
            }
        }
        return (length, ~crc)
    }
}

private extension Data {
    mutating func put16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func put32(_ value: UInt32) {
        put16(UInt16(truncatingIfNeeded: value))
        put16(UInt16(truncatingIfNeeded: value >> 16))
    }
}
