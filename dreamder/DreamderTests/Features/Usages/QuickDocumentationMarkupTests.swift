import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@Suite("Quick documentation markup")
struct QuickDocumentationMarkupTests {
    @Test func readsMarkdownMarkupContent() {
        let hover = Hover(contents: .optionC(MarkupContent(kind: .markdown, value: "**Int** — a number")), range: nil)
        let content = QuickDocumentationMarkup.content(from: hover)
        #expect(content == QuickDocumentationContent(text: "**Int** — a number", isMarkdown: true))
    }

    @Test func readsPlaintextMarkupContent() {
        let hover = Hover(contents: .optionC(MarkupContent(kind: .plaintext, value: "Int")), range: nil)
        let content = QuickDocumentationMarkup.content(from: hover)
        #expect(content == QuickDocumentationContent(text: "Int", isMarkdown: false))
    }

    @Test func readsSingleMarkedString() {
        let hover = Hover(contents: .optionA(.optionA("func value() -> Int")), range: nil)
        let content = QuickDocumentationMarkup.content(from: hover)
        #expect(content == QuickDocumentationContent(text: "func value() -> Int", isMarkdown: true))
    }

    @Test func joinsMarkedStringListsAndFencesLanguages() {
        let hover = Hover(contents: .optionB([
            .optionA("Documentation."),
            .optionB(LanguageStringPair(language: .swift, value: "let value = 1"))
        ]), range: nil)
        let content = QuickDocumentationMarkup.content(from: hover)
        #expect(content?.text == "Documentation.\n\n```swift\nlet value = 1\n```")
        #expect(content?.isMarkdown == true)
    }

    @Test func ignoresEmptyHover() {
        #expect(QuickDocumentationMarkup.content(from: nil) == nil)
        #expect(QuickDocumentationMarkup.content(from: Hover(
            contents: .optionC(MarkupContent(kind: .markdown, value: "   ")),
            range: nil
        )) == nil)
        #expect(QuickDocumentationMarkup.content(from: Hover(contents: .optionB([.optionA("")]), range: nil)) == nil)
    }

    @Test func splitsFencedCodeFromProse() {
        let blocks = QuickDocumentationMarkup.blocks(fromMarkdown: """
        `value` is a number.

        ```swift
        let value = 1
        let other = 2
        ```
        """)
        #expect(blocks == [
            .prose("`value` is a number."),
            .code("let value = 1\nlet other = 2")
        ])
    }

    @Test func keepsUnterminatedFenceAsCode() {
        let blocks = QuickDocumentationMarkup.blocks(fromMarkdown: """
        ```swift
        let value = 1
        """)
        #expect(blocks == [.code("let value = 1")])
    }

    @Test func keepsPlainContentAsSingleBlock() {
        let content = QuickDocumentationContent(text: "Int\nA signed integer.", isMarkdown: false)
        #expect(QuickDocumentationMarkup.blocks(from: content) == [.plain("Int\nA signed integer.")])
    }

    @Test func dropsEmptyProse() {
        let blocks = QuickDocumentationMarkup.blocks(fromMarkdown: "\n\n**Int**\n\n")
        #expect(blocks == [.prose("**Int**")])
    }

    @Test func normalizesCarriageReturns() {
        let blocks = QuickDocumentationMarkup.blocks(fromMarkdown: "First line.\r\nSecond line.\r\n```swift\r\nlet value = 1\r\n```")
        #expect(blocks == [.prose("First line.\nSecond line."), .code("let value = 1")])
    }

    @Test func exposesBlockTextAndCodeFlag() {
        let blocks: [QuickDocumentationBlock] = [.prose("a"), .plain("b"), .code("c")]
        #expect(blocks.map(\.text) == ["a", "b", "c"])
        #expect(blocks.map(\.isCode) == [false, false, true])
    }
}
