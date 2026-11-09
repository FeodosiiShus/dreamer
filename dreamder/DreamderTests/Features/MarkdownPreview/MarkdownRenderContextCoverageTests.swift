import Foundation
import Testing
@testable import Dreamder

private func contextPlain(_ markdown: String) -> String {
    MarkdownPreviewTestSupport.plainHTML(markdown)
}

@Suite
struct MarkdownRenderContextCoverageTests {
    @Test
    func strippingContainersRemovesQuotesAndListMarkers() {
        #expect(MarkdownLinkReferences.strippingContainers("-") == "")
        #expect(MarkdownLinkReferences.strippingContainers("- ") == "")
        #expect(MarkdownLinkReferences.strippingContainers("> - ") == "")
        #expect(MarkdownLinkReferences.strippingContainers("> > x") == "x")
        #expect(MarkdownLinkReferences.strippingContainers("- > [a]: /u") == "[a]: /u")
        #expect(MarkdownLinkReferences.strippingContainers("  plain") == "plain")
    }

    @Test
    func definitionLabelKeepsEscapedBracket() {
        let html = contextPlain("[a\\]b]: /u\n\n[a\\]b]")
        #expect(html == "<p><a href=\"/u\">a]b</a></p>")
    }

    @Test
    func definitionTitleKeepsEscapedQuote() {
        let html = contextPlain("[a]: /u \"t\\\"x\"\n\n[a]")
        #expect(html == "<p><a href=\"/u\" title=\"t&quot;x\">a</a></p>")
    }

    @Test
    func definitionMayBeIndentedUpToThreeSpaces() {
        #expect(contextPlain("  [a]: /u\n\n[a]") == "<p><a href=\"/u\">a</a></p>")
    }

    @Test
    func malformedDefinitionsAreIgnored() {
        let rejected = [
            "[a]", "[a: /u", "[[a]]: /u", "[ ]: /u", "[a]:", "[a]: <b", "[a]: <b<c>", "[a]: /u x", "[a]: /u \"t",
            "[a]: <b>\"t\"", "[a]: /u \"t\" x"
        ]
        for line in rejected {
            #expect(MarkdownLinkReferences.parseDefinition(line) == nil, "\(line)")
        }
    }

    @Test
    func acceptedDefinitionForms() throws {
        let angle = try #require(MarkdownLinkReferences.parseDefinition("[a]: <b c> 'T'"))
        #expect(angle.label == "a")
        #expect(angle.reference == MarkdownLinkReference(destination: "b c", title: "T"))

        let paren = try #require(MarkdownLinkReferences.parseDefinition("[a]: /u (T)"))
        #expect(paren.reference == MarkdownLinkReference(destination: "/u", title: "T"))

        let bare = try #require(MarkdownLinkReferences.parseDefinition("[a]:\t/u"))
        #expect(bare.reference == MarkdownLinkReference(destination: "/u", title: nil))
    }

    @Test
    func headingIdentifiersAreDeduplicated() {
        let context = MarkdownRenderContext(references: [:], includesSourcePositions: true)
        #expect(context.headingAttributes(content: "Title", from: 0, to: 5) == " id=\"title\" md-src-pos=\"0..5\"")
        #expect(context.headingAttributes(content: "Title", from: 6, to: 11) == " id=\"title-1\" md-src-pos=\"6..11\"")
        #expect(context.inline.references.isEmpty)
    }

    @Test
    func positionsCanBeDisabled() {
        let context = MarkdownRenderContext(references: [:], includesSourcePositions: false)
        #expect(context.positionAttribute(from: 0, to: 3) == "")
        #expect(context.headingAttributes(content: "Title", from: 0, to: 5) == " id=\"title\"")
    }

    @Test
    func sourceLinesTrackUTF16OffsetsAndContentEnd() {
        let lines = MarkdownSourceLine.split("a \r\n\u{1F600}\tb\r\u{200B}\n")
        #expect(lines.map(\.offset) == [0, 4, 9, 11])
        #expect(lines[0].contentEnd == 1)
        #expect(lines[1].end == 8)
        #expect(lines[1].suffix("b").offset == 7)
        #expect(MarkdownSourceLine(text: "x\t ", offset: 3).contentEnd == 4)
    }
}
