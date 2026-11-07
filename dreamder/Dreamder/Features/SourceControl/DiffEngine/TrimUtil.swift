import Foundation

nonisolated enum TrimUtil {
    static func isPunctuation(_ code: Int) -> Bool {
        if code == 95 { return false }
        return (code >= 33 && code <= 47)
            || (code >= 58 && code <= 64)
            || (code >= 91 && code <= 96)
            || (code >= 123 && code <= 126)
    }

    static func isWhiteSpaceCodePoint(_ code: Int) -> Bool {
        code < 128 && code >= 0 && ComparisonUtil.isSpaceEnterOrTab(UInt16(code))
    }

    static func isAlpha(_ code: Int) -> Bool {
        if isWhiteSpaceCodePoint(code) { return false }
        return !isPunctuation(code)
    }

    static func isContinuousScript(_ code: Int) -> Bool {
        if code < 128 { return false }
        guard let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: code)) else { return true }
        if scalar.properties.generalCategory == .decimalNumber { return false }
        if code > 0xFFFF { return true }
        if scalar.properties.isIdeographic { return true }
        if !scalar.properties.isAlphabetic { return true }
        return isInRanges(code, hiraganaRanges)
            || isInRanges(code, katakanaRanges)
            || isInRanges(code, thaiRanges)
            || isInRanges(code, javaneseRanges)
    }

    private static func isInRanges(_ code: Int, _ ranges: [ClosedRange<Int>]) -> Bool {
        for range in ranges where range.contains(code) {
            return true
        }
        return false
    }

    private static let hiraganaRanges: [ClosedRange<Int>] = [
        0x3041...0x3096, 0x309d...0x309e, 0x309f...0x309f, 0x1b001...0x1b11f, 0x1b132...0x1b132, 0x1b150...0x1b152, 0x1f200...0x1f200
    ]

    private static let katakanaRanges: [ClosedRange<Int>] = [
        0x30a1...0x30fa, 0x30fd...0x30fe, 0x30ff...0x30ff, 0x31f0...0x31ff, 0x32d0...0x32fe, 0x3300...0x3357,
        0xff66...0xff6f, 0xff71...0xff9d, 0x1aff0...0x1aff3, 0x1aff5...0x1affb, 0x1affd...0x1affe, 0x1b000...0x1b000,
        0x1b120...0x1b122, 0x1b155...0x1b155, 0x1b164...0x1b167
    ]

    private static let thaiRanges: [ClosedRange<Int>] = [
        0x0e01...0x0e30, 0x0e31...0x0e31, 0x0e32...0x0e33, 0x0e34...0x0e3a, 0x0e40...0x0e45, 0x0e46...0x0e46,
        0x0e47...0x0e4e, 0x0e4f...0x0e4f, 0x0e50...0x0e59, 0x0e5a...0x0e5b
    ]

    private static let javaneseRanges: [ClosedRange<Int>] = [
        0xa980...0xa982, 0xa983...0xa983, 0xa984...0xa9b2, 0xa9b3...0xa9b3, 0xa9b4...0xa9b5, 0xa9b6...0xa9b9,
        0xa9ba...0xa9bb, 0xa9bc...0xa9bd, 0xa9be...0xa9c0, 0xa9c1...0xa9cd, 0xa9d0...0xa9d9, 0xa9de...0xa9df
    ]

    static func codePointAt(_ text: DiffUnits, _ index: Int) -> Int {
        let high = text[index]
        if high >= 0xD800 && high <= 0xDBFF && index + 1 < text.count {
            let low = text[index + 1]
            if low >= 0xDC00 && low <= 0xDFFF {
                return ((Int(high) - 0xD800) << 10 | (Int(low) - 0xDC00)) + 0x10000
            }
        }
        return Int(high)
    }

    static func charCount(_ codePoint: Int) -> Int {
        codePoint >= 0x10000 ? 2 : 1
    }

    static func trimStart(_ text: DiffUnits, _ start: Int, _ end: Int) -> Int {
        var cursor = start
        while cursor < end && ComparisonUtil.isSpaceEnterOrTab(text[cursor]) {
            cursor += 1
        }
        return cursor
    }

    static func trimEnd(_ text: DiffUnits, _ start: Int, _ end: Int) -> Int {
        var cursor = end
        while start < cursor && ComparisonUtil.isSpaceEnterOrTab(text[cursor - 1]) {
            cursor -= 1
        }
        return cursor
    }

    static func trim(_ text: DiffUnits, _ start: Int, _ end: Int) -> (start: Int, end: Int) {
        let newStart = trimStart(text, start, end)
        let newEnd = trimEnd(text, newStart, end)
        return (newStart, newEnd)
    }

    static func trim(_ text1: DiffUnits, _ text2: DiffUnits, _ range: DiffRange) -> DiffRange {
        let start1 = trimStart(text1, range.start1, range.end1)
        let end1 = trimEnd(text1, start1, range.end1)
        let start2 = trimStart(text2, range.start2, range.end2)
        let end2 = trimEnd(text2, start2, range.end2)
        return DiffRange(start1, end1, start2, end2)
    }

    static func trim(_ text1: DiffUnits, _ text2: DiffUnits, _ text3: DiffUnits, _ range: MergeRange) -> MergeRange {
        let start1 = trimStart(text1, range.start1, range.end1)
        let end1 = trimEnd(text1, start1, range.end1)
        let start2 = trimStart(text2, range.start2, range.end2)
        let end2 = trimEnd(text2, start2, range.end2)
        let start3 = trimStart(text3, range.start3, range.end3)
        let end3 = trimEnd(text3, start3, range.end3)
        return MergeRange(start1, end1, start2, end2, start3, end3)
    }

    static func expandForward(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int, _ equals: (Int, Int) -> Bool) -> Int {
        var cursor1 = start1
        var cursor2 = start2
        while cursor1 < end1 && cursor2 < end2 {
            if !equals(cursor1, cursor2) { break }
            cursor1 += 1
            cursor2 += 1
        }
        return cursor1 - start1
    }

    static func expandBackward(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int, _ equals: (Int, Int) -> Bool) -> Int {
        var cursor1 = end1
        var cursor2 = end2
        while start1 < cursor1 && start2 < cursor2 {
            if !equals(cursor1 - 1, cursor2 - 1) { break }
            cursor1 -= 1
            cursor2 -= 1
        }
        return end1 - cursor1
    }

    static func expand(_ start1: Int, _ start2: Int, _ end1: Int, _ end2: Int, _ equals: (Int, Int) -> Bool) -> DiffRange {
        let forward = expandForward(start1, start2, end1, end2, equals)
        let newStart1 = start1 + forward
        let newStart2 = start2 + forward
        let backward = expandBackward(newStart1, newStart2, end1, end2, equals)
        return DiffRange(newStart1, end1 - backward, newStart2, end2 - backward)
    }

    static func expandWhitespacesForward(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ start1: Int,
        _ start2: Int,
        _ end1: Int,
        _ end2: Int
    ) -> Int {
        var cursor1 = start1
        var cursor2 = start2
        while cursor1 < end1 && cursor2 < end2 {
            if text1[cursor1] != text2[cursor2] { break }
            if !ComparisonUtil.isSpaceEnterOrTab(text1[cursor1]) { break }
            cursor1 += 1
            cursor2 += 1
        }
        return cursor1 - start1
    }

    static func expandWhitespacesBackward(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ start1: Int,
        _ start2: Int,
        _ end1: Int,
        _ end2: Int
    ) -> Int {
        var cursor1 = end1
        var cursor2 = end2
        while start1 < cursor1 && start2 < cursor2 {
            if text1[cursor1 - 1] != text2[cursor2 - 1] { break }
            if !ComparisonUtil.isSpaceEnterOrTab(text1[cursor1 - 1]) { break }
            cursor1 -= 1
            cursor2 -= 1
        }
        return end1 - cursor1
    }

    static func expandWhitespaces(_ text1: DiffUnits, _ text2: DiffUnits, _ range: DiffRange) -> DiffRange {
        let forward = expandWhitespacesForward(text1, text2, range.start1, range.start2, range.end1, range.end2)
        let start1 = range.start1 + forward
        let start2 = range.start2 + forward
        let backward = expandWhitespacesBackward(text1, text2, start1, start2, range.end1, range.end2)
        return DiffRange(start1, range.end1 - backward, start2, range.end2 - backward)
    }

    static func expandWhitespacesForward(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits,
        _ range: MergeRange,
        endShift: Int
    ) -> Int {
        var cursor1 = range.start1
        var cursor2 = range.start2
        var cursor3 = range.start3
        let end1 = range.end1 - endShift
        let end2 = range.end2 - endShift
        let end3 = range.end3 - endShift
        while cursor1 < end1 && cursor2 < end2 && cursor3 < end3 {
            if text1[cursor1] != text2[cursor2] { break }
            if text1[cursor1] != text3[cursor3] { break }
            if !ComparisonUtil.isSpaceEnterOrTab(text1[cursor1]) { break }
            cursor1 += 1
            cursor2 += 1
            cursor3 += 1
        }
        return cursor1 - range.start1
    }

    static func expandWhitespacesBackward(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits,
        _ range: MergeRange
    ) -> Int {
        var cursor1 = range.end1
        var cursor2 = range.end2
        var cursor3 = range.end3
        while range.start1 < cursor1 && range.start2 < cursor2 && range.start3 < cursor3 {
            if text1[cursor1 - 1] != text2[cursor2 - 1] { break }
            if text1[cursor1 - 1] != text3[cursor3 - 1] { break }
            if !ComparisonUtil.isSpaceEnterOrTab(text1[cursor1 - 1]) { break }
            cursor1 -= 1
            cursor2 -= 1
            cursor3 -= 1
        }
        return range.end1 - cursor1
    }

    static func expandWhitespaces(_ text1: DiffUnits, _ text2: DiffUnits, _ text3: DiffUnits, _ range: MergeRange) -> MergeRange {
        let forward = expandWhitespacesForward(text1, text2, text3, range, endShift: 0)
        let shifted = MergeRange(
            range.start1 + forward,
            range.end1,
            range.start2 + forward,
            range.end2,
            range.start3 + forward,
            range.end3
        )
        let backward = expandWhitespacesBackward(text1, text2, text3, shifted)
        return MergeRange(
            shifted.start1,
            range.end1 - backward,
            shifted.start2,
            range.end2 - backward,
            shifted.start3,
            range.end3 - backward
        )
    }

    static func isEquals(_ text1: DiffUnits, _ text2: DiffUnits, _ range: DiffRange) -> Bool {
        text1[range.start1..<range.end1] == text2[range.start2..<range.end2]
    }

    static func isEqualsIgnoreWhitespaces(_ text1: DiffUnits, _ text2: DiffUnits, _ range: DiffRange) -> Bool {
        ComparisonUtil.equalsIgnoreWhitespaces(
            Array(text1[range.start1..<range.end1]),
            Array(text2[range.start2..<range.end2])
        )
    }

    static func isEquals(_ text1: DiffUnits, _ text2: DiffUnits, _ text3: DiffUnits, _ range: MergeRange) -> Bool {
        let sequence1 = text1[range.start1..<range.end1]
        let sequence2 = text2[range.start2..<range.end2]
        let sequence3 = text3[range.start3..<range.end3]
        return sequence2 == sequence1 && sequence2 == sequence3
    }

    static func isEqualsIgnoreWhitespaces(
        _ text1: DiffUnits,
        _ text2: DiffUnits,
        _ text3: DiffUnits,
        _ range: MergeRange
    ) -> Bool {
        let sequence1 = Array(text1[range.start1..<range.end1])
        let sequence2 = Array(text2[range.start2..<range.end2])
        let sequence3 = Array(text3[range.start3..<range.end3])
        return ComparisonUtil.equalsIgnoreWhitespaces(sequence2, sequence1)
            && ComparisonUtil.equalsIgnoreWhitespaces(sequence2, sequence3)
    }

    static func trimExpand(
        _ start1: Int,
        _ start2: Int,
        _ end1: Int,
        _ end2: Int,
        equals: (Int, Int) -> Bool,
        ignored1: (Int) -> Bool,
        ignored2: (Int) -> Bool
    ) -> DiffRange {
        var cursorStart1 = start1
        var cursorStart2 = start2
        while cursorStart1 < end1 && cursorStart2 < end2 {
            if equals(cursorStart1, cursorStart2) {
                cursorStart1 += 1
                cursorStart2 += 1
                continue
            }
            var skipped = false
            if ignored1(cursorStart1) {
                skipped = true
                cursorStart1 += 1
            }
            if ignored2(cursorStart2) {
                skipped = true
                cursorStart2 += 1
            }
            if !skipped { break }
        }
        while cursorStart1 < end1 && ignored1(cursorStart1) { cursorStart1 += 1 }
        while cursorStart2 < end2 && ignored2(cursorStart2) { cursorStart2 += 1 }

        var cursorEnd1 = end1
        var cursorEnd2 = end2
        while cursorStart1 < cursorEnd1 && cursorStart2 < cursorEnd2 {
            if equals(cursorEnd1 - 1, cursorEnd2 - 1) {
                cursorEnd1 -= 1
                cursorEnd2 -= 1
                continue
            }
            var skipped = false
            if ignored1(cursorEnd1 - 1) {
                skipped = true
                cursorEnd1 -= 1
            }
            if ignored2(cursorEnd2 - 1) {
                skipped = true
                cursorEnd2 -= 1
            }
            if !skipped { break }
        }
        while cursorStart1 < cursorEnd1 && ignored1(cursorEnd1 - 1) { cursorEnd1 -= 1 }
        while cursorStart2 < cursorEnd2 && ignored2(cursorEnd2 - 1) { cursorEnd2 -= 1 }

        return DiffRange(cursorStart1, cursorEnd1, cursorStart2, cursorEnd2)
    }
}
