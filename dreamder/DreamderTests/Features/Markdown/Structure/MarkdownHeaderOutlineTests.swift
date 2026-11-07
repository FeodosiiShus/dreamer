import Foundation
import Testing

@testable import Dreamder

struct MarkdownHeaderOutlineTests {
    private func render(_ text: String) -> String {
        var lines: [String] = []
        func append(_ nodes: [MarkdownHeaderNode], depth: Int) {
            for node in nodes {
                let marker = node.children.isEmpty ? "" : "-"
                lines.append(String(repeating: " ", count: depth + 1) + marker + node.title)
                append(node.children, depth: depth + 1)
            }
        }
        append(MarkdownHeaderOutline.nodes(in: text), depth: 0)
        return lines.joined(separator: "\n")
    }

    private func dump(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }

    private func describe(_ nodes: [StructureNode]) -> String {
        var parts: [String] = []
        for node in nodes {
            let start = node.rangeStartLine ?? -1
            let end = node.rangeEndLine ?? -1
            var part = "\(node.name):\(start)-\(end)"
            if !node.children.isEmpty {
                part += "[" + describe(node.children) + "]"
            }
            parts.append(part)
        }
        return parts.joined(separator: ",")
    }

    @Test func oneParagraph() {
        let text = "Just one paragraph of text."
        #expect(render(text) == "")
        #expect(MarkdownHeaderOutline.nodes(in: text).isEmpty)
    }

    @Test func twoParagraphs() {
        let text = "First paragraph.\n\nSecond paragraph\ncontinues here."
        #expect(render(text) == "")
        #expect(MarkdownHeaderOutline.entries(in: text).isEmpty)
    }

    @Test func normalATXDocument() {
        let text = [
            "# Header 1",
            "## Header 2",
            "### Header 3",
            "#### Header 4",
            "##### Header 5",
            "###### Header 6",
            "###### Header 6#2",
            "##### Header 5",
            "###### Header 6",
            "###### Header 6#2",
            "#### Header 4",
            "### Header 3",
            "#### Header 4",
            "## Header 2",
            "# Header 1",
        ].joined(separator: "\n")
        let expected = dump([
            " -Header 1",
            "  -Header 2",
            "   -Header 3",
            "    -Header 4",
            "     -Header 5",
            "      Header 6",
            "      Header 6#2",
            "     -Header 5",
            "      Header 6",
            "      Header 6#2",
            "    Header 4",
            "   -Header 3",
            "    Header 4",
            "  Header 2",
            " Header 1",
        ])
        #expect(render(text) == expected)
    }

    @Test func normalSetextDocument() {
        let text = [
            "Header 1", "========", "",
            "Header 2", "--------", "",
            "Header 1", "========", "",
            "Header 2", "--------", "",
            "Header 1", "========",
        ].joined(separator: "\n")
        let expected = dump([
            " -Header 1",
            "  Header 2",
            " -Header 1",
            "  Header 2",
            " Header 1",
        ])
        #expect(render(text) == expected)
    }

    @Test func headersLadder() {
        let text = [
            "###### h6", "##### h5", "#### h4", "### h3", "## h2",
            "# h1", "## h2", "### h3", "#### h4", "##### h5", "###### h6",
            "##### h5", "#### h4", "### h3", "## h2",
            "# h1", "## h2", "### h3", "#### h4", "##### h5", "###### h6",
        ].joined(separator: "\n")
        let expected = dump([
            " h6",
            " h5",
            " h4",
            " h3",
            " h2",
            " -h1",
            "  -h2",
            "   -h3",
            "    -h4",
            "     -h5",
            "      h6",
            "     h5",
            "    h4",
            "   h3",
            "  h2",
            " -h1",
            "  -h2",
            "   -h3",
            "    -h4",
            "     -h5",
            "      h6",
        ])
        #expect(render(text) == expected)
    }

