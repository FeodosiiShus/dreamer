import Foundation
import Testing
@testable import Dreamder

struct MarkdownLinkCreationTests {
    private static let pastedURL = "https://example.com"

    private func pasted(_ markup: String, _ clipboard: String = MarkdownLinkCreationTests.pastedURL) -> String {
        let parsed = MarkdownActionCaretMarkup(markup)
        let selection = parsed.selections.first ?? NSRange(location: 0, length: 0)
        return MarkdownLinkCreation.pasteReplacement(text: parsed.text, selection: selection, pasted: clipboard)
    }

    private func wrapped(
        _ markup: String,
        clipboard: String? = nil,
        existingPaths: Set<String> = []
    ) -> String {
        let parsed = MarkdownActionCaretMarkup(markup)
        let result = MarkdownLinkCreation.wrapSelections(
            text: parsed.text,
            selections: parsed.selections,
            clipboard: clipboard,
            relativePathExists: { existingPaths.contains($0) }
        )
        return MarkdownActionCaretMarkup.render(result.text, result.selections)
    }

    private func unwrapped(_ markup: String) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        guard let result = MarkdownLinkCreation.unwrap(text: parsed.text, selections: parsed.selections) else {
            return nil
        }
        return MarkdownActionCaretMarkup.render(result.text, result.selections)
    }

    @Test func createsLinkInMarkdownText() {
        let actual = pasted("Some <selection>text</selection>")
        #expect(actual == "[text](https://example.com)")
    }

    @Test(arguments: [
        ("- *<selection>list item</selection>*", "[list item](https://example.com)"),
        ("| Column |\n| --- |\n| <selection>table cell</selection> |", "[table cell](https://example.com)"),
        ("[<selection>label</selection>]\n\nno definition", "[label](https://example.com)"),
        ("see <selection>words</selection> now\n\n[other]: https://old.example.com", "[words](https://example.com)")
    ])
    func createsLinkInFormattingContexts(markup: String, expected: String) {
        let actual = pasted(markup)
        #expect(actual == expected)
    }

    @Test func trimsPastedUrlIntoDestination() {
        let actual = pasted("Some <selection>text</selection>", "  https://example.com/a?b=c\n")
        #expect(actual == "[text](https://example.com/a?b=c)")
    }

    @Test(arguments: [
        "```\n<selection>some code</selection>\n```",
        "    <selection>some code</selection>",
        "`<selection>some code</selection>`",
        "[<selection>link text</selection>](https://old.example.com)",
        "<selection>[link](https://old.example.com)</selection>",
        "<selection>[link][label]</selection>\n\n[label]: https://old.example.com",
        "<selection>[label]</selection>\n\n[label]: https://old.example.com",
        "[link](<selection>https://old.example.com</selection>)",
        "<selection>https://old.example.com</selection>",
        "<<selection>https://old.example.com</selection>>",
        "<div>\n<selection>some text</selection>\n</div>",
        "---\ntitle: <selection>some text</selection>\n---",
        "Some <selection>   </selection> text",
        "see <selection>https://old.example.com/path</selection> now",
        "![<selection>alt text</selection>](image.png)",
        "[label]: <selection>https://old.example.com</selection>"
    ])
    func doesNotCreateLinkInIgnoredContexts(markup: String) {
        let actual = pasted(markup)
        #expect(actual == Self.pastedURL)
    }

    @Test(arguments: ["plain words", "example.com", "two words https://example.com", "relative/path.md"])
    func doesNotCreateLinkFromNonUrlClipboard(clipboard: String) {
        let actual = pasted("Some <selection>text</selection>", clipboard)
        #expect(actual == clipboard)
    }

    @Test func doesNotCreateLinkWithoutSelection() {
        let actual = pasted("Some <caret>text")
        #expect(actual == Self.pastedURL)
    }

    @Test(arguments: [
        ("https://example.com", "https://example.com"),
        ("  https://example.com/a?b=c#d \n", "https://example.com/a?b=c#d"),
        ("mailto:me@example.com", "mailto:me@example.com"),
        ("ftp://host/file", "ftp://host/file"),
        ("file:///tmp/a.md", "file:///tmp/a.md")
    ])
    func acceptsLinkDestination(candidate: String, expected: String) {
        let actual = MarkdownLinkCreation.linkDestination(from: candidate)
        #expect(actual == expected)
    }

    @Test(arguments: [
        "", "   ", "two words", "https://a b", "example.com", "relative/path.md", "/absolute/path", "#anchor",
        "?q:1", ":nothing"
    ])
    func rejectsLinkDestination(candidate: String) {
        let actual = MarkdownLinkCreation.linkDestination(from: candidate)
        #expect(actual == nil)
    }

    @Test func buildsInlineLink() {
        let actual = MarkdownLinkCreation.createInlineLink(text: "text", destination: "https://example.com")
        #expect(actual == "[text](https://example.com)")
    }

    @Test func wrapsPlainSelectionWithCaretInDestination() {
        let actual = wrapped("Some <selection>text</selection> here")
        #expect(actual == "Some [text](<caret>) here")
    }

    @Test func wrapsEmptySelectionIntoEmptyLink() {
        let actual = wrapped("a<caret>b")
        #expect(actual == "a[](<caret>)b")
    }

    @Test func wrapsUrlSelectionIntoDestinationWithCaretInText() {
        let actual = wrapped("<selection>https://example.com</selection>")
        #expect(actual == "[<caret>](https://example.com)")
    }

    @Test func urlSelectionIsTrimmedAndIgnoresClipboard() {
        let actual = wrapped("<selection> https://example.com </selection>", clipboard: "https://other.com")
        #expect(actual == "[<caret>](https://example.com)")
    }

    @Test func insertsClipboardUrlAndSelectsIt() {
        let actual = wrapped("<selection>text</selection>", clipboard: "https://example.com")
        #expect(actual == "[text](<selection>https://example.com</selection>)")
    }

    @Test func insertsClipboardMailtoAsLocalPathCheck() {
        let missing = wrapped("<selection>text</selection>", clipboard: "mailto:me@example.com")
        let existing = wrapped(
            "<selection>text</selection>",
            clipboard: "mailto:me@example.com",
            existingPaths: ["mailto:me@example.com"]
        )
        #expect(missing == "[text](<caret>)")
        #expect(existing == "[text](<selection>mailto:me@example.com</selection>)")
    }

    @Test func insertsExistingRelativePathFromClipboard() {
        let actual = wrapped(
            "<selection>docs</selection>",
            clipboard: "docs/readme.md",
            existingPaths: ["docs/readme.md"]
        )
        #expect(actual == "[docs](<selection>docs/readme.md</selection>)")
    }

    @Test(arguments: ["docs/missing.md", "just words", "", "https://a\nb"])
    func ignoresClipboardThatIsNeitherUrlNorExistingPath(clipboard: String) {
        let actual = wrapped("<selection>docs</selection>", clipboard: clipboard, existingPaths: ["docs/readme.md"])
        #expect(actual == "[docs](<caret>)")
    }

    @Test func ignoresMissingClipboard() {
        let actual = wrapped("<selection>docs</selection>", clipboard: nil)
        #expect(actual == "[docs](<caret>)")
    }

    @Test func wrapsEveryCaretAndShiftsLaterOnes() {
        let actual = wrapped("<selection>one</selection> and <selection>two</selection> and <caret>")
        #expect(actual == "[one](<caret>) and [two](<caret>) and [](<caret>)")
    }

    @Test func insertsClipboardForEveryCaret() {
        let actual = wrapped(
            "<selection>one</selection> and <selection>two</selection>",
            clipboard: "https://example.com"
        )
        let expected = "[one](<selection>https://example.com</selection>)"
            + " and [two](<selection>https://example.com</selection>)"
        #expect(actual == expected)
    }

    @Test func mixesUrlAndPlainSelectionsAcrossCarets() {
        let actual = wrapped(
            "<selection>https://a.io</selection> <selection>name</selection>",
            clipboard: "https://example.com"
        )
        #expect(actual == "[<caret>](https://a.io) [name](<selection>https://example.com</selection>)")
    }

    @Test func keepsSelectionOrderOfInput() {
        let parsed = MarkdownActionCaretMarkup("<selection>one</selection> <selection>two</selection>")
        let reversed = Array(parsed.selections.reversed())
        let result = MarkdownLinkCreation.wrapSelections(
            text: parsed.text,
            selections: reversed,
            clipboard: nil,
            relativePathExists: { _ in false }
        )
        let expected = [NSRange(location: 14, length: 0), NSRange(location: 6, length: 0)]
        #expect(result.text == "[one]() [two]()")
        #expect(result.selections == expected)
    }

    @Test func wrapReportsMinimalEdit() {
        let parsed = MarkdownActionCaretMarkup("a <selection>b</selection> c")
        let result = MarkdownLinkCreation.wrapSelections(
            text: parsed.text,
            selections: parsed.selections,
            clipboard: nil,
            relativePathExists: { _ in false }
        )
        let applied = result.applied(to: parsed.text)
        #expect(applied == "a [b]() c")
    }

    @Test(arguments: [
        ("[te<caret>xt](https://example.com)", "te<caret>xt"),
        ("[text<caret>](https://example.com)", "text<caret>"),
        ("[<caret>text](https://example.com)", "<caret>text"),
        ("[text](https://exa<caret>mple.com)", "text<caret>"),
        ("[text](<caret>https://example.com)", "text<caret>"),
        ("[text]<caret>(https://example.com)", "text<caret>"),
        ("a [te<caret>xt](u) b", "a te<caret>xt b"),
        ("[<selection>te</selection>xt](https://example.com)", "<selection>te</selection>xt"),
        ("[t<selection>ex</selection>t](https://example.com)", "t<selection>ex</selection>t"),
        ("<selection>[text](https://example.com)</selection>", "<selection>text</selection>"),
        ("[text](<selection>https://example.com</selection>)", "text<caret>"),
        ("[a<caret>b](http://x.y<caret>)", "a<caret>b<caret>"),
        ("[a<caret>](u) and [b<caret>](v)", "a<caret> and b<caret>"),
        ("[a](u) [<caret>b](v) [c](w)", "[a](u) <caret>b [c](w)"),
        ("| [te<caret>xt](https://example.com) |", "| te<caret>xt |"),
        ("- [te<caret>xt](https://example.com)", "- te<caret>xt"),
        ("# [te<caret>xt](https://example.com)", "# te<caret>xt"),
        ("[a **b<caret>** c](https://example.com)", "a **b<caret>** c"),
        ("[](https://example.com<caret>)", "<caret>")
    ])
    func unwrapsLinks(markup: String, expected: String) {
        let actual = unwrapped(markup)
        #expect(actual != nil)
        #expect(actual == expected)
    }

    @Test(arguments: [
        "[te<caret>xt](https://example.com)",
        "[<selection>te</selection>xt](https://example.com)",
        "[a<caret>](u) and [b<caret>](v)",
        "[a<caret>b](http://x.y<caret>)"
    ])
    func canUnwrapWhenEveryCaretIsInsideLink(markup: String) {
        let parsed = MarkdownActionCaretMarkup(markup)
        let actual = MarkdownLinkCreation.canUnwrap(text: parsed.text, selections: parsed.selections)
        #expect(actual)
    }

    @Test(arguments: [
        "plain <caret>text",
        "![img<caret>](https://example.com/a.png)",
        "<caret>[text](https://example.com)",
        "[text](https://example.com)<caret>",
        "[text](https://example.com) <caret>",
        "[te<caret>xt][ref]\n\n[ref]: https://example.com",
        "[te<caret>xt]",
        "`[te<caret>xt](u)`",
        "<https://exa<caret>mple.com>",
        "[a<caret>](u) and plain<caret>",
        "[a](u) and <caret>",
        "[te<selection>xt](https://example.com) and pl</selection>ain",
        "```\n[te<caret>xt](u)\n```"
    ])
    func rejectsUnwrapWhenAnyCaretIsOutsideLink(markup: String) {
        let parsed = MarkdownActionCaretMarkup(markup)
        let canUnwrap = MarkdownLinkCreation.canUnwrap(text: parsed.text, selections: parsed.selections)
        let result = MarkdownLinkCreation.unwrap(text: parsed.text, selections: parsed.selections)
        #expect(!canUnwrap)
        #expect(result == nil)
    }

    @Test func rejectsUnwrapWithoutCarets() {
        let canUnwrap = MarkdownLinkCreation.canUnwrap(text: "[a](u)", selections: [])
        let result = MarkdownLinkCreation.unwrap(text: "[a](u)", selections: [])
        #expect(!canUnwrap)
        #expect(result == nil)
    }

    @Test func unwrapResultCarriesTextAndEdit() {
        let parsed = MarkdownActionCaretMarkup("x [te<caret>xt](https://example.com) y")
        let result = MarkdownLinkCreation.unwrap(text: parsed.text, selections: parsed.selections)
        let applied = result?.applied(to: parsed.text)
        #expect(result?.text == "x text y")
        #expect(applied == "x text y")
    }

    @Test func unwrapsDistinctLinksOnceWhenCaretsShareLink() {
        let parsed = MarkdownActionCaretMarkup("[a<caret>b](http://x.y<caret>) [c<caret>](v)")
        let result = MarkdownLinkCreation.unwrap(text: parsed.text, selections: parsed.selections)
        let rendered = result.map { MarkdownActionCaretMarkup.render($0.text, $0.selections) }
        #expect(rendered == "a<caret>b<caret> c<caret>")
    }
}
