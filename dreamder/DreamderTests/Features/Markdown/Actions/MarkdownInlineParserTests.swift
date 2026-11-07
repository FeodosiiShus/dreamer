import Foundation
import Testing
@testable import Dreamder

struct MarkdownInlineParserTests {
    private func described(_ markdown: String) -> [String] {
        let nodes = MarkdownInlineParser.parse(Array(markdown.utf16), base: 0)
        let ns = markdown as NSString
        return nodes.map { "\($0.kind):\(ns.substring(with: $0.range))" }
    }

    @Test(arguments: [
        ("**foo**", ["strong:**foo**"]),
        ("__foo__", ["strong:__foo__"]),
        ("*foo*", ["emphasis:*foo*"]),
        ("_foo_", ["emphasis:_foo_"]),
        ("~~gone~~", ["strikethrough:~~gone~~"]),
        ("==mark==", ["highlight:==mark=="]),
        ("***both***", ["emphasis:***both***", "strong:**both**"]),
        ("*a **b** c*", ["emphasis:*a **b** c*", "strong:**b**"]),
        ("`code`", ["codeSpan:`code`"]),
        ("``a`b``", ["codeSpan:``a`b``"])
    ])
    func emphasisAndCodeNodes(markdown: String, expected: [String]) {
        #expect(described(markdown) == expected)
    }

    @Test(arguments: ["snake_case_name", "2 * 3 * 4", "a * b", "=x=", "===x===", "~one~", "`unclosed", "**unclosed"])
    func nonEmphasisInputsProduceNoEmphasisNodes(markdown: String) {
        #expect(described(markdown).isEmpty)
    }

    @Test
    func codeSpanShieldsEmphasisMarkers() {
        #expect(described("`*a*` *b*") == ["codeSpan:`*a*`", "emphasis:*b*"])
    }

    @Test
    func backslashEscapesDelimiters() {
        #expect(described("\\*a\\*") == [])
    }

    @Test
    func inlineLinkProducesTextDestinationAndWholeLink() {
        #expect(described("[text](http://a.b/c)") == [
            "inlineLink:[text](http://a.b/c)",
            "linkText:[text]",
            "linkDestination:http://a.b/c"
        ])
    }

    @Test
    func linkTitleIsNotPartOfTheDestination() {
        #expect(described("[t](u \"title\")") == ["inlineLink:[t](u \"title\")", "linkText:[t]", "linkDestination:u"])
    }

    @Test
    func emphasisInsideLinkTextIsRecognized() {
        #expect(described("[*x*](u)") == ["inlineLink:[*x*](u)", "linkText:[*x*]", "emphasis:*x*", "linkDestination:u"])
    }

    @Test
    func imageProducesImageNode() {
        #expect(described("![alt](src)") == ["image:![alt](src)", "linkText:[alt]", "linkDestination:src"])
    }

    @Test
    func emptyDestinationLinkHasNoDestinationNode() {
        #expect(described("[text]()") == ["inlineLink:[text]()", "linkText:[text]"])
    }

    @Test
    func linksCannotBeNested() {
        let nodes = described("[a [b](c) d](e)")

        #expect(nodes.contains("inlineLink:[b](c)"))
        #expect(nodes.contains("inlineLink:[a [b](c) d](e)") == false)
    }

    @Test
    func fullReferenceLinkTextIsALinkText() {
        #expect(described("[text][label]") == ["linkText:[text]"])
    }

    @Test
    func shortcutReferenceWithoutDefinitionIsPlainText() {
        #expect(described("[text]").isEmpty)
    }

    @Test(arguments: [
        ("<https://a.b/c>", ["autolink:<https://a.b/c>"]),
        ("<me@example.com>", ["autolink:<me@example.com>"]),
        ("see https://foo.bar/baz). end", ["autolink:https://foo.bar/baz"]),
        ("www.example.com/x", ["autolink:www.example.com/x"]),
        ("<span>", ["htmlTag:<span>"]),
        ("<!-- note -->", ["htmlTag:<!-- note -->"])
    ])
    func autolinksAndHtmlTags(markdown: String, expected: [String]) {
        #expect(described(markdown) == expected)
    }

    @Test
    func bareUrlRequiresBoundaryBefore() {
        #expect(described("xhttps://a.b").isEmpty)
    }

    @Test
    func nodesAreSortedByStartThenOuterFirst() {
        let nodes = MarkdownInlineParser.parse(Array("**a *b* c**".utf16), base: 0)

        let starts = nodes.map(\.range.location)

        #expect(starts == [0, 4])
        #expect(nodes[0].kind == .strong)
        #expect(nodes[1].kind == .emphasis)
    }

    @Test
    func baseOffsetShiftsAllRanges() {
        let nodes = MarkdownInlineParser.parse(Array("*a*".utf16), base: 10)

        #expect(nodes.first?.range == NSRange(location: 10, length: 3))
    }

    @Test
    func contentRangeExcludesDelimiters() {
        let nodes = MarkdownInlineParser.parse(Array("**foo**".utf16), base: 0)

        #expect(nodes.first?.contentRange == NSRange(location: 2, length: 3))
        #expect(nodes.first?.containsChar(at: 6) == true)
        #expect(nodes.first?.containsChar(at: 7) == false)
    }

    @Test
    func unicodePunctuationFlankingAllowsEmphasisNextToQuotes() {
        #expect(described("“*quoted*”") == ["emphasis:*quoted*"])
    }
}
