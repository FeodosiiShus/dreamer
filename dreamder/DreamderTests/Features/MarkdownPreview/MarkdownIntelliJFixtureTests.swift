import Foundation
import Testing
@testable import Dreamder

@Suite
struct MarkdownIntelliJFixtureTests {
    struct Fixture: Sendable, CustomTestStringConvertible {
        let name: String
        let markdown: String
        let html: String

        var testDescription: String { name }
    }

    private static func normalized(_ markdown: String) -> String {
        MarkdownPreviewTestSupport.normalized(MarkdownHTMLRenderer.bodyHTML(from: markdown))
    }

    static let parserFixtures: [Fixture] = [
        Fixture(
            name: "parser/codeSpan",
            markdown: "An example of `CodeSpan`",
            html: "<p>An example of <code>CodeSpan</code></p>"
        ),
        Fixture(
            name: "parser/highlight",
            markdown: "Some ==marked== text",
            html: "<p>Some <mark>marked</mark> text</p>"
        ),
        Fixture(
            name: "parser/linkDestinationWithUnderscore",
            markdown: "[link](underscore_/file.md)",
            html: "<p><a href=\"underscore_/file.md\">link</a></p>"
        ),
        Fixture(
            name: "parser/comment",
            markdown: "[//]: #a (comment)\n[//]: # (comment)",
            html: ""
        ),
        Fixture(
            name: "parser/complex",
            markdown: "# 123\n\nHello how are you\n\n    blockquote\n\n# Other header\n  # And other",
            html: "<h1>123</h1><p>Hello how are you</p><pre><code>blockquote\n</code></pre>"
                + "<h1>Other header</h1><h1>And other</h1>"
        ),
        Fixture(
            name: "parser/referenceLinkLabelSeparatedFromLinkText",
            markdown: "T030 [P] [US3] Implement the thing\n\n[foo] [bar]\n\n[foo]\n[bar]\n\n[foo][bar]\n\n![foo] [bar]\n\n"
                + "![foo][bar]\n\n[bar]: /url \"title\"",
            html: "<p>T030 [P] [US3] Implement the thing</p>"
                + "<p>[foo] <a href=\"/url\" title=\"title\">bar</a></p>"
                + "<p>[foo]\n<a href=\"/url\" title=\"title\">bar</a></p>"
                + "<p><a href=\"/url\" title=\"title\">foo</a></p>"
                + "<p>![foo] <a href=\"/url\" title=\"title\">bar</a></p>"
                + "<p><img src=\"/url\" alt=\"foo\" title=\"title\" /></p>"
        ),
        Fixture(
            name: "parser/tableWithEmptyCells",
            markdown: "|||\n|-|-|\n|||",
            html: "<table><thead><tr><th></th><th></th></tr></thead>"
                + "<tbody><tr><td></td><td></td></tr></tbody></table>"
        ),
        Fixture(
            name: "parser/tableWithEmptyCellsAndTrailingWhitespace",
            markdown: "||| \n|-|-|\n|||",
            html: "<table><thead><tr><th></th><th></th></tr></thead>"
                + "<tbody><tr><td></td><td></td></tr></tbody></table>"
        ),
        Fixture(
            name: "parser/tableWithEscapedPipe",
            markdown: "| A | B |\n| --- | --- |\n| a \\| a | b |",
            html: "<table><thead><tr><th>A</th><th>B</th></tr></thead>"
                + "<tbody><tr><td>a | a</td><td>b</td></tr></tbody></table>"
        ),
        Fixture(
            name: "parser/tableWithEscapedPipeInsideCodeSpan",
            markdown: "|  some  |\n|--------|\n| A`\\|`B |",
            html: "<table><thead><tr><th>some</th></tr></thead>"
                + "<tbody><tr><td>A<code>|</code>B</td></tr></tbody></table>"
        ),
        Fixture(
            name: "parser/tableWithSmallCells",
            markdown: "| |  |    |   |    |   |    |  |  |\n|-|--|----|---|:---|:-:|---:|:-|-:|\n"
                + "| |  |    |   |    |   |    |  |  |",
            html: "<table><thead><tr><th></th><th></th><th></th><th></th>"
                + "<th style=\"text-align: left\"></th><th style=\"text-align: center\"></th>"
                + "<th style=\"text-align: right\"></th><th style=\"text-align: left\"></th>"
                + "<th style=\"text-align: right\"></th></tr></thead>"
                + "<tbody><tr><td></td><td></td><td></td><td></td>"
                + "<td style=\"text-align: left\"></td><td style=\"text-align: center\"></td>"
                + "<td style=\"text-align: right\"></td><td style=\"text-align: left\"></td>"
                + "<td style=\"text-align: right\"></td></tr></tbody></table>"
        )
    ]

