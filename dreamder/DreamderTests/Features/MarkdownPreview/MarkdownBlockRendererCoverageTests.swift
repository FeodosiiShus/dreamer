import Foundation
import Testing
@testable import Dreamder

private struct BlockCase {
    let markdown: String
    let html: String
}

private func blockPlain(_ markdown: String) -> String {
    MarkdownPreviewTestSupport.plainHTML(markdown)
}

private func expectBlockCases(_ cases: [BlockCase]) {
    for entry in cases {
        #expect(blockPlain(entry.markdown) == entry.html, "\(entry.markdown.debugDescription)")
    }
}

@Suite
struct MarkdownBlockRendererCoverageTests {
    @Test
    func blockQuoteContinuesAcrossBlankLineBeforeQuotedLine() {
        expectBlockCases([
            BlockCase(
                markdown: "> a\n\n> b",
                html: "<blockquote>\n<p>a</p>\n<p>b</p>\n</blockquote>"
            ),
            BlockCase(
                markdown: "> a\n\nplain",
                html: "<blockquote>\n<p>a</p>\n</blockquote>\n<p>plain</p>"
            )
        ])
    }

    @Test
    func atxHeadingEdgeCases() {
        expectBlockCases([
            BlockCase(markdown: "#hashtag", html: "<p>#hashtag</p>"),
            BlockCase(markdown: "# foo ##", html: "<h1>foo</h1>"),
            BlockCase(markdown: "# foo\t##", html: "<h1>foo</h1>"),
            BlockCase(markdown: "#\tfoo", html: "<h1>foo</h1>"),
            BlockCase(markdown: "# #", html: "<h1></h1>"),
            BlockCase(markdown: "# foo#", html: "<h1>foo#</h1>"),
            BlockCase(markdown: "#", html: "<h1></h1>")
        ])
    }

    @Test
    func listMarkerVariants() {
        expectBlockCases([
            BlockCase(markdown: " - a\n - b", html: "<ul>\n<li>a</li>\n<li>b</li>\n</ul>"),
            BlockCase(markdown: "1) a", html: "<ol>\n<li>a</li>\n</ol>"),
            BlockCase(markdown: "1abc", html: "<p>1abc</p>"),
            BlockCase(markdown: "-      code", html: "<ul>\n<li>code</li>\n</ul>"),
            BlockCase(markdown: "-\n- b", html: "<ul>\n<li></li>\n<li>b</li>\n</ul>"),
            BlockCase(markdown: "- \n- b", html: "<ul>\n<li></li>\n<li>b</li>\n</ul>"),
            BlockCase(markdown: "\u{663}. x", html: "<ol start=\"0\">\n<li>x</li>\n</ol>")
        ])
    }

    @Test
    func listLazyContinuationAndInterruption() {
        expectBlockCases([
            BlockCase(markdown: "- a\nlazy\n- b", html: "<ul>\n<li>a\nlazy</li>\n<li>b</li>\n</ul>"),
            BlockCase(markdown: "- a\n lazy", html: "<ul>\n<li>a\nlazy</li>\n</ul>"),
            BlockCase(markdown: "- a\n# h", html: "<ul>\n<li>a</li>\n</ul>\n<h1>h</h1>")
        ])
    }

    @Test
    func taskListItems() {
        let markdown = "- [X] done\n- [x]nope\n- [y] no\n- [ ] open"
        let html = "<ul>\n"
            + "<li class=\"task-list-item\"><input type=\"checkbox\" disabled checked> done</li>\n"
            + "<li>[x]nope</li>\n"
            + "<li>[y] no</li>\n"
            + "<li class=\"task-list-item\"><input type=\"checkbox\" disabled> open</li>\n"
            + "</ul>"
        #expect(blockPlain(markdown) == html)
    }

    @Test
    func tablesFallBackToParagraphsWhenStructureIsInvalid() {
        expectBlockCases([
            BlockCase(markdown: "a | b\nc", html: "<p>a | b\nc</p>"),
            BlockCase(markdown: "a|b|c\n-|-", html: "<p>a|b|c\n-|-</p>"),
            BlockCase(markdown: "a|b|c\n-||-", html: "<p>a|b|c\n-||-</p>"),
            BlockCase(markdown: "a|b\n-|x-", html: "<p>a|b\n-|x-</p>")
        ])
    }

