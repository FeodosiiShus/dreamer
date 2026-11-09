import Foundation
import Testing
@testable import Dreamder

struct MarkdownLinkCreationCoverage {
    private static let pastedURL = "https://example.com"
    private static let createdLink = "[words](https://example.com)"

    private func pasted(_ markup: String) -> String {
        let parsed = MarkdownActionCaretMarkup(markup)
        let selection = parsed.selections.first ?? NSRange(location: 0, length: 0)
        return MarkdownLinkCreation.pasteReplacement(
            text: parsed.text,
            selection: selection,
            pasted: Self.pastedURL
        )
    }

    @Test
    func bareUrlsAroundTheSelectionDoNotPreventLinkCreation() {
        let markup = "see http://. https://a.b/c?. (https://a.b/(x)) (https://a.b/y) <selection>words</selection>"

        #expect(pasted(markup) == Self.createdLink)
    }

    @Test
    func selectionOnTheSemicolonAfterABareUrlIsInsideTheUrl() {
        #expect(pasted("see https://a.b/c<selection>;</selection> now") == Self.pastedURL)
    }

    @Test
    func definitionBehindAnOverlongListMarkerGapIsRecognized() {
        #expect(pasted("-      [label]: <selection>words</selection>") == Self.pastedURL)
        #expect(pasted("-      [label] <selection>words</selection>") == Self.createdLink)
    }

    @Test
    func escapedOpeningBracketDoesNotStartALabel() {
        #expect(pasted("a\\[b] <selection>words</selection>") == Self.createdLink)
    }

    @Test
    func escapedClosingBracketStaysInsideTheLabel() {
        #expect(pasted("[a\\]b] <selection>words</selection>") == Self.createdLink)
    }

    @Test
    func unclosedLabelIsSkipped() {
        #expect(pasted("[ open <selection>words</selection>") == Self.createdLink)
    }
}
