import Foundation

nonisolated struct CodePointSlice: Sendable {
    let value: UInt32
    let length: Int
}

nonisolated enum NameUtilCore {
    nonisolated private enum Script {
        case hiragana
        case katakana
        case common
        case other
    }

    static func codePointAt(_ text: [UInt16], _ index: Int) -> CodePointSlice {
        let unit = text[index]
        if MatchingCharacter.isHighSurrogate(unit), index + 1 < text.count {
            let next = text[index + 1]
            if MatchingCharacter.isLowSurrogate(next) {
                let value = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(next) - 0xDC00)
                return CodePointSlice(value: value, length: 2)
            }
        }
        return CodePointSlice(value: UInt32(unit), length: 1)
    }

    static func codePointBefore(_ text: [UInt16], _ index: Int) -> CodePointSlice {
        let unit = text[index - 1]
        if MatchingCharacter.isLowSurrogate(unit), index >= 2 {
            let previous = text[index - 2]
            if MatchingCharacter.isHighSurrogate(previous) {
                let value = 0x10000 + ((UInt32(previous) - 0xD800) << 10) + (UInt32(unit) - 0xDC00)
                return CodePointSlice(value: value, length: 2)
            }
        }
        return CodePointSlice(value: UInt32(unit), length: 1)
    }

    static func nextWord(_ text: [UInt16], _ start: Int) -> Int {
        guard start >= 0, start < text.count else { return start + 1 }
        let first = codePointAt(text, start)
        if !MatchingCharacter.isLetterOrDigit(first.value) {
            return start + first.length
        }

        var i = start
        while i < text.count {
            let codePoint = codePointAt(text, i)
            if !MatchingCharacter.isDigit(codePoint.value) { break }
            i += codePoint.length
        }
        if i > start {
            return i
        }

        while i < text.count {
            let codePoint = codePointAt(text, i)
            if !MatchingCharacter.isUpperCase(codePoint.value) { break }
            i += codePoint.length
        }

        if i > start + first.length {
            if i == text.count || !MatchingCharacter.isLetter(codePointAt(text, i).value) {
                return i
            }
            return i - codePointBefore(text, i).length
        }

        if i == start {
            i += first.length
        }
        while i < text.count {
            let codePoint = codePointAt(text, i)
            if !MatchingCharacter.isLetter(codePoint.value) || isWordStart(text, i) { break }
            i += codePoint.length
        }
        return i
    }

    static func isWordStart(_ text: [UInt16], _ i: Int) -> Bool {
        let current = codePointAt(text, i)
        let hasPrevious = i > 0
        let previousValue = hasPrevious ? codePointBefore(text, i).value : 0
        if MatchingCharacter.isUpperCase(current.value) {
            if hasPrevious && MatchingCharacter.isUpperCase(previousValue) {
                let nextPosition = i + current.length
                return nextPosition < text.count
                    && MatchingCharacter.isLowerCase(codePointAt(text, nextPosition).value)
            }
            return true
        }
        if MatchingCharacter.isDigit(current.value) {
            return true
        }
        if !MatchingCharacter.isLetter(current.value) {
            return false
        }
        if MatchingCharacter.isIdeographic(current.value) {
            return true
        }
        return i == 0
            || !MatchingCharacter.isLetterOrDigit(text[i - 1])
            || (hasPrevious && isKanaBreak(current.value, previousValue))
    }

    static func splitNameIntoWordList(_ name: String) -> [String] {
        let units = Array(name.utf16)
        var result: [String] = []
        var wordStart = 0
        while wordStart <= units.count {
            var wordEnd = wordStart
            while wordEnd < units.count && units[wordEnd] != 0x5F {
                wordEnd += 1
            }
            let word = Array(units[wordStart..<wordEnd])
            var start = 0
            while start < word.count {
                let next = nextWord(word, start)
                result.append(String(decoding: word[start..<next], as: UTF16.self))
                start = next
            }
            wordStart = wordEnd + 1
        }
        return result
    }

    private static func isMaybeKana(_ c: UInt32) -> Bool {
        (c >= 0x3040 && c <= 0x3358) || (c >= 0xFF66 && c <= 0xFF9D)
    }

    private static func script(of c: UInt32) -> Script {
        switch c {
        case 0x3041...0x3096, 0x309D...0x309F:
            return .hiragana
        case 0x30A1...0x30FA, 0x30FD...0x30FF, 0x31F0...0x31FF, 0x32D0...0x32FE, 0x3300...0x3357,
             0xFF66...0xFF6F, 0xFF71...0xFF9D:
            return .katakana
        case 0x309B, 0x309C, 0x30A0, 0x30FB, 0x30FC, 0xFF70, 0xFF9E, 0xFF9F:
            return .common
        default:
            if MatchingCharacter.isLetter(c) || MatchingCharacter.isMark(c) {
                return .other
            }
            return .common
        }
    }

    private static func isKanaBreak(_ current: UInt32, _ previous: UInt32) -> Bool {
        if !isMaybeKana(current) && !isMaybeKana(previous) { return false }
        let currentScript = script(of: current)
        let previousScript = script(of: previous)
        if previousScript == currentScript { return false }
        let involvesKana = currentScript == .katakana || currentScript == .hiragana
            || previousScript == .katakana || previousScript == .hiragana
        return involvesKana && previousScript != .common && currentScript != .common
    }
}
