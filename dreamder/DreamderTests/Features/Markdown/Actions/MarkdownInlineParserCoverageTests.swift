import Foundation
import Testing
@testable import Dreamder

struct MarkdownInlineParserCoverage {
    private func described(_ markdown: String) -> [String] {
        let nodes = MarkdownInlineParser.parse(Array(markdown.utf16), base: 0)
        let ns = markdown as NSString
        return nodes.map { "\($0.kind):\(ns.substring(with: $0.range))" }
    }

    private func kinds(_ markdown: String) -> [MarkdownInlineNode.Kind] {
        MarkdownInlineParser.parse(Array(markdown.utf16), base: 0).map(\.kind)
    }

    @Test
    func loneBangIsPlainText() {
        #expect(described("wow! ok").isEmpty)
    }

    @Test
    func angleBracketDestinationMayContainSpaces() {
        #expect(described("[t](<a b>)") == ["inlineLink:[t](<a b>)", "linkText:[t]", "linkDestination:<a b>"])
    }

    @Test
    func angleBracketDestinationHonorsBackslashEscapes() {
        #expect(described("[t](<a\\>b>)") == [
            "inlineLink:[t](<a\\>b>)",
            "linkText:[t]",
            "linkDestination:<a\\>b>"
        ])
    }

    @Test(arguments: ["[t](<a<b>)", "[t](<a\nb>)", "[t](<abc", "[t](a b)", "[t](<a>\"x\")"])
    func malformedDestinationsProduceNoLink(markdown: String) {
        #expect(!kinds(markdown).contains(.inlineLink))
        #expect(!kinds(markdown).contains(.linkDestination))
    }

    @Test
    func escapedParenthesisBelongsToThePlainDestination() {
        #expect(described("[t](a\\)b)") == ["inlineLink:[t](a\\)b)", "linkText:[t]", "linkDestination:a\\)b"])
    }

    @Test
    func balancedParenthesesBelongToThePlainDestination() {
        #expect(described("[t](a(b)c)") == ["inlineLink:[t](a(b)c)", "linkText:[t]", "linkDestination:a(b)c"])
    }

    @Test
    func unterminatedCommentIsPlainText() {
        #expect(described("<!-- a>").isEmpty)
    }

    @Test(arguments: ["<3 b>", "</>"])
    func angleBracketsNotStartingATagArePlainText(markdown: String) {
        #expect(described(markdown).isEmpty)
    }

    @Test
    func schemeWithInvalidCharacterFallsBackToHtmlTag() {
        #expect(described("<a$b:c>") == ["htmlTag:<a$b:c>"])
    }

    @Test
    func aBackslashBeforeANonPunctuationCharacterOrAtTheEndEscapesNothing() {
        #expect(described("\\a *b*") == ["emphasis:*b*"])
        #expect(described("x\\").isEmpty)
        #expect(described("\\*a* *b*") == ["emphasis:*b*"])
    }

    @Test
    func aLoneSurrogateNextToADelimiterRunIsNeitherWhitespaceNorPunctuation() {
        let units: [UInt16] = [0xD800, 0x2A, 0x61, 0x2A]

        let nodes = MarkdownInlineParser.parse(units, base: 0)

        #expect(nodes.map(\.kind) == [.emphasis])
        #expect(nodes.map(\.range) == [NSRange(location: 1, length: 3)])
    }

    @Test
    func aLoneSurrogateAfterADelimiterRunDoesNotBlockClosing() {
        let units: [UInt16] = [0x2A, 0x61, 0x2A, 0xDC00]

        let nodes = MarkdownInlineParser.parse(units, base: 0)

        #expect(nodes.map(\.kind) == [.emphasis])
        #expect(nodes.map(\.range) == [NSRange(location: 0, length: 3)])
    }

    @Test
    func theRuleOfThreeRejectsAnOpenerAndKeepsSearching() {
        #expect(described("*foo**bar*") == ["emphasis:*foo**bar*"])
    }

    @Test
    func destinationMayBePrecededByWhitespace() {
        #expect(described("[t]( a)") == ["inlineLink:[t]( a)", "linkText:[t]", "linkDestination:a"])
    }

    @Test(arguments: ["[t](", "[t]( ", "[t](a", "[t](a ", "[t](<a>", "[t](a(b", "[t](a(b c)"])
    func destinationsCutOffByTheEndOfTextProduceNoLink(markdown: String) {
        #expect(!kinds(markdown).contains(.inlineLink))
        #expect(!kinds(markdown).contains(.linkDestination))
    }

    @Test(arguments: [
        "[t](a \"ti\")", "[t](a 'ti')", "[t](a (ti))", "[t](a \"x\\\"y\")", "[t](a \"ti\" )", "[t](<a b> \"ti\")"
    ])
    func linkTitlesAreAcceptedInAnyQuotingStyle(markdown: String) {
        let result = described(markdown)

        #expect(result.first == "inlineLink:\(markdown)")
        #expect(result.contains("linkText:[t]"))
        #expect(result.count == 3)
    }

    @Test(arguments: ["[t](a \"ti", "[t](a \"ti\" x)", "[t](a \"ti\"", "[t](a \"x\\", "[t](a (ti\")", "[t](a x)"])
    func malformedLinkTitlesProduceNoLink(markdown: String) {
        #expect(!kinds(markdown).contains(.inlineLink))
        #expect(!kinds(markdown).contains(.linkDestination))
    }

    @Test
    func emptyAngleBracketsArePlainText() {
        #expect(described("<>").isEmpty)
    }

    @Test
    func aSchemeMustStartWithAnAsciiLetter() {
        #expect(described("<1a:b>").isEmpty)
        let units: [UInt16] = [0x3C, 0xD800, 0x61, 0x3A, 0x62, 0x3E]
        #expect(MarkdownInlineParser.parse(units, base: 0).isEmpty)
    }

    @Test
    func aNonAsciiSchemeCharacterFallsBackToHtmlTag() {
        #expect(described("<a\u{E9}:b>") == ["htmlTag:<a\u{E9}:b>"])
    }

    @Test(arguments: ["see http://", "http:// x", "www.", "see ftp://\tx"])
    func aBareAutolinkPrefixWithoutHostIsPlainText(markdown: String) {
        #expect(described(markdown).isEmpty)
    }
}
