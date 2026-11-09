import Foundation
import Testing
@testable import Dreamder

func plainHTML(_ markdown: String) -> String {
    MarkdownPreviewTestSupport.plainHTML(markdown)
}

@Suite
struct MarkdownHTMLRendererTests {
    @Test
    func atxHeadings() {
        let markdown = "## Sub ##\n####### not heading"
        let html = plainHTML(markdown)
        #expect(html == "<h2>Sub</h2>\n<p>####### not heading</p>")
    }

    @Test
    func atxHeadingLevels() {
        let html = plainHTML("# One\n### Three\n###### Six")
        #expect(html == "<h1>One</h1>\n<h3>Three</h3>\n<h6>Six</h6>")
    }

    @Test
    func setextHeadings() {
        let html = plainHTML("Title\n=====\n\nSub\n---")
        #expect(html == "<h1>Title</h1>\n<h2>Sub</h2>")
    }

    @Test
    func paragraphsJoinLines() {
        let html = plainHTML("first line\nsecond line\n\nnext paragraph")
        #expect(html == "<p>first line\nsecond line</p>\n<p>next paragraph</p>")
    }

    @Test
    func emphasisAndStrong() {
        let html = plainHTML("*em* **strong** ***both***")
        #expect(html == "<p><em>em</em> <strong>strong</strong> <em><strong>both</strong></em></p>")
    }

    @Test
    func nestedEmphasis() {
        let html = plainHTML("**bold *italic***")
        #expect(html == "<p><strong>bold <em>italic</em></strong></p>")
    }

    @Test
    func intrawordUnderscoresStayLiteral() {
        let html = plainHTML("a_b_c and _em_")
        #expect(html == "<p>a_b_c and <em>em</em></p>")
    }

    @Test
    func unmatchedDelimiterStaysLiteral() {
        let html = plainHTML("a * b")
        #expect(html == "<p>a * b</p>")
    }

    @Test
    func codeSpans() {
        let html = plainHTML("call `print(\"hi\")` now")
        #expect(html == "<p>call <code>print(&quot;hi&quot;)</code> now</p>")
    }

    @Test
    func codeSpanKeepsMarkdownLiteral() {
        let html = plainHTML("`a *b* [c](d)`")
        #expect(html == "<p><code>a *b* [c](d)</code></p>")
    }

    @Test
    func fencedCodeBlock() {
        let markdown = "```swift\nlet a = 1 < 2\n```"
        let html = plainHTML(markdown)
        #expect(html == "<pre><code class=\"language-swift\">let a = 1 &lt; 2\n</code></pre>")
    }

    @Test
    func fencedCodeBlockWithoutInfo() {
        let html = plainHTML("```\nplain `code`\n```")
        #expect(html == "<pre><code>plain `code`\n</code></pre>")
    }

    @Test
    func indentedCodeBlock() {
        let html = plainHTML("    let a = 1\n    let b = 2")
        #expect(html == "<pre><code>let a = 1\nlet b = 2\n</code></pre>")
    }

    @Test
    func blockQuote() {
        let html = plainHTML("> quoted")
        #expect(html == "<blockquote>\n<p>quoted</p>\n</blockquote>")
    }

    @Test
    func nestedBlockQuote() {
        let html = plainHTML("> quoted\n> > nested")
        #expect(html == "<blockquote>\n<p>quoted</p>\n<blockquote>\n<p>nested</p>\n</blockquote>\n</blockquote>")
    }

    @Test
    func unorderedList() {
        let html = plainHTML("- one\n- two\n- three")
        #expect(html == "<ul>\n<li>one</li>\n<li>two</li>\n<li>three</li>\n</ul>")
    }

    @Test
    func orderedList() {
        let html = plainHTML("1. one\n2. two")
        #expect(html == "<ol>\n<li>one</li>\n<li>two</li>\n</ol>")
    }

    @Test
    func orderedListKeepsStartNumber() {
        let html = plainHTML("3. three\n4. four")
        #expect(html == "<ol start=\"3\">\n<li>three</li>\n<li>four</li>\n</ol>")
    }

    @Test
    func nestedList() {
        let html = plainHTML("- a\n  - b\n  - c\n- d")
        #expect(html == "<ul>\n<li>a<ul>\n<li>b</li>\n<li>c</li>\n</ul></li>\n<li>d</li>\n</ul>")
    }

