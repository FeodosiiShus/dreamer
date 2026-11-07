import Foundation
@testable import Dreamder

nonisolated struct MarkdownTokenSample: Equatable, CustomStringConvertible {
    let kind: MarkdownTokenKind
    let text: String

    init(_ kind: MarkdownTokenKind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    var description: String {
        "\(kind)(\(text.debugDescription))"
    }
}

nonisolated enum MarkdownLexerSupport {
    static func tokens(_ text: String) -> [MarkdownToken] {
        MarkdownBlockLexer.tokens(in: text)
    }

    static func slice(_ token: MarkdownToken, in text: String) -> String {
        (text as NSString).substring(with: token.range)
    }

    static func samples(_ text: String) -> [MarkdownTokenSample] {
        tokens(text).map { MarkdownTokenSample($0.kind, slice($0, in: text)) }
    }

    static func texts(of kind: MarkdownTokenKind, in text: String) -> [String] {
        tokens(text).filter { $0.kind == kind }.map { slice($0, in: text) }
    }

    static func ranges(of kind: MarkdownTokenKind, in text: String) -> [NSRange] {
        tokens(text).filter { $0.kind == kind }.map(\.range)
    }

    static func kinds(at offset: Int, in text: String) -> [MarkdownTokenKind] {
        tokens(text).filter { NSLocationInRange(offset, $0.range) }.map(\.kind)
    }

    static func offset(of fragment: String, in text: String, occurrence: Int = 0) -> Int {
        var searchRange = NSRange(location: 0, length: (text as NSString).length)
        var found = NSRange(location: NSNotFound, length: 0)
        for _ in 0...occurrence {
            found = (text as NSString).range(of: fragment, options: [], range: searchRange)
            guard found.location != NSNotFound else { return NSNotFound }
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: (text as NSString).length - next)
        }
        return found.location
    }

    static func kinds(of fragment: String, in text: String, occurrence: Int = 0) -> [MarkdownTokenKind] {
        let offset = offset(of: fragment, in: text, occurrence: occurrence)
        guard offset != NSNotFound else { return [] }
        let range = NSRange(location: offset, length: (fragment as NSString).length)
        return tokens(text).filter { token in
            token.range.location <= range.location
                && token.range.location + token.range.length >= range.location + range.length
        }.map(\.kind)
    }

    static func exactKinds(of fragment: String, in text: String, occurrence: Int = 0) -> [MarkdownTokenKind] {
        let offset = offset(of: fragment, in: text, occurrence: occurrence)
        guard offset != NSNotFound else { return [] }
        let range = NSRange(location: offset, length: (fragment as NSString).length)
        return tokens(text).filter { $0.range == range }.map(\.kind)
    }

    static func captures(in text: String) -> [MarkdownTokenKind: [String]] {
        var result: [MarkdownTokenKind: [String]] = [:]
        for token in tokens(text) {
            result[token.kind, default: []].append(slice(token, in: text))
        }
        return result
    }
}
