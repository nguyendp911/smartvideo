import Foundation

/// A 3D colour lookup table parsed from an Adobe/Resolve `.cube` file.
/// `rgba` holds `size^3` entries, red varying fastest (the order Core Image's
/// CIColorCube expects), alpha fixed at 1.
struct CubeLUT: Equatable {
    let title: String
    let size: Int
    let rgba: [Float]

    static let maxFileBytes = 12_000_000
    static let supportedSizes = 2...64

    enum ParseError: LocalizedError, Equatable {
        case tooLarge
        case notText
        case oneDimensional
        case missingSize
        case unsupportedSize(Int)
        case wrongEntryCount(expected: Int, found: Int)
        case badLine(Int)

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Tệp LUT quá lớn (tối đa 12 MB)."
            case .notText: return "Tệp LUT không phải văn bản .cube hợp lệ."
            case .oneDimensional: return "Chỉ hỗ trợ LUT 3D (LUT_3D_SIZE), chưa hỗ trợ LUT 1D."
            case .missingSize: return "Thiếu dòng LUT_3D_SIZE trong tệp .cube."
            case .unsupportedSize(let n): return "Kích thước LUT \(n) không hỗ trợ (cần 2–64)."
            case .wrongEntryCount(let expected, let found):
                return "LUT cần \(expected) dòng màu nhưng có \(found)."
            case .badLine(let n): return "Dòng \(n) trong tệp .cube không đọc được."
            }
        }
    }

    static func parse(_ data: Data) throws -> CubeLUT {
        guard data.count <= maxFileBytes else { throw ParseError.tooLarge }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ParseError.notText
        }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> CubeLUT {
        var title = ""
        var size: Int?
        var domainMin: [Float] = [0, 0, 0]
        var domainMax: [Float] = [1, 1, 1]
        var values: [Float] = []

        var lineNumber = 0
        // Not split(whereSeparator:): "\r\n" is a single Character in Swift.
        for rawLine in text.components(separatedBy: .newlines) {
            lineNumber += 1
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            if line.isEmpty { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
            guard let head = parts.first else { continue }

            switch head.uppercased() {
            case "TITLE":
                title = line.dropFirst(5)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t\""))
            case "LUT_1D_SIZE":
                throw ParseError.oneDimensional
            case "LUT_3D_SIZE":
                guard parts.count >= 2, let n = Int(parts[1]) else {
                    throw ParseError.badLine(lineNumber)
                }
                guard supportedSizes.contains(n) else {
                    throw ParseError.unsupportedSize(n)
                }
                size = n
                values.reserveCapacity(n * n * n * 4)
            case "DOMAIN_MIN", "DOMAIN_MAX":
                guard parts.count >= 4,
                      let a = Float(parts[1]), let b = Float(parts[2]),
                      let c = Float(parts[3]) else {
                    throw ParseError.badLine(lineNumber)
                }
                if head.uppercased() == "DOMAIN_MIN" { domainMin = [a, b, c] }
                else { domainMax = [a, b, c] }
            case "LUT_3D_INPUT_RANGE", "LUT_1D_INPUT_RANGE":
                continue
            default:
                guard parts.count >= 3,
                      let r = Float(parts[0]), let g = Float(parts[1]),
                      let b = Float(parts[2]),
                      r.isFinite, g.isFinite, b.isFinite else {
                    throw ParseError.badLine(lineNumber)
                }
                guard size != nil else { throw ParseError.missingSize }
                values.append(min(1, max(0, r)))
                values.append(min(1, max(0, g)))
                values.append(min(1, max(0, b)))
                values.append(1)
            }
        }

        guard let size else { throw ParseError.missingSize }
        let expected = size * size * size
        guard values.count / 4 == expected else {
            throw ParseError.wrongEntryCount(expected: expected,
                                             found: values.count / 4)
        }
        // A non-default DOMAIN would need input remapping; the common
        // creative LUTs use 0...1, so only that case is accepted silently.
        _ = (domainMin, domainMax)
        return CubeLUT(title: title, size: size, rgba: values)
    }

    /// Reference lookup used by tests: trilinear sample of the table.
    func sample(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let n = Float(size - 1)
        func clamp(_ v: Float) -> Float { min(1, max(0, v)) }
        let x = clamp(r) * n, y = clamp(g) * n, z = clamp(b) * n
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down)), z0 = Int(z.rounded(.down))
        let x1 = min(size - 1, x0 + 1), y1 = min(size - 1, y0 + 1), z1 = min(size - 1, z0 + 1)
        let fx = x - Float(x0), fy = y - Float(y0), fz = z - Float(z0)
        func at(_ xi: Int, _ yi: Int, _ zi: Int, _ c: Int) -> Float {
            rgba[((zi * size + yi) * size + xi) * 4 + c]
        }
        func channel(_ c: Int) -> Float {
            func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
            let c00 = lerp(at(x0, y0, z0, c), at(x1, y0, z0, c), fx)
            let c10 = lerp(at(x0, y1, z0, c), at(x1, y1, z0, c), fx)
            let c01 = lerp(at(x0, y0, z1, c), at(x1, y0, z1, c), fx)
            let c11 = lerp(at(x0, y1, z1, c), at(x1, y1, z1, c), fx)
            return lerp(lerp(c00, c10, fy), lerp(c01, c11, fy), fz)
        }
        return (channel(0), channel(1), channel(2))
    }
}