    static let htmlFixtures: [Fixture] = [
        Fixture(
            name: "html/codeFenceWithLang",
            markdown: "```ruby\ndef foo(x)\n  return 3\nend\n```",
            html: "<pre><code class=\"language-ruby\">def foo(x)\n  return 3\nend\n</code></pre>"
        ),
        Fixture(
            name: "html/codeFenceWithoutLang",
            markdown: "```\naaa\n~~~\n```",
            html: "<pre><code>aaa\n~~~\n</code></pre>"
        ),
        Fixture(
            name: "html/emphasisAroundCodeSpan",
            markdown: "***Some `code`***",
            html: "<p><em><strong>Some <code>code</code></strong></em></p>"
        ),
        Fixture(
            name: "html/imageDestinationInAngleBrackets",
            markdown: "![alt](<a b.png>)",
            html: "<p><img src=\"a b.png\" alt=\"alt\" /></p>"
        ),
        Fixture(
            name: "html/htmlTags",
            markdown: "```html\n<dependency>\n  <groupId>com.intellij</groupId>\n</dependency>\n```",
            html: "<pre><code class=\"language-html\">&lt;dependency&gt;\n  &lt;groupId&gt;com.intellij&lt;/groupId&gt;\n"
                + "&lt;/dependency&gt;\n</code></pre>"
        ),
        Fixture(
            name: "html/xmlTags",
            markdown: "```xml\n<dependency>\n  <groupId>com.intellij</groupId>\n</dependency>\n```",
            html: "<pre><code class=\"language-xml\">&lt;dependency&gt;\n  &lt;groupId&gt;com.intellij&lt;/groupId&gt;\n"
                + "&lt;/dependency&gt;\n</code></pre>"
        ),
        Fixture(
            name: "html/backslashesInText",
            markdown: "* One \\\n* Two \\\\\n* Three \\\\\\\n* Four \\\\\\\\\n* Five \\\\\\\\\\\n* Six \\\\\\\\\\\\\n* Seven \\\\\\\\\\\\\\",
            html: "<ul><li>One \\</li><li>Two \\</li><li>Three \\\\</li><li>Four \\\\</li>"
                + "<li>Five \\\\\\</li><li>Six \\\\\\</li><li>Seven \\\\\\\\</li></ul>"
        )
    ]

    @Test(arguments: parserFixtures)
    func parserFixtureInputRendersExpectedHTML(_ fixture: Fixture) {
        #expect(Self.normalized(fixture.markdown) == fixture.html)
    }

    @Test(arguments: htmlFixtures)
    func htmlGenerationFixtureRendersExpectedHTML(_ fixture: Fixture) {
        #expect(Self.normalized(fixture.markdown) == fixture.html)
    }

    @Test
    func codeBlockFixtureKeepsIndentationAndEscapesMarkup() {
        let markdown = """
        A code block:

            /**
             * Load a {@link String} from the {@link #BUNDLE} {@link ResourceBundle}.
             *
             * @param key    the key of the resource.
             */
            public static String message(@PropertyKey(resourceBundle = BUNDLE_NAME) String key) {
                return CommonBundle.message(BUNDLE, key);
            }
        """
        let expected = """
        <p>A code block:</p>
        <pre><code>/**
         * Load a {@link String} from the {@link #BUNDLE} {@link ResourceBundle}.
         *
         * @param key    the key of the resource.
         */
        public static String message(@PropertyKey(resourceBundle = BUNDLE_NAME) String key) {
            return CommonBundle.message(BUNDLE, key);
        }
        </code></pre>
        """
        #expect(MarkdownPreviewTestSupport.plainHTML(markdown) == expected)
    }

