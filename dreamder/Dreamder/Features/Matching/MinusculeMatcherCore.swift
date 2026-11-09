import Foundation

nonisolated struct MinusculeMatcherCore: Sendable {
    static let maxCamelHumpMatchingLength = 100

    private static let star: UInt16 = 0x2A
    private static let space: UInt16 = 0x20
    private static let dot: UInt16 = 0x2E

    let pattern: [UInt16]
    let mode: MatchingCaseMode
    private let hardSeparators: [UInt16]
    private let isLowerCase: [Bool]
    private let isUpperCase: [Bool]
    private let isWordSeparator: [Bool]
    private let toUpperCase: [UInt16]
    private let toLowerCase: [UInt16]
    private let isMixedCase: Bool
    private let hasSeparators: Bool
    private let hasDots: Bool
    private let meaningfulCharacters: [UInt16]

    init(pattern rawPattern: String, mode: MatchingCaseMode, hardSeparators: String) {
        var units = Array(rawPattern.utf16)
        if units.count >= 2, units[units.count - 2] == Self.star, units[units.count - 1] == Self.space {
            units.removeLast(2)
        }
        pattern = units
        self.mode = mode
        self.hardSeparators = Array(hardSeparators.utf16)

        var lower: [Bool] = []
        var upper: [Bool] = []
        var separators: [Bool] = []
        var toUpper: [UInt16] = []
        var toLower: [UInt16] = []
        var meaningful: [UInt16] = []
        lower.reserveCapacity(units.count)
        upper.reserveCapacity(units.count)
        separators.reserveCapacity(units.count)
        toUpper.reserveCapacity(units.count)
        toLower.reserveCapacity(units.count)
        meaningful.reserveCapacity(units.count * 2)

        var seenNonWildcard = false
        var seenLowerCase = false
        var seenUpperCaseNotImmediatelyAfterWildcard = false
        var seenDots = false
        var seenSeparators = false

        for unit in units {
            let separator = Self.isWordSeparatorUnit(unit)
            let isUpper = MatchingCharacter.isUpperCase(unit)
            let isLower = MatchingCharacter.isLowerCase(unit)
            let upperUnit = MatchingCharacter.uppercased(unit)
            let lowerUnit = MatchingCharacter.lowercased(unit)
            if isLower {
                seenLowerCase = true
            }
            if unit == Self.dot {
                seenDots = true
            }
            if seenNonWildcard && isUpper {
                seenUpperCaseNotImmediatelyAfterWildcard = true
            }
            if !Self.isWildcardUnit(unit) {
                seenNonWildcard = true
                meaningful.append(lowerUnit)
                meaningful.append(upperUnit)
            }
            if seenNonWildcard && separator {
                seenSeparators = true
            }
            separators.append(separator)
            upper.append(isUpper)
            lower.append(isLower)
            toUpper.append(upperUnit)
            toLower.append(lowerUnit)
        }

        isLowerCase = lower
        isUpperCase = upper
        isWordSeparator = separators
        toUpperCase = toUpper
        toLowerCase = toLower
        hasDots = seenDots
        isMixedCase = seenLowerCase && seenUpperCaseNotImmediatelyAfterWildcard
        hasSeparators = seenSeparators
        meaningfulCharacters = meaningful
    }

    func match(_ name: [UInt16]) -> [Range<Int>]? {
        if name.count < meaningfulCharacters.count / 2 {
            return nil
        }
        if pattern.count > Self.maxCamelHumpMatchingLength {
            return matchBySubstring(name)
        }
        if !nameContainsAllMeaningfulCharactersInOrder(name) {
            return nil
        }
        guard let reversed = matchWildcards(name, 0, 0) else { return nil }
        return Array(reversed.reversed())
    }

    func matchingDegree(_ name: [UInt16], valueStartCaseMatch: Bool, fragments: [Range<Int>]?) -> Int {
        guard let fragments else { return Int.min }
        guard let first = fragments.first, let last = fragments.last else { return 0 }
        if fragments.contains(where: { $0.lowerBound < 0 || $0.upperBound > name.count || $0.isEmpty }) {
            return Int.min
        }

        let startMatch = first.lowerBound == 0
        let valuedStartMatch = startMatch && valueStartCaseMatch

        var matchingCase = 0
        var p = -1
        var skippedHumps = 0
        var nextHumpStart = 0
        var humpStartMatchedUpperCase = false

        for (rangeIndex, range) in fragments.enumerated() {
            var i = range.lowerBound
            while i < range.upperBound {
                let afterGap = i == range.lowerBound && rangeIndex != 0
                var isHumpStart = false
                while nextHumpStart <= i {
                    if nextHumpStart == i {
                        isHumpStart = true
                    } else if afterGap {
                        skippedHumps += 1
                    }
                    if nextHumpStart < name.count && MatchingCharacter.isDigit(name[nextHumpStart]) {
                        nextHumpStart += 1
                    } else {
                        nextHumpStart = NameUtilCore.nextWord(name, nextHumpStart)
                    }
                }

                let c = name[i]
                p = indexOfInPattern(c, from: p + 1)
                if p < 0 {
                    break
                }

                if isHumpStart {
                    humpStartMatchedUpperCase = c == pattern[p] && isUpperCase[p]
                }

                matchingCase += evaluateCaseMatching(
                    valuedStartMatch: valuedStartMatch,
                    patternIndex: p,
                    humpStartMatchedUpperCase: humpStartMatchedUpperCase,
                    nameIndex: i,
                    afterGap: afterGap,
                    isHumpStart: isHumpStart,
                    nameChar: c
                )
                i += 1
            }
        }

        let startIndex = first.lowerBound
        let afterSeparator = indexOfAnyHardSeparator(name, start: 0, end: startIndex) >= 0
        let wordStart = startIndex == 0
            || (NameUtilCore.isWordStart(name, startIndex) && !NameUtilCore.isWordStart(name, startIndex - 1))
        let finalMatch = last.upperBound == name.count

        var score = wordStart ? 1000 : 0
        score += matchingCase
        score -= fragments.count
        score -= skippedHumps * 10
        score += afterSeparator ? 0 : 2
        score += startMatch ? 1 : 0
        score += finalMatch ? 1 : 0
        return score
    }

    private func evaluateCaseMatching(
        valuedStartMatch: Bool,
        patternIndex: Int,
        humpStartMatchedUpperCase: Bool,
        nameIndex: Int,
        afterGap: Bool,
        isHumpStart: Bool,
        nameChar: UInt16
    ) -> Int {
        if afterGap && isHumpStart && isLowerCase[patternIndex] {
            return -10
        }
        if nameChar == pattern[patternIndex] {
            if isUpperCase[patternIndex] {
                return 50
            }
            if nameIndex == 0 && valuedStartMatch {
                return 150
            }
            if isHumpStart {
                return 1
            }
            return 0
        }
        if isHumpStart {
            return -1
        }
        if isLowerCase[patternIndex] && humpStartMatchedUpperCase {
            return -1
        }
        return 0
    }

    private func nameContainsAllMeaningfulCharactersInOrder(_ name: [UInt16]) -> Bool {
        var meaningfulIndex = 0
        var nameIndex = 0
        while meaningfulIndex + 1 < meaningfulCharacters.count {
            if nameIndex >= name.count {
                return false
            }
            let c1 = meaningfulCharacters[meaningfulIndex]
            let indexOf1 = Self.indexOf(name, c1, from: nameIndex)
            if indexOf1 == nameIndex {
                nameIndex = indexOf1 + 1
            } else {
                let c2 = meaningfulCharacters[meaningfulIndex + 1]
                if c1 == c2 {
                    if indexOf1 < 0 {
                        return false
                    }
                    nameIndex = indexOf1 + 1
                } else {
                    let indexOf2 = Self.indexOf(name, c2, from: nameIndex)
                    if indexOf1 >= 0 && indexOf2 >= 0 {
                        nameIndex = min(indexOf1, indexOf2) + 1
                    } else if indexOf1 >= 0 {
                        nameIndex = indexOf1 + 1
                    } else if indexOf2 >= 0 {
                        nameIndex = indexOf2 + 1
                    } else {
                        return false
                    }
                }
            }
            meaningfulIndex += 2
        }
        return true
    }

    private func matchBySubstring(_ name: [UInt16]) -> [Range<Int>]? {
        let meaningfulCount = meaningfulCharacters.count / 2
        if isPatternChar(0, Self.star) {
            var i = 0
            while i <= name.count - meaningfulCount {
                let length = meaningfulCharactersMatchLength(name, at: i)
                if length != 0 {
                    return [i..<(i + length)]
                }
                i += 1
            }
            return nil
        }
        let length = meaningfulCharactersMatchLength(name, at: 0)
        return length != 0 ? [0..<length] : nil
    }

    private func meaningfulCharactersMatchLength(_ name: [UInt16], at nameIndex: Int) -> Int {
        var meaningfulIndex = 0
        var namePosition = nameIndex
        while namePosition < name.count && meaningfulIndex + 1 < meaningfulCharacters.count {
            let c = name[namePosition]
            if c == meaningfulCharacters[meaningfulIndex] || c == meaningfulCharacters[meaningfulIndex + 1] {
                meaningfulIndex += 2
                namePosition += 1
            } else if Self.isWildcardUnit(c) {
                namePosition += 1
            } else {
                return 0
            }
        }
        return namePosition - nameIndex
    }

    private func matchWildcards(_ name: [UInt16], _ startPatternIndex: Int, _ nameIndex: Int) -> [Range<Int>]? {
        if nameIndex < 0 {
            return nil
        }
        if !isWildcard(startPatternIndex) {
            return startPatternIndex == pattern.count ? [] : matchFragment(name, startPatternIndex, nameIndex)
        }

        var patternIndex = startPatternIndex
        repeat {
            patternIndex += 1
        } while isWildcard(patternIndex)

        if patternIndex == pattern.count {
            if isTrailingSpacePattern && nameIndex != name.count
                && (patternIndex < 2 || !isUpperCaseOrDigit(patternIndex - 2)) {
                let spaceIndex = Self.indexOf(name, Self.space, from: nameIndex)
                return spaceIndex >= 0 ? [spaceIndex..<(spaceIndex + 1)] : nil
            }
            return []
        }

        return matchSkippingWords(
            name,
            patternIndex,
            findNextPatternCharacterOccurrence(name, nameIndex, patternIndex),
            allowSpecialCharacters: true
        )
    }

    private var isTrailingSpacePattern: Bool {
        isPatternChar(pattern.count - 1, Self.space)
    }

    private func isUpperCaseOrDigit(_ patternIndex: Int) -> Bool {
        isUpperCase[patternIndex] || MatchingCharacter.isDigit(pattern[patternIndex])
    }

    private func matchSkippingWords(
        _ name: [UInt16],
        _ patternIndex: Int,
        _ startNameIndex: Int,
        allowSpecialCharacters: Bool
    ) -> [Range<Int>]? {
        var nameIndex = startNameIndex
        var maxFoundLength = 0
        while nameIndex >= 0 {
            let fragmentLength = seemsLikeFragmentStart(name, patternIndex, nameIndex)
                ? maxMatchingFragment(name, patternIndex, nameIndex)
                : 0

            if fragmentLength > maxFoundLength
                || (nameIndex + fragmentLength == name.count && isTrailingSpacePattern) {
                if !isMiddleMatch(name, patternIndex, nameIndex) {
                    maxFoundLength = fragmentLength
                }
                if let ranges = matchInsideFragment(name, patternIndex, nameIndex, fragmentLength) {
                    return ranges
                }
            }
            let next = findNextPatternCharacterOccurrence(name, nameIndex + 1, patternIndex)
            nameIndex = allowSpecialCharacters
                ? next
                : checkForSpecialCharacters(name, nameIndex + 1, next, patternIndex)
        }
        return nil
    }

    private func findNextPatternCharacterOccurrence(_ name: [UInt16], _ startAt: Int, _ patternIndex: Int) -> Int {
        if !isPatternChar(patternIndex - 1, Self.star) && !isWordSeparator[patternIndex] {
            return indexOfWordStart(name, patternIndex, startAt)
        }
        return indexOfIgnoreCase(name, startAt, patternIndex)
    }

    private func checkForSpecialCharacters(_ name: [UInt16], _ start: Int, _ end: Int, _ patternIndex: Int) -> Int {
        if end < 0 {
            return -1
        }
        if !hasSeparators && !isMixedCase && indexOfAnyHardSeparator(name, start: start, end: end) != -1 {
            return -1
        }
        if hasDots && !isPatternChar(patternIndex - 1, Self.dot) && indexOfDot(name, start: start, end: end) != -1 {
            return -1
        }
        return end
    }

    private func seemsLikeFragmentStart(_ name: [UInt16], _ patternIndex: Int, _ nextOccurrence: Int) -> Bool {
        !isUpperCase[patternIndex]
            || MatchingCharacter.isUpperCase(name[nextOccurrence])
            || NameUtilCore.isWordStart(name, nextOccurrence)
            || (!isMixedCase && mode != .matchCase)
    }

    private func charEquals(_ patternChar: UInt16, _ patternIndex: Int, _ c: UInt16, ignoreCase: Bool) -> Bool {
        patternChar == c || (ignoreCase && (toLowerCase[patternIndex] == c || toUpperCase[patternIndex] == c))
    }

    private func matchFragment(_ name: [UInt16], _ patternIndex: Int, _ nameIndex: Int) -> [Range<Int>]? {
        let fragmentLength = maxMatchingFragment(name, patternIndex, nameIndex)
        return fragmentLength == 0 ? nil : matchInsideFragment(name, patternIndex, nameIndex, fragmentLength)
    }

    private func maxMatchingFragment(_ name: [UInt16], _ patternIndex: Int, _ nameIndex: Int) -> Int {
        if !isFirstCharMatching(name, nameIndex, patternIndex) {
            return 0
        }
        var i = 1
        let ignoreCase = mode != .matchCase
        while nameIndex + i < name.count && patternIndex + i < pattern.count {
            let nameChar = name[nameIndex + i]
            if !charEquals(pattern[patternIndex + i], patternIndex + i, nameChar, ignoreCase: ignoreCase) {
                if isSkippingDigitBetweenPatternDigits(patternIndex + i, nameChar) {
                    return 0
                }
                break
            }
            i += 1
        }
        return i
    }

    private func isSkippingDigitBetweenPatternDigits(_ patternIndex: Int, _ nameChar: UInt16) -> Bool {
        MatchingCharacter.isDigit(pattern[patternIndex])
            && MatchingCharacter.isDigit(pattern[patternIndex - 1])
            && MatchingCharacter.isDigit(nameChar)
    }

    private func matchInsideFragment(
        _ name: [UInt16],
        _ patternIndex: Int,
        _ nameIndex: Int,
        _ fragmentLength: Int
    ) -> [Range<Int>]? {
        let minFragment = isMiddleMatch(name, patternIndex, nameIndex) ? 3 : 1
        if let camelHumpRanges = improveCamelHumps(name, patternIndex, nameIndex, fragmentLength, minFragment) {
            return camelHumpRanges
        }
        return findLongestMatchingPrefix(name, patternIndex, nameIndex, fragmentLength, minFragment)
    }

    private func isMiddleMatch(_ name: [UInt16], _ patternIndex: Int, _ nameIndex: Int) -> Bool {
        guard nameIndex >= 0, nameIndex < name.count else { return false }
        return isPatternChar(patternIndex - 1, Self.star)
            && !isWildcard(patternIndex + 1)
            && MatchingCharacter.isLetterOrDigit(name[nameIndex])
            && !NameUtilCore.isWordStart(name, nameIndex)
    }

    private func findLongestMatchingPrefix(
        _ name: [UInt16],
        _ patternIndex: Int,
        _ nameIndex: Int,
        _ fragmentLength: Int,
        _ minFragment: Int
    ) -> [Range<Int>]? {
        if patternIndex + fragmentLength >= pattern.count {
            return [nameIndex..<(nameIndex + fragmentLength)]
        }

        var i = fragmentLength
        while i >= minFragment || (i > 0 && isWildcard(patternIndex + i)) {
            let ranges: [Range<Int>]?
            if isWildcard(patternIndex + i) {
                ranges = matchWildcards(name, patternIndex + i, nameIndex + i)
            } else {
                var nextOccurrence = findNextPatternCharacterOccurrence(name, nameIndex + i + 1, patternIndex + i)
                nextOccurrence = checkForSpecialCharacters(name, nameIndex + i, nextOccurrence, patternIndex + i)
                if nextOccurrence >= 0 {
                    ranges = matchSkippingWords(name, patternIndex + i, nextOccurrence, allowSpecialCharacters: false)
                } else {
                    ranges = nil
                }
            }
            if let ranges {
                return Self.appendRange(ranges, from: nameIndex, length: i)
            }
            i -= 1
        }
        return nil
    }

    private func improveCamelHumps(
        _ name: [UInt16],
        _ patternIndex: Int,
        _ nameIndex: Int,
        _ maxFragment: Int,
        _ minFragment: Int
    ) -> [Range<Int>]? {
        var i = minFragment
        while i < maxFragment {
            if isUpperCase[patternIndex + i] && pattern[patternIndex + i] != name[nameIndex + i] {
                let nextWordStart = indexOfWordStart(name, patternIndex + i, nameIndex + i)
                if let ranges = matchWildcards(name, patternIndex + i, nextWordStart) {
                    return Self.appendRange(ranges, from: nameIndex, length: i)
                }
            }
            i += 1
        }
        return nil
    }

    private func isFirstCharMatching(_ name: [UInt16], _ nameIndex: Int, _ patternIndex: Int) -> Bool {
        let ignoreCase = mode != .matchCase
        if !charEquals(pattern[patternIndex], patternIndex, name[nameIndex], ignoreCase: ignoreCase) {
            return false
        }
        let firstLetterCaseMismatch = mode == .firstLetter
            && (patternIndex == 0 || (patternIndex == 1 && isWildcard(0)))
            && hasCase(patternIndex)
            && isUpperCase[patternIndex] != MatchingCharacter.isUpperCase(name[0])
        return !firstLetterCaseMismatch
    }

    private func hasCase(_ patternIndex: Int) -> Bool {
        isUpperCase[patternIndex] || isLowerCase[patternIndex]
    }

    private func isWildcard(_ patternIndex: Int) -> Bool {
        patternIndex >= 0 && patternIndex < pattern.count && Self.isWildcardUnit(pattern[patternIndex])
    }

    private func isPatternChar(_ patternIndex: Int, _ c: UInt16) -> Bool {
        patternIndex >= 0 && patternIndex < pattern.count && pattern[patternIndex] == c
    }

    private func indexOfWordStart(_ name: [UInt16], _ patternIndex: Int, _ startFrom: Int) -> Int {
        let p = pattern[patternIndex]
        if startFrom >= name.count
            || (isMixedCase && isLowerCase[patternIndex] && !(patternIndex > 0 && isWordSeparator[patternIndex - 1])) {
            return -1
        }
        var i = indexOfIgnoreCase(name, startFrom, patternIndex)
        let isSpecialSymbol = !MatchingCharacter.isLetterOrDigit(p)
        while i >= 0, !isSpecialSymbol, !NameUtilCore.isWordStart(name, i) {
            i = indexOfIgnoreCase(name, i + 1, patternIndex)
        }
        return i
    }

    private func indexOfIgnoreCase(_ name: [UInt16], _ fromIndex: Int, _ patternIndex: Int) -> Int {
        let p = pattern[patternIndex]
        var i = max(fromIndex, 0)
        if p < 0x80 {
            let upper = toUpperCase[patternIndex]
            let lower = toLowerCase[patternIndex]
            while i < name.count {
                let c = name[i]
                if c == upper || c == lower {
                    return i
                }
                i += 1
            }
            return -1
        }
        while i < name.count {
            if MatchingCharacter.equals(name[i], p, ignoreCase: true) {
                return i
            }
            i += 1
        }
        return -1
    }

    private func indexOfInPattern(_ c: UInt16, from start: Int) -> Int {
        var i = max(start, 0)
        while i < pattern.count {
            if MatchingCharacter.equals(c, pattern[i], ignoreCase: true) {
                return i
            }
            i += 1
        }
        return -1
    }

    private func indexOfAnyHardSeparator(_ name: [UInt16], start: Int, end: Int) -> Int {
        if hardSeparators.isEmpty {
            return -1
        }
        var i = max(start, 0)
        let limit = min(end, name.count)
        while i < limit {
            if hardSeparators.contains(name[i]) {
                return i
            }
            i += 1
        }
        return -1
    }

    private func indexOfDot(_ name: [UInt16], start: Int, end: Int) -> Int {
        var i = max(start, 0)
        let limit = min(end, name.count)
        while i < limit {
            if name[i] == Self.dot {
                return i
            }
            i += 1
        }
        return -1
    }

    private static func indexOf(_ text: [UInt16], _ c: UInt16, from start: Int) -> Int {
        var i = max(start, 0)
        while i < text.count {
            if text[i] == c {
                return i
            }
            i += 1
        }
        return -1
    }

    private static func isWildcardUnit(_ c: UInt16) -> Bool {
        c == space || c == star
    }

    private static func isWordSeparatorUnit(_ c: UInt16) -> Bool {
        MatchingCharacter.isWhitespace(c) || c == 0x5F || c == 0x2D || c == 0x3A || c == 0x2B || c == 0x2E
    }

    private static func appendRange(_ ranges: [Range<Int>], from: Int, length: Int) -> [Range<Int>] {
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
