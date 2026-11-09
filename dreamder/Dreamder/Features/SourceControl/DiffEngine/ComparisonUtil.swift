import Foundation

nonisolated enum ComparisonPolicy: Sendable, Hashable, CaseIterable {
    case `default`
    case trimWhitespaces
    case ignoreWhitespaces
}

nonisolated enum ComparisonUtil {
    static let unimportantLineCharCount = 3
    static let maxBadLines = 3

    static func isSpaceEnterOrTab(_ unit: UInt16) -> Bool {
        unit == 10 || unit == 9 || unit == 32
    }

    static func isEquals(_ text1: DiffUnits, _ text2: DiffUnits, _ policy: ComparisonPolicy) -> Bool {
        switch policy {
        case .default:
            return text1 == text2
        case .trimWhitespaces:
            return trimmed(ArraySlice(text1)) == trimmed(ArraySlice(text2))
        case .ignoreWhitespaces:
            return equalsIgnoreWhitespaces(text1, text2)
        }
    }

    static func hashCode(_ text: DiffUnits, _ policy: ComparisonPolicy) -> Int {
        var hash: Int32 = 0
        switch policy {
        case .default:
            for unit in text {
                hash = 31 &* hash &+ Int32(unit)
            }
        case .trimWhitespaces:
            for unit in trimmed(ArraySlice(text)) {
                hash = 31 &* hash &+ Int32(unit)
            }
        case .ignoreWhitespaces:
            for unit in text where !isSpaceEnterOrTab(unit) {
                hash = 31 &* hash &+ Int32(unit)
            }
        }
        return Int(hash)
    }

    static func isEqualTexts(_ text1: DiffUnits, _ text2: DiffUnits, _ policy: ComparisonPolicy) -> Bool {
        switch policy {
        case .default:
            return text1 == text2
        case .trimWhitespaces:
            return equalsTrimWhitespacesPerLine(text1, text2)
        case .ignoreWhitespaces:
            return equalsIgnoreWhitespaces(text1, text2)
        }
    }

    static func isEqualTexts(_ text1: ArraySlice<UInt16>, _ text2: ArraySlice<UInt16>, _ policy: ComparisonPolicy) -> Bool {
        isEqualTexts(Array(text1), Array(text2), policy)
    }

    static func equalsIgnoreWhitespaces(_ text1: DiffUnits, _ text2: DiffUnits) -> Bool {
        let length1 = text1.count
        let length2 = text2.count
        var index1 = 0
        var index2 = 0
        while index1 < length1 && index2 < length2 {
            if text1[index1] == text2[index2] {
                index1 += 1
                index2 += 1
                continue
            }
            var skipped = false
            while index1 != length1 && isSpaceEnterOrTab(text1[index1]) {
                skipped = true
                index1 += 1
            }
            while index2 != length2 && isSpaceEnterOrTab(text2[index2]) {
                skipped = true
                index2 += 1
            }
            if !skipped { return false }
        }
        while index1 != length1 {
            if !isSpaceEnterOrTab(text1[index1]) { return false }
            index1 += 1
        }
        while index2 != length2 {
            if !isSpaceEnterOrTab(text2[index2]) { return false }
            index2 += 1
        }
        return true
    }

    static func equalsTrimWhitespacesPerLine(_ text1: DiffUnits, _ text2: DiffUnits) -> Bool {
        var index1 = 0
        var index2 = 0
        var isLastLine = false
        while !isLastLine {
            let (end1, last1) = lineEnd(text1, from: index1)
            let (end2, last2) = lineEnd(text2, from: index2)
            if last1 != last2 { return false }
            if trimmed(text1[index1..<end1]) != trimmed(text2[index2..<end2]) { return false }
            index1 = end1
            index2 = end2
            isLastLine = last1
        }
        return true
    }

    private static func lineEnd(_ text: DiffUnits, from index: Int) -> (end: Int, isLast: Bool) {
        var cursor = index
        while cursor < text.count {
            if text[cursor] == 10 { return (cursor + 1, false) }
            cursor += 1
        }
        return (text.count, true)
    }

    static func trimmed(_ text: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
        var start = text.startIndex
        var end = text.endIndex
        while start < end && isSpaceEnterOrTab(text[start]) { start += 1 }
        while start < end && isSpaceEnterOrTab(text[end - 1]) { end -= 1 }
        return text[start..<end]
    }
}
