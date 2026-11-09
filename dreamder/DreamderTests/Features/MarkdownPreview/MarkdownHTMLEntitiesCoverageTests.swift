import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownHTMLEntitiesCoverageTests {
    @Test
    func decodeRejectsMalformedReferences() {
        let cases = ["x", "&", "&#;", "&#x;", "&#65", "&;", "&amp", "&#xZ;"]
        for text in cases {
            #expect(MarkdownHTMLEntities.decode(Array(text), at: 0) == nil, "\(text)")
        }
        #expect(MarkdownHTMLEntities.decode(Array("&amp;"), at: 5) == nil)
    }

    @Test
    func numericReferencesOutsideUnicodeBecomeReplacementCharacter() {
        let replacement = "\u{FFFD}"
        for text in ["&#0;", "&#xD800;", "&#9999999;", "&#x110000;"] {
            let decoded = MarkdownHTMLEntities.decode(Array(text), at: 0)
            #expect(decoded?.text == replacement, "\(text)")
            #expect(decoded?.end == text.count, "\(text)")
        }
    }

    @Test
    func numericReferencesDecodeScalarValues() {
        #expect(MarkdownHTMLEntities.decode(Array("&#65;"), at: 0)?.text == "A")
        #expect(MarkdownHTMLEntities.decode(Array("&#X42;"), at: 0)?.text == "B")
        #expect(MarkdownHTMLEntities.decode(Array("&#128512;"), at: 0)?.text == "\u{1F600}")
        #expect(MarkdownHTMLEntities.decode(Array("x&amp;"), at: 1)?.end == 6)
    }

    @Test
    func namedTableIsWellFormed() {
        #expect(MarkdownHTMLEntities.named["amp"] == "&")
        #expect(MarkdownHTMLEntities.named["ngE"] == "\u{2267}\u{338}")
        #expect(MarkdownHTMLEntities.named.values.allSatisfy { !$0.isEmpty })
    }
}
