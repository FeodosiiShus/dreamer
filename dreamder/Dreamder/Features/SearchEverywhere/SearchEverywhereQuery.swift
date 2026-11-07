import Foundation
import Synchronization

nonisolated struct SearchEverywhereQuery: Equatable, Sendable {
    let text: String
    let line: Int?
    let column: Int?

    init(text: String, line: Int? = nil, column: Int? = nil) {
        self.text = text
        self.line = line
        self.column = column
    }

    static func parse(_ raw: String) -> SearchEverywhereQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return SearchEverywhereQuery(text: "")
        }
        guard LineColumnPattern.mayContainPosition(trimmed) else {
            return SearchEverywhereQuery(text: trimmed)
        }
        let units = Array(trimmed.utf16)
        guard let split = LineColumnPattern.split(units) else {
            return SearchEverywhereQuery(text: trimmed)
        }
        let text = String(decoding: units[0..<split.nameEnd], as: UTF16.self)
        let firstNumber = LineColumnPattern.number(units, split.line)
        let secondNumber = LineColumnPattern.number(units, split.column)
        let lineNumber = split.line == nil ? secondNumber : firstNumber
        let columnNumber = split.line == nil ? nil : secondNumber
        guard let line = lineNumber, line > 0 else {
            return SearchEverywhereQuery(text: text)
        }
        let column = columnNumber.flatMap { $0 > 0 ? $0 : nil }
        return SearchEverywhereQuery(text: text, line: line, column: column)
    }
}

private nonisolated enum LineColumnPattern {
    struct Split {
        let nameEnd: Int
        let line: Range<Int>?
        let column: Range<Int>?
    }

    private static let triggerCharacters: Set<Character> = [":", ",", ";", "@", "[", "(", " ", "#"]

    private static let separators: [[UInt16]] = [
        ":", "@", ",", " ", "#", "#L", "?l=", " on line ", " at line ", ":line ", ":(", "(", ":[", "["
    ].map { Array($0.utf16) }

    static func mayContainPosition(_ text: String) -> Bool {
        text.contains { triggerCharacters.contains($0) } || text.contains("?l=")
    }

    static func split(_ units: [UInt16]) -> Split? {
        var nameEnd = 1
        while nameEnd < units.count {
            if isLineTerminator(units[nameEnd - 1]) {
                return nil
            }
            for separator in separators where hasSeparator(units, at: nameEnd, separator) {
                if let tail = matchTail(units, from: nameEnd + separator.count) {
                    return Split(nameEnd: nameEnd, line: tail.line, column: tail.column)
                }
            }
            nameEnd += 1
        }
        return nil
    }

    static func number(_ units: [UInt16], _ range: Range<Int>?) -> Int? {
        guard let range else { return nil }
        return Int(String(decoding: units[range], as: UTF16.self))
    }

    private static func hasSeparator(_ units: [UInt16], at index: Int, _ separator: [UInt16]) -> Bool {
        guard index + separator.count <= units.count else { return false }
        for offset in separator.indices where units[index + offset] != separator[offset] {
            return false
        }
        return true
    }

    private static func matchTail(
        _ units: [UInt16],
        from start: Int
    ) -> (line: Range<Int>?, column: Range<Int>?)? {
        for (line, afterLine) in digitOptions(units, at: start) {
            if afterLine < units.count, isNonWord(units[afterLine]) {
                for (column, afterColumn) in digitOptions(units, at: afterLine + 1)
                where endsWithOptionalClosing(units, at: afterColumn) {
                    return (line, column)
                }
            }
            if endsWithOptionalClosing(units, at: afterLine) {
                return (line, nil)
            }
        }
        return nil
    }

    private static func digitOptions(_ units: [UInt16], at start: Int) -> [(Range<Int>?, Int)] {
        var end = start
        while end < units.count, isDigit(units[end]) {
            end += 1
        }
        var options: [(Range<Int>?, Int)] = []
        var length = end - start
        while length > 0 {
            options.append((start..<(start + length), start + length))
            length -= 1
        }
        options.append((nil, start))
        return options
    }

    private static func endsWithOptionalClosing(_ units: [UInt16], at index: Int) -> Bool {
        if index == units.count {
            return true
        }
        return index == units.count - 1 && (units[index] == 0x29 || units[index] == 0x5D)
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        unit >= 0x30 && unit <= 0x39
    }

    private static func isNonWord(_ unit: UInt16) -> Bool {
        !(isDigit(unit) || (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F)
    }

    private static func isLineTerminator(_ unit: UInt16) -> Bool {
        unit == 0x0A || unit == 0x0D || unit == 0x85 || unit == 0x2028 || unit == 0x2029
    }
}

nonisolated struct SearchEverywhereMatch: Equatable, Sendable {
    let score: Int
    let ranges: [NSRange]
}

nonisolated enum SearchEverywhereMatcher {
    private nonisolated struct CachedMatcher: Sendable {
        let query: String
        let matcher: MinusculeMatcher
    }

    private static let cache = Mutex<CachedMatcher?>(nil)

    static func matcher(for query: String) -> MinusculeMatcher {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let cached: MinusculeMatcher? = cache.withLock { stored -> MinusculeMatcher? in
            guard let stored, stored.query == trimmed else { return nil }
            return stored.matcher
        }
        if let cached {
            return cached
        }
        let pattern = trimmed.hasPrefix("*") ? trimmed : "*" + trimmed
        let matcher = MinusculeMatcher(pattern: pattern, mode: .ignoreCase, preferStartMatch: true)
        cache.withLock { $0 = CachedMatcher(query: trimmed, matcher: matcher) }
        return matcher
    }

    static func match(query: String, in candidate: String) -> SearchEverywhereMatch? {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return SearchEverywhereMatch(score: 0, ranges: [])
        }
        return match(using: matcher(for: query), in: candidate)
    }

    static func match(using matcher: MinusculeMatcher, in candidate: String) -> SearchEverywhereMatch? {
        guard let result = matcher.matchWithDegree(candidate) else {
            return nil
        }
        let ranges = result.fragments.map { NSRange(location: $0.lowerBound, length: $0.count) }
        return SearchEverywhereMatch(score: result.degree, ranges: ranges)
    }
}
