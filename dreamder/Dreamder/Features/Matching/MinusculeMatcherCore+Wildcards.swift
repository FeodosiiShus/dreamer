import Foundation

nonisolated extension MinusculeMatcherCore {
    func nameContainsAllMeaningfulCharactersInOrder(_ name: [UInt16]) -> Bool {
        var meaningfulIndex = 0
        var nameIndex = 0
        while meaningfulIndex + 1 < meaningfulCharacters.count {
            if nameIndex >= name.count {
                return false
            }
            let firstUnit = meaningfulCharacters[meaningfulIndex]
            let indexOf1 = Self.indexOf(name, firstUnit, from: nameIndex)
            if indexOf1 == nameIndex {
                nameIndex = indexOf1 + 1
            } else {
                let secondUnit = meaningfulCharacters[meaningfulIndex + 1]
                if firstUnit == secondUnit {
                    if indexOf1 < 0 {
                        return false
                    }
                    nameIndex = indexOf1 + 1
                } else {
                    let indexOf2 = Self.indexOf(name, secondUnit, from: nameIndex)
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

    func matchBySubstring(_ name: [UInt16]) -> [Range<Int>]? {
        let meaningfulCount = meaningfulCharacters.count / 2
        if isPatternChar(0, Self.star) {
            var position = 0
            while position <= name.count - meaningfulCount {
                let length = meaningfulCharactersMatchLength(name, at: position)
                if length != 0 {
                    return [position..<(position + length)]
                }
                position += 1
            }
            return nil
        }
        let length = meaningfulCharactersMatchLength(name, at: 0)
        return length != 0 ? [0..<length] : nil
    }

    func meaningfulCharactersMatchLength(_ name: [UInt16], at nameIndex: Int) -> Int {
        var meaningfulIndex = 0
        var namePosition = nameIndex
        while namePosition < name.count && meaningfulIndex + 1 < meaningfulCharacters.count {
            let unit = name[namePosition]
            if unit == meaningfulCharacters[meaningfulIndex] || unit == meaningfulCharacters[meaningfulIndex + 1] {
                meaningfulIndex += 2
                namePosition += 1
            } else if Self.isWildcardUnit(unit) {
                namePosition += 1
            } else {
                return 0
            }
        }
        return namePosition - nameIndex
    }

    func matchWildcards(_ name: [UInt16], _ startPatternIndex: Int, _ nameIndex: Int) -> [Range<Int>]? {
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

    var isTrailingSpacePattern: Bool {
        isPatternChar(pattern.count - 1, Self.space)
    }

    func isUpperCaseOrDigit(_ patternIndex: Int) -> Bool {
        isUpperCase[patternIndex] || MatchingCharacter.isDigit(pattern[patternIndex])
    }

    func matchSkippingWords(
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

    func findNextPatternCharacterOccurrence(_ name: [UInt16], _ startAt: Int, _ patternIndex: Int) -> Int {
        if !isPatternChar(patternIndex - 1, Self.star) && !isWordSeparator[patternIndex] {
            return indexOfWordStart(name, patternIndex, startAt)
        }
        return indexOfIgnoreCase(name, startAt, patternIndex)
    }

    func checkForSpecialCharacters(_ name: [UInt16], _ start: Int, _ end: Int, _ patternIndex: Int) -> Int {
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

    func seemsLikeFragmentStart(_ name: [UInt16], _ patternIndex: Int, _ nextOccurrence: Int) -> Bool {
        !isUpperCase[patternIndex]
            || MatchingCharacter.isUpperCase(name[nextOccurrence])
            || NameUtilCore.isWordStart(name, nextOccurrence)
            || (!isMixedCase && mode != .matchCase)
    }
}
