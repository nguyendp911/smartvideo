import Foundation

@main
struct CubeLUTTests {
    static func near(_ a: Float, _ b: Float, tolerance: Float = 0.001) {
        precondition(abs(a - b) < tolerance, "Expected \(b) got \(a)")
    }

    static func identityText(size: Int, lineEnding: String = "\n") -> String {
        var lines = ["# generated", "TITLE \"Identity\"", "LUT_3D_SIZE \(size)"]
        let n = Float(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            lines.append("\(Float(r) / n) \(Float(g) / n) \(Float(b) / n)")
        } } }
        return lines.joined(separator: lineEnding)
    }

    static func expectError(_ text: String, _ expected: CubeLUT.ParseError) {
        do {
            _ = try CubeLUT.parse(text)
            preconditionFailure("expected \(expected)")
        } catch let error as CubeLUT.ParseError {
            precondition(error == expected, "got \(error), expected \(expected)")
        } catch {
            preconditionFailure("unexpected error \(error)")
        }
    }

    static func main() throws {
        // 1. Identity LUTs of several sizes parse and sample as identity.
        for size in [2, 3, 17, 33] {
            let lut = try CubeLUT.parse(identityText(size: size))
            precondition(lut.size == size)
            precondition(lut.title == "Identity")
            precondition(lut.rgba.count == size * size * size * 4)
            for (r, g, b) in [(0.0, 0.0, 0.0), (1.0, 1.0, 1.0), (0.3, 0.6, 0.9),
                              (0.5, 0.25, 0.75)] as [(Float, Float, Float)] {
                let out = lut.sample(r, g, b)
                near(out.0, r); near(out.1, g); near(out.2, b)
            }
        }

        // 2. Windows line endings, comments, blank lines, trailing comments.
        let crlf = try CubeLUT.parse(identityText(size: 2, lineEnding: "\r\n")
                                     + "\r\n\r\n# end")
        precondition(crlf.size == 2)

        // 3. Red is the fastest axis: entry 1 is (1, 0, 0) for identity.
        near(crlf.rgba[4], 1); near(crlf.rgba[5], 0); near(crlf.rgba[6], 0)
        near(crlf.rgba[7], 1)                // alpha
        // entry 2 should be green = 1
        near(crlf.rgba[8], 0); near(crlf.rgba[9], 1)

        // 4. A tint LUT really changes colours (all entries -> sepia-ish red).
        var tint = "LUT_3D_SIZE 2\n"
        for _ in 0..<8 { tint += "1.0 0.5 0.0\n" }
        let tinted = try CubeLUT.parse(tint)
        let out = tinted.sample(0.2, 0.9, 0.4)
        near(out.0, 1); near(out.1, 0.5); near(out.2, 0)

        // 5. Out-of-range values are clamped to 0...1.
        let clamped = try CubeLUT.parse("LUT_3D_SIZE 2\n" +
            String(repeating: "2.0 -1.0 0.5\n", count: 8))
        near(clamped.rgba[0], 1); near(clamped.rgba[1], 0)

        // 6. Errors are specific and never crash.
        expectError("LUT_1D_SIZE 16\n0 0 0\n", .oneDimensional)
        expectError("0 0 0\n1 1 1\n", .missingSize)
        expectError("# nothing here\n", .missingSize)
        expectError("LUT_3D_SIZE 1\n0 0 0\n", .unsupportedSize(1))
        expectError("LUT_3D_SIZE 65\n", .unsupportedSize(65))
        expectError("LUT_3D_SIZE 2\n0 0 0\n1 1 1\n",
                    .wrongEntryCount(expected: 8, found: 2))
        expectError("LUT_3D_SIZE 2\n0 0 0\nfoo bar baz\n", .badLine(3))
        expectError("LUT_3D_SIZE 2\n0 0 nan\n", .badLine(2))

        // 7. Oversized input is rejected before parsing.
        do {
            _ = try CubeLUT.parse(Data(count: CubeLUT.maxFileBytes + 1))
            preconditionFailure("oversized data accepted")
        } catch let error as CubeLUT.ParseError {
            precondition(error == .tooLarge)
        }

        print("cube LUT tests passed")
    }
}