    private static let colorsAndFontsSample = """
    Test Markdown document
    ======================

    Text
    ----

    Here is a paragraph with bold text. **This is some bold text.** Here is a
    paragraph with bold text. __This is also some bold text.__

    Here is another one with italic text. *This is some italic text.* Here is
    another one with italic text. _This is some italic text._

    Here is another one with struckout text. ~~This is some struckout text.~~

    Here is another one with highlighted text. ==This is some highlighted text.==


    Links
    -----

    Autolink: <http://example.com>

    Link: [Example](http://example.com)

    Reference style [link][1].

    [1]: http://example.com  "Example"


    Images
    ------

    Image: ![My image](http://www.foo.bar/image.png)

    Headers
    -------

    # First level title
    ## Second level title
    ### Third level title
    #### Fourth level title
    ##### Fifth level title
    ###### Sixth level title

    ### Title with [link](http://localhost)
    ### Title with ![image](http://localhost)

    Code
    ----

    ```
    This
      is
        code
          fence
    ```

    Inline `code span in a` paragraph.

    Horizontal rules
    ----------------

    ---

    ___


    ***


    Lists
    -----

    Unordered list:

    *\tasterisk 1
    *\tasterisk 2
    *\tasterisk 3


    Ordered list:

    1.\tFirst
    2.\tSecond
    3.\tThird


    Mixed:

    1. First
    2. Second:
    \t* Fee
    \t* Fie
    \t* Foe
    3. Third
    """

    @Test
    func colorsAndFontsSampleRendersEveryConstruct() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: Self.colorsAndFontsSample)
        let plain = MarkdownPreviewTestSupport.stripped(html)
        let expectedFragments = [
            "<h1>Test Markdown document</h1>",
            "<h2>Text</h2>",
            "<strong>This is some bold text.</strong>",
            "<strong>This is also some bold text.</strong>",
            "<em>This is some italic text.</em>",
            "<del>This is some struckout text.</del>",
            "<mark>This is some highlighted text.</mark>",
            "<p>Autolink: <a href=\"http://example.com\">http://example.com</a></p>",
            "<p>Link: <a href=\"http://example.com\">Example</a></p>",
            "<p>Reference style <a href=\"http://example.com\" title=\"Example\">link</a>.</p>",
            "<p>Image: <img src=\"http://www.foo.bar/image.png\" alt=\"My image\" /></p>",
            "<h6>Sixth level title</h6>",
            "<h3>Title with <a href=\"http://localhost\">link</a></h3>",
            "<h3>Title with <img src=\"http://localhost\" alt=\"image\" /></h3>",
            "<pre><code>This\n  is\n    code\n      fence\n</code></pre>",
            "<p>Inline <code>code span in a</code> paragraph.</p>",
            "<hr />\n<hr />\n<hr />",
            "<ul>\n<li>asterisk 1</li>\n<li>asterisk 2</li>\n<li>asterisk 3</li>\n</ul>",
            "<ol>\n<li>First</li>\n<li>Second</li>\n<li>Third</li>\n</ol>",
            "<li>Second:<ul>\n<li>Fee</li>\n<li>Fie</li>\n<li>Foe</li>\n</ul></li>"
        ]
        for fragment in expectedFragments {
            #expect(plain.contains(fragment), "missing \(fragment)")
        }
        #expect(!html.contains("[1]:"))
    }

    @Test
    func colorsAndFontsSampleHeadingIdentifiers() {
        let html = MarkdownHTMLRenderer.bodyHTML(from: Self.colorsAndFontsSample)
        let expectedIDs = [
            "test-markdown-document", "text", "links", "images", "headers", "first-level-title",
            "second-level-title", "third-level-title", "fourth-level-title", "fifth-level-title",
            "sixth-level-title", "title-with-link", "title-with-", "code", "horizontal-rules", "lists"
        ]
        for identifier in expectedIDs {
            #expect(html.contains("id=\"\(identifier)\""), "missing id \(identifier)")
        }
    }
}