    @Test func headersUnderBlockquotesAndLists() {
        let text = [
            "# A list",
            "",
            "* ## Subsection",
            "  * ### Subsubsection",
            "  * #### H4 here",
            "* ## And one more h2",
            "",
            "> ## Testing under blockquotes",
            "> ### A quoted susbection",
            "",
            "## One more h1",
            "## Should this h2 be under previous section?",
            "### This h1",
        ].joined(separator: "\n")
        let expected = dump([
            " -A list",
            "  -Subsection",
            "   Subsubsection",
            "   H4 here",
            "  And one more h2",
            "  -Testing under blockquotes",
            "   A quoted susbection",
            "  One more h1",
            "  -Should this h2 be under previous section?",
            "   This h1",
        ])
        #expect(render(text) == expected)
    }

    @Test func headerWithLink() {
        let text = "# [Tutorial](http://example.com)"
        #expect(render(text) == " Tutorial")
    }

    @Test func headersWithHtmlTags() {
        let text = [
            "# my title <i>in MD</i> file",
            "## my head<b>1</b>",
            "# <img src=\"a.png\">",
        ].joined(separator: "\n")
        let expected = dump([
            " -my title in MD file",
            "  my head1",
            " Invalid header: # <img src=\"a.png\">",
        ])
        #expect(render(text) == expected)
    }

    @Test func headersWithImages() {
        let text = [
            "# Links[a](http://a.com)",
            "# ![Logo](logo.png)",
            "# ![Logo][logo]",
            "# ![Logo]",
        ].joined(separator: "\n")
        let expected = dump([" Linksa", " Logo", " Logo", " Logo"])
        #expect(render(text) == expected)
    }

    @Test func puppetlabsCoreTypes() {
        let text = [
            "# Core Types Cheat Sheet",
            "",
            "## The Trifecta",
            "",
            "### [file][]",
            "#### Important Attributes",
            "#### For Normal Files",
            "#### For Directories",
            "#### For Symlinks",
            "#### Other Notable Attributes",
            "",
            "### [package][]",
            "#### Important Attributes",
            "",
            "### [service][]",
            "#### Important Attributes",
            "#### Other Notable Attributes",
            "",
            "## Hello World",
            "",
            "### [[notify][]]",
            "#### Important Attributes",
            "",
            "## Grab Bag",
            "",
            "### [exec][]",
            "#### Important Attributes",
            "#### Attributes to Limit When a Command Should Run",
            "#### Other Notable Attributes:",
            "",
            "### [cron][]",
            "#### Important Attributes",
            "#### Other Notable Attributes",
            "",
            "### [user][]",
            "#### Important Attributes",
            "#### Other Notable Attributes",
            "",
            "### [group][]",
            "#### Important Attributes",
            "",
            "## Everything Else",
        ].joined(separator: "\n")
        let expected = dump([
            " -Core Types Cheat Sheet",
            "  -The Trifecta",
            "   -[file][]",
            "    Important Attributes",
            "    For Normal Files",
            "    For Directories",
            "    For Symlinks",
            "    Other Notable Attributes",
            "   -[package][]",
            "    Important Attributes",
            "   -[service][]",
            "    Important Attributes",
            "    Other Notable Attributes",
            "  -Hello World",
            "   -[[notify][]]",
            "    Important Attributes",
            "  -Grab Bag",
            "   -[exec][]",
            "    Important Attributes",
            "    Attributes to Limit When a Command Should Run",
            "    Other Notable Attributes:",
            "   -[cron][]",
            "    Important Attributes",
            "    Other Notable Attributes",
            "   -[user][]",
            "    Important Attributes",
            "    Other Notable Attributes",
            "   -[group][]",
            "    Important Attributes",
            "  Everything Else",
        ])
        #expect(render(text) == expected)
    }

    @Test func levelSixIsAlwaysLeaf() {
        let text = "###### h6\n####### not a header\n\ntext"
        let nodes = MarkdownHeaderOutline.nodes(in: text)
        #expect(nodes.count == 1)
        #expect(nodes.first?.level == 6)
        #expect(nodes.first?.title == "h6")
        #expect(nodes.first?.children.isEmpty == true)
    }