    @Test
    func looseListKeepsParagraphs() {
        let html = plainHTML("- a\n\n- b")
        #expect(html == "<ul>\n<li><p>a</p></li>\n<li><p>b</p></li>\n</ul>")
    }

    @Test
    func taskList() {
        let html = plainHTML("- [ ] open\n- [x] done")
        #expect(html == """
        <ul>
        <li class="task-list-item"><input type="checkbox" disabled> open</li>
        <li class="task-list-item"><input type="checkbox" disabled checked> done</li>
        </ul>
        """)
    }

    @Test
    func links() {
        let html = plainHTML("[site](https://example.com \"Title\")")
        #expect(html == "<p><a href=\"https://example.com\" title=\"Title\">site</a></p>")
    }

    @Test
    func linkWithBoldLabel() {
        let html = plainHTML("[**bold**](a.md)")
        #expect(html == "<p><a href=\"a.md\"><strong>bold</strong></a></p>")
    }

    @Test
    func relativeImage() {
        let html = plainHTML("![logo](images/logo.png)")
        #expect(html == "<p><img src=\"images/logo.png\" alt=\"logo\" /></p>")
    }

    @Test
    func imageInsideLink() {
        let html = plainHTML("[![b](i.png)](https://x.y)")
        #expect(html == "<p><a href=\"https://x.y\"><img src=\"i.png\" alt=\"b\" /></a></p>")
    }

    @Test
    func thematicBreak() {
        let html = plainHTML("a\n\n---\n\n***\n\nb")
        #expect(html == "<p>a</p>\n<hr />\n<hr />\n<p>b</p>")
    }

    @Test
    func tableWithAlignment() {
        let markdown = "| Name | Age |\n|:-----|----:|\n| Ann | 30 |"
        let html = plainHTML(markdown)
        #expect(html == """
        <table>
        <thead>
        <tr>
        <th style="text-align: left">Name</th>
        <th style="text-align: right">Age</th>
        </tr>
        </thead>
        <tbody>
        <tr>
        <td style="text-align: left">Ann</td>
        <td style="text-align: right">30</td>
        </tr>
        </tbody>
        </table>
        """)
    }

    @Test
    func tableEscapedPipe() {
        let markdown = "| a \\| b | c |\n|---|---|\n| 1 | 2 |"
        let html = plainHTML(markdown)
        #expect(html.contains("<th>a | b</th>"))
        #expect(html.contains("<td>1</td>"))
    }

    @Test
    func escapesHTML() {
        let html = plainHTML("a < b & c > d")
        #expect(html == "<p>a &lt; b &amp; c &gt; d</p>")
    }

    @Test
    func inlineHTMLPassesThrough() {
        let html = plainHTML("<b>&\"x\"</b>")
        #expect(html == "<p><b>&amp;&quot;x&quot;</b></p>")
    }

    @Test
    func inlineHTMLCommentPassesThrough() {
        let html = plainHTML("a <!-- note --> b")
        #expect(html == "<p>a <!-- note --> b</p>")
    }

    @Test
    func inlineHTMLWithAttributesPassesThrough() {
        let html = plainHTML("text <img src=\"a.png\" alt=\"x\"> end")
        #expect(html == "<p>text <img src=\"a.png\" alt=\"x\"> end</p>")
    }

    @Test
    func inlineHTMLEventHandlerIsStripped() {
        let html = plainHTML("text <img src=\"a.png\" onerror=\"evil()\"> end")
        #expect(html == "<p>text <img src=\"a.png\"> end</p>")
    }

    @Test
    func escapesHTMLInsideCode() {
        let html = plainHTML("```\n<script>alert(1)</script>\n```")
        #expect(html == "<pre><code>&lt;script&gt;alert(1)&lt;/script&gt;\n</code></pre>")
    }

    @Test
    func backslashEscape() {
        let html = plainHTML("a \\*literal\\* star")
        #expect(html == "<p>a *literal* star</p>")
    }

    @Test
    func hardBreak() {
        let html = plainHTML("one  \ntwo")
        #expect(html == "<p>one<br />\ntwo</p>")
    }

    @Test
    func backslashHardBreak() {
        let html = plainHTML("one\\\ntwo")
        #expect(html == "<p>one<br />\ntwo</p>")
    }
}
