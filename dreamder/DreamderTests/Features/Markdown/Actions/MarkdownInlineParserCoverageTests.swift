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
}
