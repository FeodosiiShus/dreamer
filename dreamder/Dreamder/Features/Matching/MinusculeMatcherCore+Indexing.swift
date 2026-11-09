import Foundation

nonisolated extension MinusculeMatcherCore {
    func indexOfWordStart(_ name: [UInt16], _ patternIndex: Int, _ startFrom: Int) -> Int {
        let patternUnit = pattern[patternIndex]
        if startFrom >= name.count
            || (isMixedCase && isLowerCase[patternIndex] && !(patternIndex > 0 && isWordSeparator[patternIndex - 1])) {
            return -1
        }
        var index = indexOfIgnoreCase(name, startFrom, patternIndex)
        let isSpecialSymbol = !MatchingCharacter.isLetterOrDigit(patternUnit)
        while index >= 0, !isSpecialSymbol, !NameUtilCore.isWordStart(name, index) {
            index = indexOfIgnoreCase(name, index + 1, patternIndex)
        }
        return index
    }

    func indexOfIgnoreCase(_ name: [UInt16], _ fromIndex: Int, _ patternIndex: Int) -> Int {
        let patternUnit = pattern[patternIndex]
        var index = max(fromIndex, 0)
        if patternUnit < 0x80 {
            let upper = toUpperCase[patternIndex]
            let lower = toLowerCase[patternIndex]
            while index < name.count {
                let unit = name[index]
                if unit == upper || unit == lower {
                    return index
                }
                index += 1
            }
            return -1
        }
        while index < name.count {
            if MatchingCharacter.equals(name[index], patternUnit, ignoreCase: true) {
                return index
            }
            index += 1
        }
        return -1
    }

    func indexOfInPattern(_ unit: UInt16, from start: Int) -> Int {
        var index = max(start, 0)
        while index < pattern.count {
            if MatchingCharacter.equals(unit, pattern[index], ignoreCase: true) {
                return index
            }
            index += 1
        }
        return -1
    }

    func indexOfAnyHardSeparator(_ name: [UInt16], start: Int, end: Int) -> Int {
        if hardSeparators.isEmpty {
            return -1
        }
        var index = max(start, 0)
        let limit = min(end, name.count)
        while index < limit {
            if hardSeparators.contains(name[index]) {
                return index
            }
            index += 1
        }
        return -1
    }

    func indexOfDot(_ name: [UInt16], start: Int, end: Int) -> Int {
        var index = max(start, 0)
        let limit = min(end, name.count)
        while index < limit {
            if name[index] == Self.dot {
                return index
            }
            index += 1
        }
        return -1
    }

    static func indexOf(_ text: [UInt16], _ unit: UInt16, from start: Int) -> Int {
        var index = max(start, 0)
        while index < text.count {
            if text[index] == unit {
                return index
            }
            index += 1
        }
        return -1
    }

    static func isWildcardUnit(_ unit: UInt16) -> Bool {
        unit == space || unit == star
    }

    static func isWordSeparatorUnit(_ unit: UInt16) -> Bool {
        MatchingCharacter.isWhitespace(unit)
            || unit == 0x5F || unit == 0x2D || unit == 0x3A || unit == 0x2B || unit == 0x2E
    }

    static func appendRange(_ ranges: [Range<Int>], from: Int, length: Int) -> [Range<Int>] {
        guard let last = ranges.last else {
            return [from..<(from + length)]
        }
        var result = ranges
        if last.lowerBound == from + length {
            result[result.count - 1] = from..<last.upperBound
        } else {
            result.append(from..<(from + length))
        }
        return result
    }
}
