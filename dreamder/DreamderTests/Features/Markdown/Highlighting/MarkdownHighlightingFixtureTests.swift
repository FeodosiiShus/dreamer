import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

struct MarkdownHighlightingFixtureTests {
    private struct Expected {
        let fragment: String
        let kind: MarkdownTokenKind

        init(_ fragment: String, _ kind: MarkdownTokenKind) {
            self.fragment = fragment
            self.kind = kind
        }
    }

    private func expectSequence(
        _ expected: [Expected],
        in text: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let nsText = text as NSString
        let tokens = MarkdownLexerSupport.tokens(text)
        var cursor = 0
        for item in expected {
            let searchRange = NSRange(location: cursor, length: nsText.length - cursor)
            let found = nsText.range(of: item.fragment, options: [], range: searchRange)
            #expect(found.location != NSNotFound, "\(item.fragment) not found", sourceLocation: sourceLocation)
            guard found.location != NSNotFound else { return }
            let exists = tokens.contains { $0.range == found && $0.kind == item.kind }
            #expect(exists, "\(item.kind) over \(item.fragment.debugDescription) missing", sourceLocation: sourceLocation)
            cursor = found.location + found.length
        }
    }

    private func isCovered(_ fragment: String, in text: String) -> Bool {
        let range = (text as NSString).range(of: fragment)
        return MarkdownLexerSupport.tokens(text).contains { NSIntersectionRange($0.range, range).length > 0 }
    }

    @Test func inlineHtmlTagsAreHighlightedAsHtml() {
        let text = "Some text with embedded <b>html</b>."
        expectSequence(
            [
                Expected("<", .htmlTag),
                Expected("b", .htmlTagName),
                Expected(">", .htmlTag),
                Expected("</", .htmlTag),
                Expected("b", .htmlTagName),
                Expected(">", .htmlTag)
            ],
            in: text
        )
        let composites = MarkdownLexerSupport.texts(of: .inlineHtml, in: text)
        #expect(composites == ["<b>", "</b>"])
    }

    @Test(arguments: ["Some text with embedded ", "html", "."])
    func inlineHtmlSurroundingTextHasNoToken(fragment: String) {
        let text = "Some text with embedded <b>html</b>."
        #expect(!isCovered(fragment, in: text))
    }

    @Test(arguments: ["<!--", "multiline", "comment", "-->"])
    func multilineHtmlCommentLinesAreComments(fragment: String) {
        let text = "Some text.\n\n<!--\nmultiline\ncomment\n-->\n\nTrailing text."
        let kinds = MarkdownLexerSupport.exactKinds(of: fragment, in: text)
        #expect(kinds == [.htmlComment])
    }

    @Test(arguments: ["Some text.", "Trailing text."])
    func multilineHtmlCommentSurroundingTextHasNoToken(fragment: String) {
        let text = "Some text.\n\n<!--\nmultiline\ncomment\n-->\n\nTrailing text."
        #expect(!isCovered(fragment, in: text))
    }

    @Test func htmlBlockContentIsHighlightedAsHtml() {
        let text = "Some text.\n\n<section class=\"hero\">\n  <div id=\"main\">Hello</div>\n</section>\n\n<!--comment-->"
        expectSequence(
            [
                Expected("<", .htmlTag),
                Expected("section", .htmlTagName),
                Expected("class", .htmlAttributeName),
                Expected("=", .htmlAttributeValue),
                Expected("\"hero\"", .htmlAttributeValue),
                Expected(">", .htmlTag),
                Expected("<", .htmlTag),
                Expected("div", .htmlTagName),
                Expected("id", .htmlAttributeName),
                Expected("=", .htmlAttributeValue),
                Expected("\"main\"", .htmlAttributeValue),
                Expected(">", .htmlTag),
                Expected("Hello", .htmlCode),
                Expected("</", .htmlTag),
                Expected("div", .htmlTagName),
                Expected(">", .htmlTag),
                Expected("</", .htmlTag),
                Expected("section", .htmlTagName),
                Expected(">", .htmlTag),
                Expected("<!--comment-->", .htmlComment)
            ],
            in: text
        )
    }

    @Test func htmlBlockSurroundingTextHasNoToken() {
        let text = "Some text.\n\n<section class=\"hero\">\n  <div id=\"main\">Hello</div>\n</section>\n\n<!--comment-->"
        #expect(!isCovered("Some text.", in: text))
    }

    @Test func htmlTagNameMapsToKeyword() {
        #expect(MarkdownHighlightProvider.captureMapping[.htmlTagName] == .keyword)
    }

    @Test func htmlAttributeValueMapsToString() {
        #expect(MarkdownHighlightProvider.captureMapping[.htmlAttributeValue] == .string)
    }

    @Test func htmlCommentMapsToComment() {
        #expect(MarkdownHighlightProvider.captureMapping[.htmlComment] == .comment)
    }

    @Test(arguments: [MarkdownTokenKind.htmlTag, .htmlAttributeName, .htmlCode, .inlineHtml])
    func otherHtmlKindsHaveNoOwnColor(kind: MarkdownTokenKind) {
        #expect(MarkdownHighlightProvider.captureMapping[kind] == nil)
    }
}
