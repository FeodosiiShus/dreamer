import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownHTMLRendererTests {
    @Test
    func atxHeadings() {
        let markdown = "## Sub ##\n####### not heading"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<h2>Sub</h2>\n<p>####### not heading</p>")
    }

    @Test
    func atxHeadingLevels() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "# One\n### Three\n###### Six")
        #expect(html == "<h1>One</h1>\n<h3>Three</h3>\n<h6>Six</h6>")
    }

    @Test
    func setextHeadings() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "Title\n=====\n\nSub\n---")
        #expect(html == "<h1>Title</h1>\n<h2>Sub</h2>")
    }

    @Test
    func paragraphsJoinLines() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "first line\nsecond line\n\nnext paragraph")
        #expect(html == "<p>first line\nsecond line</p>\n<p>next paragraph</p>")
    }

    @Test
    func emphasisAndStrong() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "*em* **strong** ***both***")
        #expect(html == "<p><em>em</em> <strong>strong</strong> <em><strong>both</strong></em></p>")
    }

    @Test
    func nestedEmphasis() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "**bold *italic***")
        #expect(html == "<p><strong>bold <em>italic</em></strong></p>")
    }

    @Test
    func intrawordUnderscoresStayLiteral() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "a_b_c and _em_")
        #expect(html == "<p>a_b_c and <em>em</em></p>")
    }

    @Test
    func unmatchedDelimiterStaysLiteral() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "a * b")
        #expect(html == "<p>a * b</p>")
    }

    @Test
    func codeSpans() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "call `print(\"hi\")` now")
        #expect(html == "<p>call <code>print(&quot;hi&quot;)</code> now</p>")
    }

    @Test
    func codeSpanKeepsMarkdownLiteral() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "`a *b* [c](d)`")
        #expect(html == "<p><code>a *b* [c](d)</code></p>")
    }

    @Test
    func fencedCodeBlock() {
        let markdown = "```swift\nlet a = 1 < 2\n```"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<pre><code class=\"language-swift\">let a = 1 &lt; 2\n</code></pre>")
    }

    @Test
    func fencedCodeBlockWithoutInfo() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "```\nplain `code`\n```")
        #expect(html == "<pre><code>plain `code`\n</code></pre>")
    }

    @Test
    func indentedCodeBlock() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "    let a = 1\n    let b = 2")
        #expect(html == "<pre><code>let a = 1\nlet b = 2\n</code></pre>")
    }

    @Test
    func blockQuote() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "> quoted")
        #expect(html == "<blockquote>\n<p>quoted</p>\n</blockquote>")
    }

    @Test
    func nestedBlockQuote() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "> quoted\n> > nested")
        #expect(html == "<blockquote>\n<p>quoted</p>\n<blockquote>\n<p>nested</p>\n</blockquote>\n</blockquote>")
    }

    @Test
    func unorderedList() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "- one\n- two\n- three")
        #expect(html == "<ul>\n<li>one</li>\n<li>two</li>\n<li>three</li>\n</ul>")
    }

    @Test
    func orderedList() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "1. one\n2. two")
        #expect(html == "<ol>\n<li>one</li>\n<li>two</li>\n</ol>")
    }

    @Test
    func orderedListKeepsStartNumber() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "3. three\n4. four")
        #expect(html == "<ol start=\"3\">\n<li>three</li>\n<li>four</li>\n</ol>")
    }

    @Test
    func nestedList() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "- a\n  - b\n  - c\n- d")
        #expect(html == "<ul>\n<li>a<ul>\n<li>b</li>\n<li>c</li>\n</ul></li>\n<li>d</li>\n</ul>")
    }

    @Test
    func looseListKeepsParagraphs() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "- a\n\n- b")
        #expect(html == "<ul>\n<li><p>a</p></li>\n<li><p>b</p></li>\n</ul>")
    }

    @Test
    func taskList() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "- [ ] open\n- [x] done")
        #expect(html == """
        <ul>
        <li><input type="checkbox" disabled> open</li>
        <li><input type="checkbox" disabled checked> done</li>
        </ul>
        """)
    }

    @Test
    func links() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "[site](https://example.com \"Title\")")
        #expect(html == "<p><a href=\"https://example.com\" title=\"Title\">site</a></p>")
    }

    @Test
    func linkWithBoldLabel() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "[**bold**](a.md)")
        #expect(html == "<p><a href=\"a.md\"><strong>bold</strong></a></p>")
    }

    @Test
    func relativeImage() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "![logo](images/logo.png)")
        #expect(html == "<p><img src=\"images/logo.png\" alt=\"logo\" /></p>")
    }

    @Test
    func imageInsideLink() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "[![b](i.png)](https://x.y)")
        #expect(html == "<p><a href=\"https://x.y\"><img src=\"i.png\" alt=\"b\" /></a></p>")
    }

    @Test
    func thematicBreak() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "a\n\n---\n\n***\n\nb")
        #expect(html == "<p>a</p>\n<hr />\n<hr />\n<p>b</p>")
    }

    @Test
    func tableWithAlignment() {
        let markdown = "| Name | Age |\n|:-----|----:|\n| Ann | 30 |"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
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
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html.contains("<th>a | b</th>"))
        #expect(html.contains("<td>1</td>"))
    }

    @Test
    func escapesHTML() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "a < b & c > d")
        #expect(html == "<p>a &lt; b &amp; c &gt; d</p>")
    }

    @Test
    func inlineHTMLPassesThrough() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "<b>&\"x\"</b>")
        #expect(html == "<p><b>&amp;&quot;x&quot;</b></p>")
    }

    @Test
    func inlineHTMLCommentPassesThrough() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "a <!-- note --> b")
        #expect(html == "<p>a <!-- note --> b</p>")
    }

    @Test
    func inlineHTMLWithAttributesPassesThrough() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "text <img src=\"a.png\" alt=\"x\"> end")
        #expect(html == "<p>text <img src=\"a.png\" alt=\"x\"> end</p>")
    }

    @Test
    func inlineHTMLEventHandlerIsStripped() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "text <img src=\"a.png\" onerror=\"evil()\"> end")
        #expect(html == "<p>text <img src=\"a.png\"> end</p>")
    }

    @Test
    func escapesHTMLInsideCode() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "```\n<script>alert(1)</script>\n```")
        #expect(html == "<pre><code>&lt;script&gt;alert(1)&lt;/script&gt;\n</code></pre>")
    }

    @Test
    func backslashEscape() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "a \\*literal\\* star")
        #expect(html == "<p>a *literal* star</p>")
    }

    @Test
    func hardBreak() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "one  \ntwo")
        #expect(html == "<p>one<br />\ntwo</p>")
    }

    @Test
    func backslashHardBreak() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "one\\\ntwo")
        #expect(html == "<p>one<br />\ntwo</p>")
    }

    @Test
    func documentEmbedsBaseURL() {
        let baseURL = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let document = MarkdownHTMLRenderer.documentHTML(body: "<p>hi</p>", baseURL: baseURL)
        #expect(document.contains("<base href=\"file:///tmp/project/\">"))
        #expect(document.contains("<p>hi</p>"))
        #expect(document.contains("font-family: \"JetBrains Mono\", monospace;"))
        #expect(document.contains("color: #71A1FE;"))
    }

    @Test
    func documentWithoutBaseURL() {
        let document = MarkdownHTMLRenderer.documentHTML(body: "<p>hi</p>", baseURL: nil)
        #expect(!document.contains("<base"))
        #expect(document.contains("<p>hi</p>"))
    }

    @Test
    func emptyDocument() {
        #expect(MarkdownHTMLRenderer.bodyHTML(from: "") == "")
    }

    @Test
    func exclamationMarkOutsideImageTerminates() {
        let markdown = "Don't be shy, jump right in and be part of the discussion!"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<p>Don't be shy, jump right in and be part of the discussion!</p>")
    }

    @Test
    func exclamationMarkBeforeLinkTerminates() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "Hello! [link](a.md) and ![img](i.png) and !")
        #expect(html == "<p>Hello! <a href=\"a.md\">link</a> and <img src=\"i.png\" alt=\"img\" /> and !</p>")
    }

    @Test
    func admonitionMarkerTerminates() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "> [!IMPORTANT]\n> Not for production.")
        #expect(html == "<blockquote>\n<p>[!IMPORTANT]\nNot for production.</p>\n</blockquote>")
    }

    @Test
    func readmeHeaderRenders() {
        let markdown = """
        <p align="center">
          <img src="https://github.com/FeodosiiShus/dreamer/blob/main/.github/Dreamder-Icon-128@2x.png?raw=true" height="128">
          <h1 align="center">Dreamder for macOS</h1>
        </p>

        <p align="center">
          <a aria-label="Follow Dreamder on X" href="https://x.com/DreamderApp" target="_blank">
            <img alt="" src="https://img.shields.io/badge/Follow%20@DreamderApp-black.svg?style=for-the-badge&logo=X">
          </a>
        </p>

        [![GitHub release](https://img.shields.io/github/v/release/FeodosiiShus/dreamer?color=orange&label=latest%20release&sort=semver&style=flat-square)](https://github.com/FeodosiiShus/dreamer/releases/latest)

        > [!IMPORTANT]
        > Dreamder is currently in development and not yet recommended for production use, however you can take part in shaping it's future by test-driving [pre-release versions](https://github.com/FeodosiiShus/dreamer/releases) and [submitting an issue](https://github.com/FeodosiiShus/dreamer/issues) to let us know what you think.

        ## Table of Contents

        - [Motivation](#motivation)
        - [Mission](#mission)
        """
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)

        #expect(!html.isEmpty)
        #expect(html.contains("<p align=\"center\">"))
        #expect(html.contains("<img src=\"https://github.com/FeodosiiShus/dreamer/blob/main/.github/Dreamder-Icon-128@2x.png?raw=true\" height=\"128\">"))
        #expect(html.contains("<h1 align=\"center\">Dreamder for macOS</h1>"))
        #expect(html.contains("<a aria-label=\"Follow Dreamder on X\" href=\"https://x.com/DreamderApp\" target=\"_blank\">"))
        #expect(!html.contains("&lt;p align="))
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("<h2>Table of Contents</h2>"))
        #expect(html.contains("<li><a href=\"#motivation\">Motivation</a></li>"))
    }

    @Test
    func readmeCommunityParagraphRenders() {
        let markdown = """
        Join our growing community on [Discord](https://discord.gg/vChUXVf9Em) and [GitHub Discussions](https://github.com/orgs/DreamderApp/discussions) where we discuss and collaborate on all things Dreamder. Don't be shy, jump right in and be part of the discussion!

        > [!NOTE]
        > We hold a weekly meetup on Discord **every Saturday at 3pm UTC** where we discuss latests development, feature requests, goals, and priorities.
        > 
        > [**Join us**](https://discord.gg/KvdE3wYKNR?event=1189275961456336937)
        """
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)

        #expect(html.contains("<a href=\"https://discord.gg/vChUXVf9Em\">Discord</a>"))
        #expect(html.contains("be part of the discussion!</p>"))
        #expect(html.contains("<strong>every Saturday at 3pm UTC</strong>"))
        #expect(html.contains("<a href=\"https://discord.gg/KvdE3wYKNR?event=1189275961456336937\"><strong>Join us</strong></a>"))
    }

    @Test
    func readmeContributorTableRenders() {
        let markdown = """
        <!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
        <table>
          <tbody>
            <tr>
              <td align="center" valign="top" width="14.28%"><a href="http://www.austincondiff.com"><img src="https://avatars.githubusercontent.com/u/806104?v=4?s=100" width="100px;" alt="Austin Condiff"/><br /><sub><b>Austin Condiff</b></sub></a><br /><a href="#design-austincondiff" title="Design">🎨</a> <a href="https://github.com/FeodosiiShus/dreamer/commits?author=austincondiff" title="Code">💻</a></td>
            </tr>
          </tbody>
        </table>

        | Name | Role |
        |---|---|
        | Austin Condiff | Design |
        """
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)

        #expect(html.contains("<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->"))
        #expect(html.contains("<table>"))
        #expect(html.contains("<td align=\"center\" valign=\"top\" width=\"14.28%\">"))
        #expect(html.contains("<td>Austin Condiff</td>"))
    }

    @Test
    func fullReadmeTerminates() {
        let paragraph = """
        <p align="center">
          <a aria-label="Join the community on Discord" href="https://discord.gg/vChUXVf9Em" target="_blank">
            <img alt="" src="https://img.shields.io/badge/Join%20the%20community-black.svg?style=for-the-badge&logo=Discord">
          </a>
        </p>

        > [!IMPORTANT]
        > Not for production use! Read [the docs](https://example.com) and [![badge](i.png)](u) first!

        - [Anchor](#anchor) and **bold** and *em* and `code` and <not-a-tag>
        """
        let markdown = Array(repeating: paragraph, count: 200).joined(separator: "\n\n")
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)

        #expect(html.contains("<blockquote>"))
        #expect(html.contains("Not for production use! Read <a href=\"https://example.com\">the docs</a>"))
        #expect(html.contains("<not-a-tag>"))
        #expect(html.count > markdown.count)
    }

    @Test
    func htmlBlockKind1ScriptIsRemoved() {
        let markdown = "<script>\nvar a = 1;\n</script>\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<p>text</p>")
    }

    @Test
    func htmlBlockKind1PreIsVerbatim() {
        let markdown = "<pre>\nkeep *raw*\n</pre>\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<pre>\nkeep *raw*\n</pre>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind1TextareaAndStyleAreVerbatim() {
        let markdown = "<textarea>\n*raw*\n</textarea>\n\n<style>\nbody { color: red }\n</style>"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<textarea>\n*raw*\n</textarea>\n<style>\nbody { color: red }\n</style>")
    }

    @Test
    func htmlBlockKind2CommentIsVerbatim() {
        let markdown = "<!-- hidden -->\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<!-- hidden -->\n<p>text</p>")
    }

    @Test
    func htmlBlockKind3InstructionIsVerbatim() {
        let markdown = "<?php echo 1; ?>\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<?php echo 1; ?>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind4DeclarationIsVerbatim() {
        let markdown = "<!DOCTYPE html>\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<!DOCTYPE html>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind5CDataIsVerbatim() {
        let markdown = "<![CDATA[raw <tag>]]>\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<![CDATA[raw <tag>]]>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind6BlockTagIsVerbatim() {
        let markdown = "<div class=\"x\">\ncontent *not em*\n</div>\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<div class=\"x\">\ncontent *not em*\n</div>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind7CompleteTagAloneOnLineIsVerbatim() {
        let markdown = "<custom-tag>\n\ntext"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<custom-tag>\n<p>text</p>")
    }

    @Test
    func htmlBlockKind6InterruptsParagraph() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "text\n<div>block</div>")
        #expect(html == "<p>text</p>\n<div>block</div>")
    }

    @Test
    func htmlBlockKind7DoesNotInterruptParagraph() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: "text\n<custom-tag>")
        #expect(html == "<p>text\n<custom-tag></p>")
    }

    @Test
    func htmlBlockEventHandlerAttributeIsStripped() {
        let markdown = "<div onclick=\"evil()\" data-x=\"1\">\nhi\n</div>"
        let html = MarkdownHTMLRenderer.bodyHTML(from: markdown)
        #expect(html == "<div data-x=\"1\">\nhi\n</div>")
    }

    @Test
    func sanitizerRemovesScriptElementsAndEventHandlers() {
        let html = MarkdownHTMLSanitizer.sanitize(
            "<div onClick=\"a()\">hi</div><script type=\"text/javascript\">bad()</script><img src=\"x\" onload='b()'>"
        )
        #expect(html == "<div>hi</div><img src=\"x\">")
    }

    @Test
    func sanitizerKeepsPlainTextUnchanged() {
        let text = "a < b and a & b"
        #expect(MarkdownHTMLSanitizer.sanitize(text) == text)
    }
}
