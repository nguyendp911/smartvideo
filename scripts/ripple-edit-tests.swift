import Foundation

@main
struct RippleEditTests {
    static func near(_ a: Double, _ b: Double, tolerance: Double = 0.0005) {
        precondition(a.isFinite && abs(a - b) < tolerance,
                     "Expected \(b) got \(a)")
    }

    static func main() {
        let m = RippleMath.self
        // Cut window: seconds 10 ... 14 (length 4).

        // Before the cut: untouched.
        let before = m.range(start: 2, end: 6, cutStart: 10, cutEnd: 14)!
        near(before.start, 2); near(before.end, 6); near(before.headTrim, 0)

        // Touching the start of the cut: untouched.
        let touching = m.range(start: 6, end: 10, cutStart: 10, cutEnd: 14)!
        near(touching.end, 10)

        // After the cut: moves left by 4.
        let after = m.range(start: 20, end: 25, cutStart: 10, cutEnd: 14)!
        near(after.start, 16); near(after.end, 21)
        let rightAfter = m.range(start: 14, end: 15, cutStart: 10, cutEnd: 14)!
        near(rightAfter.start, 10); near(rightAfter.end, 11)

        // Fully inside the cut: removed.
        precondition(m.range(start: 11, end: 13, cutStart: 10, cutEnd: 14) == nil)
        precondition(m.range(start: 10, end: 14, cutStart: 10, cutEnd: 14) == nil)

        // Overlaps the beginning of the cut: tail is cut off.
        let leftOverlap = m.range(start: 8, end: 12, cutStart: 10, cutEnd: 14)!
        near(leftOverlap.start, 8); near(leftOverlap.end, 10)

        // Overlaps the end of the cut: head is trimmed and moved to the cut.
        let rightOverlap = m.range(start: 12, end: 20, cutStart: 10, cutEnd: 14)!
        near(rightOverlap.start, 10); near(rightOverlap.end, 16)
        near(rightOverlap.headTrim, 2)

        // Straddles the whole cut.
        let shrink = m.range(start: 5, end: 20, cutStart: 10, cutEnd: 14,
                             straddle: .shrink)!
        near(shrink.start, 5); near(shrink.end, 16); near(shrink.headTrim, 0)
        let head = m.range(start: 5, end: 20, cutStart: 10, cutEnd: 14,
                           straddle: .keepHead)!
        near(head.start, 5); near(head.end, 10)

        // Too-short leftovers are dropped; invalid input never crashes.
        precondition(m.range(start: 9.98, end: 12, cutStart: 10, cutEnd: 14) == nil)
        precondition(m.range(start: .nan, end: 5, cutStart: 0, cutEnd: 1) == nil)
        precondition(m.range(start: 5, end: 3, cutStart: 0, cutEnd: 1) == nil)
        let noCut = m.range(start: 5, end: 8, cutStart: 7, cutEnd: 7)!
        near(noCut.start, 5); near(noCut.end, 8)

        // Single positions.
        near(m.point(3, cutStart: 10, cutEnd: 14), 3)
        near(m.point(10, cutStart: 10, cutEnd: 14), 10)
        near(m.point(12, cutStart: 10, cutEnd: 14), 10)
        near(m.point(14, cutStart: 10, cutEnd: 14), 10)
        near(m.point(30, cutStart: 10, cutEnd: 14), 26)

        // Keyframe remap: 8 s item that lost its first 2 s and now lasts 6 s.
        near(m.remapProgress(0.5, oldDuration: 8, headTrim: 2, newDuration: 6)!,
             2.0 / 6.0)
        near(m.remapProgress(1, oldDuration: 8, headTrim: 2, newDuration: 6)!, 1)
        precondition(m.remapProgress(0.1, oldDuration: 8, headTrim: 2,
                                     newDuration: 6) == nil)
        // Tail cut: 8 s item shortened to 4 s keeps first half of frames only.
        near(m.remapProgress(0.25, oldDuration: 8, headTrim: 0, newDuration: 4)!,
             0.5)
        precondition(m.remapProgress(0.75, oldDuration: 8, headTrim: 0,
                                     newDuration: 4) == nil)

        // Sequential ripple deletes keep gaps consistent: deleting 10..14 then
        // 5..7 moves an item at 20 to 14.
        let first = m.range(start: 20, end: 22, cutStart: 10, cutEnd: 14)!
        let second = m.range(start: first.start, end: first.end,
                             cutStart: 5, cutEnd: 7)!
        near(second.start, 14)

        print("ripple edit tests passed")
    }
}
