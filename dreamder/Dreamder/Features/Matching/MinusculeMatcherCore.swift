import Foundation

nonisolated struct MinusculeMatcherCore: Sendable {
    static let maxCamelHumpMatchingLength = 100

    static let star: UInt16 = 0x2A
    static let space: UInt16 = 0x20
    static let dot: UInt16 = 0x2E

    let pattern: [UInt16]
    let mode: MatchingCaseMode
    let hardSeparators: [UInt16]
    let isLowerCase: [Bool]
    let isUpperCase: [Bool]
    let isWordSeparator: [Bool]
    let toUpperCase: [UInt16]
    let toLowerCase: [UInt16]
    let isMixedCase: Bool
    let hasSeparators: Bool
    let hasDots: Bool
    let meaningfulCharacters: [UInt16]

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
        var patternPosition = -1
        var skippedHumps = 0
        var nextHumpStart = 0
        var humpStartMatchedUpperCase = false

        for (rangeIndex, range) in fragments.enumerated() {
            var nameIndex = range.lowerBound
            while nameIndex < range.upperBound {
                let afterGap = nameIndex == range.lowerBound && rangeIndex != 0
                var isHumpStart = false
                while nextHumpStart <= nameIndex {
                    if nextHumpStart == nameIndex {
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

                let nameChar = name[nameIndex]
                patternPosition = indexOfInPattern(nameChar, from: patternPosition + 1)
                if patternPosition < 0 {
                    break
                }

                if isHumpStart {
                    humpStartMatchedUpperCase = nameChar == pattern[patternPosition] && isUpperCase[patternPosition]
                }

                matchingCase += evaluateCaseMatching(
                    CaseMatchingContext(
                        valuedStartMatch: valuedStartMatch,
                        patternIndex: patternPosition,
                        humpStartMatchedUpperCase: humpStartMatchedUpperCase,
                        nameIndex: nameIndex,
                        afterGap: afterGap,
                        isHumpStart: isHumpStart,
                        nameChar: nameChar
                    )
                )
                nameIndex += 1
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

    struct CaseMatchingContext {
        let valuedStartMatch: Bool
        let patternIndex: Int
        let humpStartMatchedUpperCase: Bool
        let nameIndex: Int
        let afterGap: Bool
        let isHumpStart: Bool
        let nameChar: UInt16
    }

    func evaluateCaseMatching(_ context: CaseMatchingContext) -> Int {
        let patternIndex = context.patternIndex
        let nameChar = context.nameChar
        let nameIndex = context.nameIndex
        let afterGap = context.afterGap
        let isHumpStart = context.isHumpStart
        let valuedStartMatch = context.valuedStartMatch
        let humpStartMatchedUpperCase = context.humpStartMatchedUpperCase
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
}