    @Test
    func tableRowsEndAtLinesWithoutPipes() {
        let html = "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n"
            + "<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n<p>plain</p>"
        #expect(blockPlain("a|b\n-|-\n1|2\nplain") == html)
    }

    @Test
    func tableRowPadsMissingCells() {
        let html = "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n<th>c</th>\n</tr>\n</thead>\n"
            + "<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n<td></td>\n</tr>\n</tbody>\n</table>"
        #expect(blockPlain("a|b|c\n-|-|-\n1|2") == html)
    }

    @Test
    func tableCellEscapes() {
        let html = "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n"
            + "<tbody>\n<tr>\n<td>\\x</td>\n<td>c|d</td>\n</tr>\n<tr>\n<td>1</td>\n<td>2|</td>\n</tr>\n</tbody>\n</table>"
        #expect(blockPlain("a|b\n-|-\n\\x|c\\|d\n1|2\\|") == html)
    }

    @Test
    func tableAlignments() {
        let html = "<table>\n<thead>\n<tr>\n"
            + "<th style=\"text-align: left\">a</th>\n"
            + "<th style=\"text-align: right\">b</th>\n"
            + "<th style=\"text-align: center\">c</th>\n"
            + "<th>d</th>\n"
            + "</tr>\n</thead>\n</table>"
        #expect(blockPlain("a|b|c|d\n:-|-:|:-:|-") == html)
    }

    @Test
    func htmlBlockVariants() {
        expectBlockCases([
            BlockCase(markdown: " <div>x</div>", html: " <div>x</div>"),
            BlockCase(markdown: "<!", html: "<p>&lt;!</p>"),
            BlockCase(markdown: "<!1 x", html: "<p>&lt;!1 x</p>"),
            BlockCase(markdown: "<pre class=x>\ncode\n</pre>", html: "<pre class=x>\ncode\n</pre>"),
            BlockCase(markdown: "<custom-tag>   ", html: "<custom-tag>   "),
            BlockCase(markdown: "<custom-tag> text", html: "<p><custom-tag> text</p>")
        ])
    }

    @Test
    func codeBlockVariants() {
        expectBlockCases([
            BlockCase(markdown: "\tlet a = 1\n\tlet b", html: "<pre><code>let a = 1\nlet b\n</code></pre>"),
            BlockCase(markdown: "``` a`b", html: "<p>``` a`b</p>"),
            BlockCase(markdown: "```\nx\n```   \ny", html: "<pre><code>x\n</code></pre>\n<p>y</p>"),
            BlockCase(
                markdown: "```\nx\n``` y\nz\n```",
                html: "<pre><code>x\n``` y\nz\n</code></pre>"
            )
        ])
    }

    @Test
    func paragraphIsInterruptedByBlockStarts() {
        expectBlockCases([
            BlockCase(markdown: "a\n```\ncode\n```", html: "<p>a</p>\n<pre><code>code\n</code></pre>"),
            BlockCase(markdown: "a\n# h", html: "<p>a</p>\n<h1>h</h1>"),
            BlockCase(markdown: "a\n***", html: "<p>a</p>\n<hr />"),
            BlockCase(markdown: "a\n> q", html: "<p>a</p>\n<blockquote>\n<p>q</p>\n</blockquote>"),
            BlockCase(markdown: "a\n- x", html: "<p>a</p>\n<ul>\n<li>x</li>\n</ul>"),
            BlockCase(markdown: "a\n<div>", html: "<p>a</p>\n<div>")
        ])
    }

    @Test
    func indentedLineContinuesParagraph() {
        expectBlockCases([
            BlockCase(markdown: "a\n    b", html: "<p>a\nb</p>"),
            BlockCase(markdown: "- a\n    b", html: "<ul>\n<li>a\nb</li>\n</ul>")
        ])
    }
}
