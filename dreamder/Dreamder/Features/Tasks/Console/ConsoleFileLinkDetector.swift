import Foundation

nonisolated struct ConsoleFileLink: Sendable, Equatable {
    let range: Range<Int>
    let path: String
    let line: Int?
    let column: Int?
}

nonisolated struct ConsoleFileLinkDetector: Sendable {
    static let maximumLineLength = 4096
    static let maximumDigits = 9
    static let fileURLPrefix = "file://"

    private static let separators: Set<Character> = ["\"", "'", "`", "<", ">", "|"]
    private static let leadingBrackets: Set<Character> = ["(", "[", "{"]
    private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]
    private static let trailingPunctuationAndClosers: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}"]
    private static let pythonPrefix = Array("File ")
    private static let pythonInfix = Array("\", line ")

    init() {}

    func links(in line: String) -> [ConsoleFileLink] {
        links(inCharacters: Array(line))
    }

    func links(inCharacters characters: [Character]) -> [ConsoleFileLink] {
        guard characters.count <= Self.maximumLineLength else { return [] }
        let candidates = (pythonLinks(in: characters) + tokenLinks(in: characters))
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
        var links: [ConsoleFileLink] = []
        for candidate in candidates {
            if let previous = links.last, candidate.range.lowerBound < previous.range.upperBound { continue }
            links.append(candidate)
        }
        return links
    }

    private func pythonLinks(in characters: [Character]) -> [ConsoleFileLink] {
        var links: [ConsoleFileLink] = []
        var index = 0
        while index < characters.count {
            guard let link = pythonLink(in: characters, at: index) else {
                index += 1
                continue
            }
            links.append(link)
            index = link.range.upperBound
        }
        return links
    }

    private func pythonLink(in characters: [Character], at index: Int) -> ConsoleFileLink? {
        let quote = index + Self.pythonPrefix.count
        guard characters[index] == "F",
              index == 0 || characters[index - 1].isWhitespace,
              Self.matches(Self.pythonPrefix, in: characters, at: index),
              quote < characters.count,
              characters[quote] == "\"",
              let closing = characters[(quote + 1)...].firstIndex(of: "\""),
              closing > quote + 1,
              Self.matches(Self.pythonInfix, in: characters, at: closing)
        else { return nil }
        let digitsStart = closing + Self.pythonInfix.count
        var digitsEnd = digitsStart
        while digitsEnd < characters.count, Self.isDigit(characters[digitsEnd]) { digitsEnd += 1 }
        guard let line = Self.number(in: characters, digitsStart..<digitsEnd), line > 0 else { return nil }
        return ConsoleFileLink(
            range: quote..<digitsEnd,
            path: String(characters[(quote + 1)..<closing]),
            line: line,
            column: nil
        )
    }

    private func tokenLinks(in characters: [Character]) -> [ConsoleFileLink] {
        var links: [ConsoleFileLink] = []
        var index = 0
        while index < characters.count {
            guard !Self.isSeparator(characters[index]) else {
                index += 1
                continue
            }
            var end = index
            while end < characters.count, !Self.isSeparator(characters[end]) { end += 1 }
            if let link = tokenLink(in: characters, token: index..<end) { links.append(link) }
            index = end
        }
        return links
    }

    private func tokenLink(in characters: [Character], token: Range<Int>) -> ConsoleFileLink? {
        var lower = token.lowerBound
        while lower < token.upperBound, Self.leadingBrackets.contains(characters[lower]) { lower += 1 }
        let punctuationTrimmed = Self.trimmedEnd(characters, lower..<token.upperBound, Self.trailingPunctuation)
        if let link = parenthesizedLink(in: characters, lower..<punctuationTrimmed) { return link }
        let fullyTrimmed = Self.trimmedEnd(
            characters,
            lower..<punctuationTrimmed,
            Self.trailingPunctuationAndClosers
        )
        return colonLink(in: characters, lower..<fullyTrimmed)
    }

    private func parenthesizedLink(in characters: [Character], _ token: Range<Int>) -> ConsoleFileLink? {
        guard !token.isEmpty,
              characters[token.upperBound - 1] == ")",
              let open = characters[token].lastIndex(of: "(")
        else { return nil }
        let parts = characters[(open + 1)..<(token.upperBound - 1)]
            .split(separator: ",", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Self.number(in: characters, $0.startIndex..<$0.endIndex) }
        guard parts.count <= 2,
              numbers.count == parts.count,
              let line = numbers.first,
              line > 0
        else { return nil }
        let column = numbers.count == 2 ? numbers[1] : nil
        return makeLink(characters, range: token, pathEnd: open, line: line, column: column)
    }

    private func colonLink(in characters: [Character], _ token: Range<Int>) -> ConsoleFileLink? {
        guard let last = Self.trailingNumber(in: characters, token) else { return nil }
        var pathEnd = last.colon
        var line = last.value
        var column: Int?
        if let first = Self.trailingNumber(in: characters, token.lowerBound..<last.colon) {
            pathEnd = first.colon
            line = first.value
            column = last.value
        }
        guard line > 0 else { return nil }
        return makeLink(characters, range: token, pathEnd: pathEnd, line: line, column: column)
    }

    private func makeLink(
        _ characters: [Character],
        range: Range<Int>,
        pathEnd: Int,
        line: Int,
        column: Int?
    ) -> ConsoleFileLink? {
        guard let path = Self.validPath(String(characters[range.lowerBound..<pathEnd])) else { return nil }
        return ConsoleFileLink(range: range, path: path, line: line, column: column)
    }

    private static func validPath(_ text: String) -> String? {
        if text.hasPrefix(fileURLPrefix) {
            let stripped = String(text.dropFirst(fileURLPrefix.count))
            let decoded = stripped.removingPercentEncoding ?? stripped
            return looksLikeFile(decoded) ? decoded : nil
        }
        guard !text.contains("://"), looksLikeFile(text) else { return nil }
        return text
    }

    private static func looksLikeFile(_ path: String) -> Bool {
        let component = path.lastIndex(of: "/").map { path[path.index(after: $0)...] } ?? Substring(path)
        guard !component.isEmpty else { return false }
        if path.contains("/") { return component.contains { $0.isLetter } }
        guard let dot = component.lastIndex(of: ".") else { return false }
        let fileExtension = component[component.index(after: dot)...]
        return fileExtension.contains { $0.isLetter } && fileExtension.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func trailingNumber(
        in characters: [Character],
        _ range: Range<Int>
    ) -> (value: Int, colon: Int)? {
        var start = range.upperBound
        while start > range.lowerBound, isDigit(characters[start - 1]) { start -= 1 }
        guard start < range.upperBound,
              start > range.lowerBound,
              characters[start - 1] == ":",
              let value = number(in: characters, start..<range.upperBound)
        else { return nil }
        return (value, start - 1)
    }

    private static func number(in characters: [Character], _ range: Range<Int>) -> Int? {
        guard !range.isEmpty,
              range.count <= maximumDigits,
              characters[range].allSatisfy(isDigit)
        else { return nil }
        return Int(String(characters[range]))
    }

    private static func trimmedEnd(_ characters: [Character], _ range: Range<Int>, _ trimmed: Set<Character>) -> Int {
        var end = range.upperBound
        while end > range.lowerBound, trimmed.contains(characters[end - 1]) { end -= 1 }
        return end
    }

    private static func matches(_ pattern: [Character], in characters: [Character], at index: Int) -> Bool {
        index + pattern.count <= characters.count && Array(characters[index..<(index + pattern.count)]) == pattern
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || separators.contains(character)
    }
}