    @Test func deeperHeaderBeforeShallowerGivesSiblings() {
        let text = "### a\n## b\n# c"
        #expect(render(text) == dump([" a", " b", " c"]))
    }

    @Test func laterDeeperHeadersAllBecomeChildren() {
        let text = "# a\n### c\n## b"
        #expect(render(text) == dump([" -a", "  c", "  b"]))
    }

    @Test func skippedLevelsNestUnderParent() {
        let text = "# a\n#### d"
        #expect(render(text) == dump([" -a", "  d"]))
    }

    @Test func setextAndAtxMixed() {
        let text = "Setext\n---\n# atx\nOther\n===\n## two"
        let expected = dump([" Setext", " atx", " -Other", "  two"])
        #expect(render(text) == expected)
        let levels = MarkdownHeaderOutline.entries(in: text).map(\.level)
        #expect(levels == [2, 1, 1, 2])
    }

    @Test func headerInNestedBlockQuotes() {
        let text = "> > ## x\n\n# y"
        let titles = MarkdownHeaderOutline.entries(in: text).map(\.title)
        #expect(titles == ["x", "y"])
        let entries = MarkdownHeaderOutline.entries(in: "> > ## x")
        #expect(entries.first?.title == "x")
        #expect(entries.first?.range == NSRange(location: 4, length: 4))
        #expect(entries.first?.depth == 0)
    }

    @Test func headerInListItemAfterText() {
        let text = "* item\n  text\n  ## inner after text\n\n# h"
        let entries = MarkdownHeaderOutline.entries(in: text)
        let titles = entries.map(\.title)
        let lines = entries.map(\.line)
        #expect(titles == ["inner after text", "h"])
        #expect(lines == [3, 5])
    }

    @Test func fencedCodeIsIgnored() {
        let text = "```\n# not a header\n```\n\n# real"
        let titles = MarkdownHeaderOutline.entries(in: text).map(\.title)
        #expect(titles == ["real"])
    }

    @Test func htmlCommentAndHtmlBlockAreIgnored() {
        let text = "x\n\n<!--\n# hidden\n-->\n\n<div>\n# in html\n</div>\n\n# ok"
        let entries = MarkdownHeaderOutline.entries(in: text)
        let titles = entries.map(\.title)
        let lines = entries.map(\.line)
        #expect(titles == ["ok"])
        #expect(lines == [11])
    }

    @Test func frontMatterIsNotHeader() {
        let text = "---\ntitle: t\n---\n# real"
        let entries = MarkdownHeaderOutline.entries(in: text)
        let titles = entries.map(\.title)
        let lines = entries.map(\.line)
        #expect(titles == ["real"])
        #expect(lines == [4])
    }

    @Test func trailingClosingHashesAreDropped() {
        let nodes = MarkdownHeaderOutline.nodes(in: "## x ##")
        #expect(nodes.count == 1)
        #expect(nodes.first?.title == "x")
        #expect(nodes.first?.level == 2)
    }

    @Test func emptyHeaderIsInvalid() {
        let nodes = MarkdownHeaderOutline.nodes(in: "#")
        #expect(nodes.count == 1)
        #expect(nodes.first?.title == "Invalid header: #")
    }

    @Test func linesAndRangesCoverWholeHeaderBlock() {
        let text = "# a\n\nSetext\n---\n## b"
        let entries = MarkdownHeaderOutline.entries(in: text)
        let lines = entries.map(\.line)
        let ranges = entries.map(\.range)
        let sources = ranges.map { (text as NSString).substring(with: $0) }
        #expect(lines == [1, 3, 5])
        #expect(ranges == [NSRange(location: 0, length: 3), NSRange(location: 5, length: 10), NSRange(location: 16, length: 4)])
        #expect(sources == ["# a", "Setext\n---", "## b"])
    }

