import Foundation

nonisolated extension MinusculeMatcherCore {
    func charEquals(_ patternChar: UInt16, _ patternIndex: Int, _ unit: UInt16, ignoreCase: Bool) -> Bool {
        patternChar == unit || (ignoreCase && (toLowerCase[patternIndex] == unit || toUpperCase[patternIndex] == unit))
    }

    func matchFragment(_ name: [UInt16], _ patternIndex: Int, _ nameIndex: Int) -> [Range<Int>]? {
        let fragmentLength = maxMatchingFragment(name, patternIndex, nameIndex)
        return fragmentLength == 0 ? nil : matchInsideFragment(name, patternIndex, nameIndex, fragmentLength)
    }

    func maxMatchingFragment(_ name: [UInt16], _ patternIndex: Int, _ nameIndex: Int) -> Int {
        if !isFirstCharMatching(name, nameIndex, patternIndex) {
            return 0
        }
        var offset = 1
        let ignoreCase = mode != .matchCase
        while nameIndex + offset < name.count && patternIndex + offset < pattern.count {
            let nameChar = name[nameIndex + offset]
            if !charEquals(pattern[patternIndex + offset], patternIndex + offset, nameChar, ignoreCase: ignoreCase) {
                if isSkippingDigitBetweenPatternDigits(patternIndex + offset, nameChar) {
                    return 0
                }
                break
            }
            offset += 1
        }
        return offset
    }

    func isSkippingDigitBetweenPatternDigits(_ patternIndex: Int, _ nameChar: UInt16) -> Bool {
        MatchingCharacter.isDigit(pattern[patternIndex])
            && MatchingCharacter.isDigit(pattern[patternIndex - 1])
            && MatchingCharacter.isDigit(nameChar)
    }

    func matchInsideFragment(
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

    func isMiddleMatch(_ name: [UInt16], _ patternIndex: Int, _ nameIndex: Int) -> Bool {
        isPatternChar(patternIndex - 1, Self.star)
            && !isWildcard(patternIndex + 1)
            && MatchingCharacter.isLetterOrDigit(name[nameIndex])
            && !NameUtilCore.isWordStart(name, nameIndex)
    }

    func findLongestMatchingPrefix(
        _ name: [UInt16],
        _ patternIndex: Int,
        _ nameIndex: Int,
        _ fragmentLength: Int,
        _ minFragment: Int
    ) -> [Range<Int>]? {
        if patternIndex + fragmentLength >= pattern.count {
            return [nameIndex..<(nameIndex + fragmentLength)]
        }

        var offset = fragmentLength
        while offset >= minFragment || (offset > 0 && isWildcard(patternIndex + offset)) {
            let ranges: [Range<Int>]?
            if isWildcard(patternIndex + offset) {
                ranges = matchWildcards(name, patternIndex + offset, nameIndex + offset)
            } else {
                var nextOccurrence = findNextPatternCharacterOccurrence(
                    name, nameIndex + offset + 1, patternIndex + offset
                )
                nextOccurrence = checkForSpecialCharacters(
                    name, nameIndex + offset, nextOccurrence, patternIndex + offset
                )
                if nextOccurrence >= 0 {
                    ranges = matchSkippingWords(
                        name, patternIndex + offset, nextOccurrence, allowSpecialCharacters: false
                    )
                } else {
                    ranges = nil
                }
            }
            if let ranges {
                return Self.appendRange(ranges, from: nameIndex, length: offset)
            }
            offset -= 1
        }
        return nil
    }

    func improveCamelHumps(
        _ name: [UInt16],
        _ patternIndex: Int,
        _ nameIndex: Int,
        _ maxFragment: Int,
        _ minFragment: Int
    ) -> [Range<Int>]? {
        var offset = minFragment
        while offset < maxFragment {
            if isUpperCase[patternIndex + offset] && pattern[patternIndex + offset] != name[nameIndex + offset] {
                let nextWordStart = indexOfWordStart(name, patternIndex + offset, nameIndex + offset)
                if let ranges = matchWildcards(name, patternIndex + offset, nextWordStart) {
                    return Self.appendRange(ranges, from: nameIndex, length: offset)
                }
            }
            offset += 1
        }
        return nil
    }

    func isFirstCharMatching(_ name: [UInt16], _ nameIndex: Int, _ patternIndex: Int) -> Bool {
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

    func hasCase(_ patternIndex: Int) -> Bool {
        isUpperCase[patternIndex] || isLowerCase[patternIndex]
    }

    func isWildcard(_ patternIndex: Int) -> Bool {
        patternIndex >= 0 && patternIndex < pattern.count && Self.isWildcardUnit(pattern[patternIndex])
    }

    func isPatternChar(_ patternIndex: Int, _ unit: UInt16) -> Bool {
        patternIndex >= 0 && patternIndex < pattern.count && pattern[patternIndex] == unit
    }
}
