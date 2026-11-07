import Foundation
import Testing
@testable import Dreamder

struct MarkdownEditorCommandTests {
    private func run(
        _ command: MarkdownEditorCommand,
        _ markup: String,
        environment: MarkdownEditorEnvironment = MarkdownEditorEnvironment()
    ) -> String? {
        let parsed = MarkdownActionCaretMarkup(markup)
        let result = MarkdownEditorCommandRunner.run(
            command,
            text: parsed.text,
            selections: parsed.selections,
            environment: environment
        )
        return result.map { MarkdownActionCaretMarkup.render($0.text, $0.selections) }
    }

    @Test
    func boldWrapsTheSelection() {
        let output = run(.toggle(.bold), "say <selection>hello</selection> now")

        #expect(output == "say **<selection>hello</selection>** now")
    }

    @Test
    func italicFollowsTheEmphasisStyleOfTheEnvironment() {
        var environment = MarkdownEditorEnvironment()
        environment.emphasisStyle = .underscores

        let output = run(.toggle(.italic), "Simple <selection>test</selection> text", environment: environment)

        #expect(output == "Simple _<selection>test</selection>_ text")
    }

    @Test
    func toggleIsRefusedInsideFencedCode() {
        let output = run(.toggle(.bold), "```\n<selection>code</selection>\n```")

        #expect(output == nil)
    }

    @Test
    func createLinkWrapsSelectionAndFillsClipboardUrl() {
        var environment = MarkdownEditorEnvironment()
        environment.clipboard = { "https://example.com" }

        let output = run(.createLink, "<selection>docs</selection>", environment: environment)

        #expect(output == "[docs](<selection>https://example.com</selection>)")
    }

    @Test
    func createLinkWithoutClipboardPlacesCaretAfterParenthesis() {
        let output = run(.createLink, "<selection>docs</selection>")

        #expect(output == "[docs](<caret>)")
    }

    @Test
    func createLinkUnwrapsWhenCaretIsInsideLink() {
        let output = run(.createLink, "see [do<caret>cs](https://example.com) now")

        #expect(output == "see do<caret>cs now")
    }

    @Test
    func headerLevelSetsAtxPrefix() {
        let output = run(.headerLevel(2), "Some <caret>title")

        #expect(output == "## Some <caret>title")
    }

    @Test
    func headerUpAndDownAdjustTheLevel() {
        let up = run(.headerUp, "## <caret>Title")
        let down = run(.headerDown, "## <caret>Title")

        #expect(up == "# <caret>Title")
        #expect(down == "### <caret>Title")
    }

    @Test
    func headerUpIsRefusedOnPlainText() {
        let output = run(.headerUp, "plain <caret>text")

        #expect(output == nil)
    }

    @Test
    func insertTableAtEmptyDocumentUsesTheEnvironmentStyle() {
        let aligned = run(.insertTable(contentRows: 1, columns: 2), "<caret>")
        var compact = MarkdownEditorEnvironment()
        compact.tableStyle = .compact
        let compactOutput = run(.insertTable(contentRows: 1, columns: 2), "<caret>", environment: compact)

        #expect(aligned == "|<caret>   |   |\n|---|---|\n|   |   |\n")
        #expect(compactOutput == "|<caret> | |\n| --- | --- |\n| | |\n")
    }

    @Test
    func formatTableRewritesTheTableAtTheCaret() {
        let output = run(.formatTable, "| a |bb|\n|---|---|\n| 1<caret> |2|\n")

        #expect(output == "| a | bb |\n|---|----|\n| 1<caret> | 2  |\n")
    }

    @Test
    func formatTableIsRefusedOutsideTables() {
        let output = run(.formatTable, "no <caret>table here")

        #expect(output == nil)
    }

    @Test
    func tableOfContentsIsInsertedAtTheCaret() {
        var environment = MarkdownEditorEnvironment()
        environment.indentSize = 2
        let output = run(.generateTableOfContents, "<caret>\n# Intro\n\n## Part\n", environment: environment)

        #expect(output?.contains("<!-- TOC -->\n* [Intro](#intro)\n  * [Part](#part)\n<!-- TOC -->") == true)
    }

    @Test
    func tableOfContentsHonoursTheIndentSize() {
        var environment = MarkdownEditorEnvironment()
        environment.indentSize = 4

        let output = run(.generateTableOfContents, "<caret>\n# Intro\n\n## Part\n", environment: environment)

        #expect(output?.contains("\n    * [Part](#part)\n") == true)
    }

    @Test
    func relativePathPredicateDecidesWhetherClipboardPathIsUsed() {
        var environment = MarkdownEditorEnvironment()
        environment.clipboard = { "docs/guide.md" }
        environment.relativePathExists = { $0 == "docs/guide.md" }

        let output = run(.createLink, "<selection>guide</selection>", environment: environment)

        #expect(output == "[guide](<selection>docs/guide.md</selection>)")
    }
}