    @Test func entriesDepthMatchesTreeAndKeepsDocumentOrder() {
        let text = "# a\n## b\n### c\n## d\n# e"
        let entries = MarkdownHeaderOutline.entries(in: text)
        let titles = entries.map(\.title)
        let depths = entries.map(\.depth)
        let lines = entries.map(\.line)
        #expect(titles == ["a", "b", "c", "d", "e"])
        #expect(depths == [0, 1, 2, 1, 0])
        #expect(lines == [1, 2, 3, 4, 5])
    }

    @Test func crlfInputGivesSameTitlesAndLines() {
        let text = "# a\r\n## b\r\n\r\nSet\r\n---"
        let entries = MarkdownHeaderOutline.entries(in: text)
        let titles = entries.map(\.title)
        let lines = entries.map(\.line)
        let depths = entries.map(\.depth)
        #expect(titles == ["a", "b", "Set"])
        #expect(lines == [1, 2, 4])
        #expect(depths == [0, 1, 1])
    }

    @Test func unicodeTitleWithEmoji() {
        let text = "# 😀 emoji\n## next"
        let entries = MarkdownHeaderOutline.entries(in: text)
        let titles = entries.map(\.title)
        let ranges = entries.map(\.range)
        #expect(titles == ["😀 emoji", "next"])
        #expect(ranges == [NSRange(location: 0, length: 10), NSRange(location: 11, length: 7)])
    }

    @Test(arguments: [
        ("# Strong **Header**", "Strong **Header**"),
        ("# `code` x", "`code` x"),
        ("# *em* and ~~gone~~", "*em* and ~~gone~~"),
    ])
    func emphasisAndCodeKeepRawMarkers(source: String, title: String) {
        let nodes = MarkdownHeaderOutline.nodes(in: source)
        #expect(nodes.count == 1)
        #expect(nodes.first?.title == title)
    }

    @Test(arguments: ["md", "markdown", "MD", "Markdown"])
    func symbolExtractorReturnsHeadersAsFields(fileExtension: String) {
        let text = "# a\n\n## b\ntext\n### c\n## d\n# e"
        let symbols = SymbolExtractor.symbols(in: text, fileExtension: fileExtension)
        let expected = [
            ExtractedSymbol(name: "a", kind: .field, line: 1, nestingLevel: 0),
            ExtractedSymbol(name: "b", kind: .field, line: 3, nestingLevel: 1),
            ExtractedSymbol(name: "c", kind: .field, line: 5, nestingLevel: 2),
            ExtractedSymbol(name: "d", kind: .field, line: 6, nestingLevel: 1),
            ExtractedSymbol(name: "e", kind: .field, line: 7, nestingLevel: 0),
        ]
        #expect(symbols == expected)
    }

    @Test func symbolExtractorIgnoresOtherExtensions() {
        let symbols = SymbolExtractor.symbols(in: "# a\n## b", fileExtension: "txt")
        #expect(symbols.isEmpty)
    }

    @Test func structureTreeNestsHeadersWithRanges() {
        let text = "# a\n## b\n### c\n## d\n# e"
        let symbols = SymbolExtractor.symbols(in: text, fileExtension: "md")
        let nodes = StructureTreeBuilder.nodes(from: symbols, text: text)
        let names = nodes.map(\.name)
        let kinds = nodes.map(\.kind)
        #expect(names == ["a", "e"])
        #expect(kinds == [.field, .field])
        #expect(describe(nodes) == "a:1-4[b:2-3[c:3-3],d:4-4],e:5-5")
        let firstChildren = nodes.first?.children.map(\.name)
        #expect(firstChildren == ["b", "d"])
        let lines = nodes.first?.children.map(\.line)
        #expect(lines == [2, 4])
    }

    @Test func structureTreeRangesExtendToLastLine() {
        let text = "# a\ntext\nmore\n## b\ntail\nend"
        let symbols = SymbolExtractor.symbols(in: text, fileExtension: "markdown")
        let nodes = StructureTreeBuilder.nodes(from: symbols, text: text)
        #expect(describe(nodes) == "a:1-6[b:4-6]")
    }
}
