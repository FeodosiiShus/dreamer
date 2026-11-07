import Foundation
import Testing
@testable import Dreamder

struct MarkdownBlockLexerTests {
    private func samples(_ text: String) -> [MarkdownTokenSample] {
        MarkdownLexerSupport.samples(text)
    }

    private func texts(_ kind: MarkdownTokenKind, _ text: String) -> [String] {
        MarkdownLexerSupport.texts(of: kind, in: text)
    }

    private func locations(_ kind: MarkdownTokenKind, _ text: String) -> [Int] {
        MarkdownLexerSupport.ranges(of: kind, in: text).map(\.location)
    }

    private func s(_ kind: MarkdownTokenKind, _ text: String) -> MarkdownTokenSample {
        MarkdownTokenSample(kind, text)
    }

    @Test(arguments: 1...6)
    func atxHeaderLevelsSplitMarkerAndContent(level: Int) {
        let marker = String(repeating: "#", count: level)
        let text = "\(marker) Title"
        let actual = samples(text)
        let expected = [s(.headerMarker, marker), s(.headerContent(level: level), "Title")]
        #expect(actual == expected)
        let ranges = MarkdownLexerSupport.tokens(text).map(\.range)
        #expect(ranges == [NSRange(location: 0, length: level), NSRange(location: level + 1, length: 5)])
    }

    @Test(arguments: ["####### seven", "#hashtag", "#!shebang"])
    func nonHeadersProduceNoTokens(text: String) {
        let actual = samples(text)
        #expect(actual.isEmpty)
        let headers = MarkdownBlockLexer.scan(text).headers
        #expect(headers.isEmpty)
    }

    @Test
    func atxContentIsTrimmed() {
        let actual = samples("#   spaced   ")
        #expect(actual == [s(.headerMarker, "#"), s(.headerContent(level: 1), "spaced")])
    }

    @Test
    func closingHashesBecomeSecondMarkerAndLeaveContent() {
        let text = "## Title ##  "
        let actual = samples(text)
        #expect(actual == [s(.headerMarker, "##"), s(.headerContent(level: 2), "Title"), s(.headerMarker, "##")])
        #expect(locations(.headerMarker, text) == [0, 9])
        let headers = MarkdownBlockLexer.scan(text).headers
        let contents = headers.map { (text as NSString).substring(with: $0.contentRange) }
        #expect(contents == ["Title"])
    }

    @Test
    func emptyHeaderHasMarkerOnly() {
        let text = "#"
        let scan = MarkdownBlockLexer.scan(text)
        #expect(samples(text) == [s(.headerMarker, "#")])
        #expect(scan.headers.count == 1)
        #expect(scan.headers.first?.level == 1)
        #expect(scan.headers.first?.contentRange.length == 0)
    }

    @Test(arguments: [1, 2, 3])
    func headerAcceptsUpToThreeLeadingSpaces(spaces: Int) {
        let text = String(repeating: " ", count: spaces) + "## lead"
        let actual = samples(text)
        #expect(actual == [s(.headerMarker, "##"), s(.headerContent(level: 2), "lead")])
        #expect(locations(.headerMarker, text) == [spaces])
    }

    @Test
    func fourLeadingSpacesIsIndentedCodeNotHeader() {
        let actual = samples("    # code")
        #expect(actual == [s(.codeBlock, "# code")])
    }

    @Test
    func setextLevelOneUsesEqualsUnderline() {
        let text = "Para one\nline two\n==="
        let actual = samples(text)
        #expect(actual == [s(.headerContent(level: 1), "Para one\nline two"), s(.headerMarker, "===")])
        let header = MarkdownBlockLexer.scan(text).headers.first
        #expect(header?.isSetext == true)
        #expect(header?.level == 1)
    }

    @Test
    func setextLevelTwoUsesDashUnderline() {
        let text = "Title\n---"
        let actual = samples(text)
        #expect(actual == [s(.headerContent(level: 2), "Title"), s(.headerMarker, "---")])
        #expect(locations(.headerMarker, text) == [6])
    }

    @Test
    func consecutiveSetextHeadersAreIndependent() {
        let text = "x\n---\ny\n---\n# H"
        let actual = samples(text)
        let expected = [
            s(.headerContent(level: 2), "x"), s(.headerMarker, "---"),
            s(.headerContent(level: 2), "y"), s(.headerMarker, "---"),
            s(.headerMarker, "#"), s(.headerContent(level: 1), "H")
        ]
        #expect(actual == expected)
    }

    @Test(arguments: ["***", "---", "___", "* * *", "- - -", "- - - -"])
    func thematicBreakIsHorizontalRule(text: String) {
        let actual = samples(text)
        #expect(actual == [s(.horizontalRule, text)])
    }

    @Test
    func thematicBreakAfterParagraphWithStarsIsRule() {
        let actual = samples("foo\n***")
        #expect(actual == [s(.horizontalRule, "***")])
    }

    @Test
    func dashRuleInsideListIsRuleAndItemIsMarker() {
        let text = "- a\n- - -"
        let actual = samples(text)
        #expect(actual == [s(.listMarker, "-"), s(.horizontalRule, "- - -")])
        #expect(locations(.horizontalRule, text) == [4])
    }

    @Test
    func singleDashItemIsListMarkerNotRule() {
        let actual = samples("- item")
        #expect(actual == [s(.listMarker, "-")])
    }

    @Test
    func backtickFenceSplitsMarkerLanguageAndBodyLines() {
        let text = "```swift title\nlet a\n\nb\n```"
        let actual = samples(text)
        let expected = [
            s(.codeFenceMarker, "```"),
            s(.codeFenceLanguage, "swift"),
            s(.codeFenceContent(hasLanguage: true), "let a"),
            s(.codeFenceContent(hasLanguage: true), "b"),
            s(.codeFenceMarker, "```")
        ]
        #expect(actual == expected)
        #expect(locations(.codeFenceMarker, text) == [0, 24])
    }

    @Test
    func tildeFenceWithoutLanguageMarksContentWithoutLanguage() {
        let actual = samples("~~~\nx\n~~~")
        let expected = [
            s(.codeFenceMarker, "~~~"),
            s(.codeFenceContent(hasLanguage: false), "x"),
            s(.codeFenceMarker, "~~~")
        ]
        #expect(actual == expected)
    }

    @Test
    func emptyFenceHasOnlyMarkers() {
        let actual = samples("```\n```")
        #expect(actual == [s(.codeFenceMarker, "```"), s(.codeFenceMarker, "```")])
    }

    @Test
    func shorterInnerFenceIsContentAndLongerOrEqualCloses() {
        let actual = samples("````\n```\nx\n````")
        let expected = [
            s(.codeFenceMarker, "````"),
            s(.codeFenceContent(hasLanguage: false), "```"),
            s(.codeFenceContent(hasLanguage: false), "x"),
            s(.codeFenceMarker, "````")
        ]
        #expect(actual == expected)
    }

    @Test
    func closingFenceShorterThanOpeningDoesNotClose() {
        let actual = samples("```\nx\n``")
        let expected = [
            s(.codeFenceMarker, "```"),
            s(.codeFenceContent(hasLanguage: false), "x"),
            s(.codeFenceContent(hasLanguage: false), "``")
        ]
        #expect(actual == expected)
    }

    @Test
    func backtickFenceInsideTildeFenceIsContent() {
        let actual = samples("~~~\n```\nx\n```\n~~~")
        let expected = [
            s(.codeFenceMarker, "~~~"),
            s(.codeFenceContent(hasLanguage: false), "```"),
            s(.codeFenceContent(hasLanguage: false), "x"),
            s(.codeFenceContent(hasLanguage: false), "```"),
            s(.codeFenceMarker, "~~~")
        ]
        #expect(actual == expected)
    }

    @Test
    func unterminatedFenceRunsToEndOfDocument() {
        let actual = samples("```\nabc\ndef")
        let expected = [
            s(.codeFenceMarker, "```"),
            s(.codeFenceContent(hasLanguage: false), "abc"),
            s(.codeFenceContent(hasLanguage: false), "def")
        ]
        #expect(actual == expected)
    }

    @Test
    func backtickFenceWithBacktickInInfoStringIsNotAFence() {
        let actual = MarkdownLexerSupport.tokens("``` a`b\nx").map(\.kind)
        #expect(actual.isEmpty)
    }

    @Test
    func tildeFenceMayContainBacktickInInfoString() {
        let text = "~~~ a`b\nx\n~~~"
        #expect(texts(.codeFenceLanguage, text) == ["a`b"])
        #expect(texts(.codeFenceMarker, text) == ["~~~", "~~~"])
    }

    @Test
    func indentedFenceUsesFenceHighlighting() {
        let text = "    ```java\n    code\n    ```"
        #expect(texts(.codeFenceMarker, text) == ["```", "```"])
        #expect(texts(.codeFenceLanguage, text) == ["java"])
        #expect(locations(.codeFenceMarker, text) == [4, 25])
        let blocks = texts(.codeBlock, text)
        #expect(blocks.isEmpty)
    }

    @Test
    func fenceInsideListItemIsRecognized() {
        let actual = samples("- item\n  ```kt\n  x\n  ```")
        let expected = [
            s(.listMarker, "-"),
            s(.codeFenceMarker, "```"),
            s(.codeFenceLanguage, "kt"),
            s(.codeFenceContent(hasLanguage: true), "x"),
            s(.codeFenceMarker, "```")
        ]
        #expect(actual == expected)
    }

    @Test
    func fenceInsideBlockQuoteIsRecognizedPerLine() {
        let text = "> ```sh\n> echo\n> ```"
        let actual = samples(text)
        let expected = [
            s(.blockQuote, "> ```sh\n"),
            s(.blockQuoteMarker, ">"),
            s(.codeFenceMarker, "```"),
            s(.codeFenceLanguage, "sh"),
            s(.blockQuote, "> echo\n"),
            s(.blockQuoteMarker, ">"),
            s(.codeFenceContent(hasLanguage: true), "echo"),
            s(.blockQuote, "> ```"),
            s(.blockQuoteMarker, ">"),
            s(.codeFenceMarker, "```")
        ]
        #expect(actual == expected)
    }

    @Test
    func indentedCodeStartsAfterFourColumns() {
        let text = "    code\n     more"
        let actual = samples(text)
        #expect(actual == [s(.codeBlock, "code"), s(.codeBlock, " more")])
        #expect(locations(.codeBlock, text) == [4, 13])
    }

    @Test
    func indentedCodeAfterBlankLineSkipsBlankLinesBetweenLines() {
        let text = "a\n\n    code\n\n    more\n\nb"
        #expect(texts(.codeBlock, text) == ["code", "more"])
    }

    @Test
    func indentedLineAfterParagraphIsLazyContinuationNotCode() {
        let actual = samples("para\n    lazy")
        #expect(actual.isEmpty)
    }

    @Test
    func blockQuoteMarkersAreEmittedForEveryNestingLevel() {
        let text = "> a\n> > b\n> > > c"
        #expect(locations(.blockQuoteMarker, text) == [0, 4, 6, 10, 12, 14])
        #expect(texts(.blockQuote, text) == ["> a\n", "> > b\n", "> > > c"])
    }

    @Test
    func blockQuoteRangesFollowIntelliJAnnotatorTestWithListAndInline() {
        let text = "- > a [link](x) `code`\n  > > b\n\ntail"
        #expect(texts(.blockQuote, text) == ["> a [link](x) `code`\n", "> > b", "\n"])
        #expect(texts(.listMarker, text) == ["-"])
        #expect(texts(.inlineLink, text) == ["[link](x)"])
        #expect(texts(.codeSpan, text) == ["`code`"])
    }

    @Test
    func blockQuoteCalloutKeepsBlockQuoteRangesAndLabelsMarker() {
        let text = "> [!NOTE]\n> text\n\ntail"
        #expect(texts(.blockQuote, text) == ["> [!NOTE]\n", "> text", "\n"])
        #expect(texts(.linkLabel, text) == ["[!NOTE]"])
    }

    @Test
    func lazyContinuationLineBelongsToBlockQuote() {
        let text = "> a\nlazy\n\nb"
        #expect(texts(.blockQuote, text) == ["> a\n", "lazy", "\n"])
        #expect(texts(.blockQuoteMarker, text) == [">"])
    }

    @Test
    func blankLineEndsBlockQuote() {
        let text = "> a\n\n> b"
        #expect(texts(.blockQuote, text) == ["> a", "\n", "> b"])
        #expect(locations(.blockQuoteMarker, text) == [0, 5])
    }

    @Test(arguments: [
        ("- a\n* b\n+ c", ["-", "*", "+"], [0, 4, 8]),
        ("1. a\n2) b", ["1.", "2)"], [0, 5]),
        ("10. x", ["10."], [0]),
        ("1. a\n2. b", ["1.", "2."], [0, 5]),
        ("-", ["-"], [0])
    ])
    func listMarkerCoversOnlyTheMarker(text: String, markers: [String], starts: [Int]) {
        #expect(texts(.listMarker, text) == markers)
        #expect(locations(.listMarker, text) == starts)
    }

    @Test
    func checkboxRangeCoversBracketsForAllStates() {
        let text = "- [ ] t\n- [x] d\n- [X] e"
        #expect(texts(.checkbox, text) == ["[ ]", "[x]", "[X]"])
        #expect(locations(.checkbox, text) == [2, 10, 18])
        #expect(texts(.listMarker, text) == ["-", "-", "-"])
    }

    @Test
    func nestedListsByIndentationEachGetMarker() {
        let text = "- a\n  - b\n    - c"
        #expect(locations(.listMarker, text) == [0, 6, 14])
    }

    @Test
    func orderedListNotStartingWithOneCannotInterruptParagraph() {
        let actual = samples("para\n2. x")
        #expect(actual.isEmpty)
    }

    @Test
    func orderedListStartingWithOneInterruptsParagraph() {
        let text = "para\n1. x"
        #expect(samples(text) == [s(.listMarker, "1.")])
        #expect(locations(.listMarker, text) == [5])
    }

    @Test
    func siblingOrderedItemAfterFirstIsMarker() {
        let text = "1. a\n2. b\n3. c"
        #expect(texts(.listMarker, text) == ["1.", "2.", "3."])
    }

    @Test
    func listMarkersInsideBlockQuote() {
        let text = "> - a\n> - b"
        let actual = samples(text)
        let expected = [
            s(.blockQuote, "> - a\n"),
            s(.blockQuoteMarker, ">"),
            s(.listMarker, "-"),
            s(.blockQuote, "> - b"),
            s(.blockQuoteMarker, ">"),
            s(.listMarker, "-")
        ]
        #expect(actual == expected)
    }

    @Test
    func headersInListItemsAndQuotesGetDistinctContainerPaths() {
        let text = "- # H\n\n> # Q\n\n# Top\n\n> # Q2"
        let headers = MarkdownBlockLexer.scan(text).headers
        let paths = headers.map(\.containerPath)
        #expect(paths == [[0], [1], [], [2]])
        let titles = headers.map { (text as NSString).substring(with: $0.contentRange) }
        #expect(titles == ["H", "Q", "Top", "Q2"])
    }

    @Test
    func sameContainerHeadersShareContainerPath() {
        let text = "# A\n\n# B"
        let headers = MarkdownBlockLexer.scan(text).headers
        let paths = headers.map(\.containerPath)
        #expect(paths == [[], []])
    }

    @Test
    func sameQuoteHeadersShareContainerPath() {
        let text = "> # A\n>\n> # B"
        let headers = MarkdownBlockLexer.scan(text).headers
        let paths = headers.map(\.containerPath)
        #expect(paths.count == 2)
        #expect(paths.first == paths.last)
        #expect(paths.first?.isEmpty == false)
    }

    @Test
    func headersInSeparateListItemsDifferFromEachOtherAndFromTopLevel() {
        let text = "- # A\n- # B\n\n# C"
        let headers = MarkdownBlockLexer.scan(text).headers
        let paths = headers.map(\.containerPath)
        #expect(paths == [[0], [1], []])
        #expect(paths[0] != paths[1])
    }

    @Test
    func tableHeaderDelimiterAndBodyRows() {
        let text = "| a | b |\n| --- | :-: |\n| 1 | 2 |"
        let actual = samples(text)
        let expected = [
            s(.tableSeparator, "|"), s(.tableSeparator, "|"), s(.tableSeparator, "|"),
            s(.tableSeparator, "| --- | :-: |"),
            s(.tableSeparator, "|"), s(.tableSeparator, "|"), s(.tableSeparator, "|")
        ]
        #expect(actual == expected)
        #expect(locations(.tableSeparator, text) == [0, 4, 8, 10, 24, 28, 32])
    }

    @Test
    func tableDelimiterRowIsSingleTokenSpanningCells() {
        let text = "| a | b |\n| - | - |"
        let ranges = MarkdownLexerSupport.ranges(of: .tableSeparator, in: text)
        #expect(ranges.last == NSRange(location: 10, length: 9))
        #expect(texts(.tableSeparator, text).last == "| - | - |")
    }

    @Test
    func tableWithoutLeadingPipesAndEscapedPipeInHeader() {
        let text = "a \\| b | c\n--- | ---\nx | y"
        let actual = samples(text)
        let expected = [
            s(.escape, "\\|"),
            s(.tableSeparator, "|"),
            s(.tableSeparator, "--- | ---"),
            s(.tableSeparator, "|")
        ]
        #expect(actual == expected)
    }

    @Test
    func escapedPipeInBodyRowIsNotASeparator() {
        let text = "| a | b |\n| - | - |\n| x \\| y | z |"
        let rowStart = (text as NSString).range(of: "| x").location
        let bodySeparators = locations(.tableSeparator, text).filter { $0 >= rowStart }
        #expect(bodySeparators == [rowStart, rowStart + 9, rowStart + 13])
        #expect(texts(.escape, text) == ["\\|"])
    }

    @Test
    func codeSpanInsideTableCellsIsLexedInline() {
        let text = "| a | `b` |\n| - | - |\n| `c` | d |"
        #expect(texts(.codeSpan, text) == ["`b`", "`c`"])
        #expect(texts(.codeSpanMarker, text) == ["`", "`", "`", "`"])
    }

    @Test
    func tableEndsAtBlankLine() {
        let text = "| a | b |\n| - | - |\n| 1 | 2 |\n\ntext"
        let textStart = (text as NSString).range(of: "text").location
        let after = MarkdownLexerSupport.tokens(text).filter { $0.range.location >= textStart }
        #expect(after.isEmpty)
        #expect(locations(.tableSeparator, text) == [0, 4, 8, 10, 20, 24, 28])
    }

    @Test
    func singleColumnTable() {
        let actual = samples("| a |\n| - |")
        let expected = [s(.tableSeparator, "|"), s(.tableSeparator, "|"), s(.tableSeparator, "| - |")]
        #expect(actual == expected)
    }

    @Test
    func headerAndDelimiterCellCountMismatchIsNotATable() {
        let actual = samples("| a | b |\n| - |\n| 1 | 2 |")
        #expect(actual.isEmpty)
    }

    @Test
    func multilineHtmlCommentEmitsTokenPerLineAndEndsAtClose() {
        let text = "<!-- c\nd -->\nafter"
        let actual = samples(text)
        #expect(actual == [s(.htmlComment, "<!-- c"), s(.htmlComment, "d -->")])
        #expect(locations(.htmlComment, text) == [0, 7])
    }

    @Test
    func commentFollowedByTextOnSameLineMarksRestAsHtmlCode() {
        let actual = samples("<!-- a --> tail")
        #expect(actual == [s(.htmlComment, "<!-- a -->"), s(.htmlCode, "tail")])
    }

    @Test
    func divBlockEndsAtBlankLine() {
        let text = "<div>\nx\n\ny"
        let actual = samples(text)
        let expected = [
            s(.htmlTag, "<"), s(.htmlTagName, "div"), s(.htmlTag, ">"),
            s(.htmlCode, "x")
        ]
        #expect(actual == expected)
    }

    @Test
    func preBlockKeepsBlankLinesUntilClosingTag() {
        let text = "<pre>\na\n\nb\n</pre>\n\nz"
        let actual = samples(text)
        let expected = [
            s(.htmlTag, "<"), s(.htmlTagName, "pre"), s(.htmlTag, ">"),
            s(.htmlCode, "a"),
            s(.htmlCode, "b"),
            s(.htmlTag, "</"), s(.htmlTagName, "pre"), s(.htmlTag, ">")
        ]
        #expect(actual == expected)
    }

    @Test
    func processingInstructionBlockEndsAfterClosingLine() {
        let text = "<?php\n echo ?>\n\nz"
        let zStart = (text as NSString).range(of: "z").location
        let after = MarkdownLexerSupport.tokens(text).filter { $0.range.location >= zStart }
        #expect(after.isEmpty)
        let first = MarkdownLexerSupport.tokens(text).first
        #expect(first?.range == NSRange(location: 0, length: 5))
    }

    @Test
    func htmlTagAndAttributeTokens() {
        let text = "<div class=\"a\" id=b hidden>\ntext\n</div>"
        let actual = samples(text)
        let expected = [
            s(.htmlTag, "<"), s(.htmlTagName, "div"),
            s(.htmlAttributeName, "class"), s(.htmlAttributeValue, "="), s(.htmlAttributeValue, "\"a\""),
            s(.htmlAttributeName, "id"), s(.htmlAttributeValue, "="), s(.htmlAttributeValue, "b"),
            s(.htmlAttributeName, "hidden"),
            s(.htmlTag, ">"),
            s(.htmlCode, "text"),
            s(.htmlTag, "</"), s(.htmlTagName, "div"), s(.htmlTag, ">")
        ]
        #expect(actual == expected)
    }

    @Test
    func frontMatterDashesFormDelimiterContentDelimiterThenHeader() {
        let text = "---\ntitle: x\n---\n# H"
        let actual = samples(text)
        let expected = [
            s(.frontMatterDelimiter, "---"),
            s(.frontMatterContent, "title: x"),
            s(.frontMatterDelimiter, "---"),
            s(.headerMarker, "#"),
            s(.headerContent(level: 1), "H")
        ]
        #expect(actual == expected)
        #expect(locations(.frontMatterContent, text) == [4])
    }

    @Test
    func frontMatterTomlUsesPlusDelimiters() {
        let actual = samples("+++\na = 1\n+++\n# H")
        let expected = [
            s(.frontMatterDelimiter, "+++"),
            s(.frontMatterContent, "a = 1"),
            s(.frontMatterDelimiter, "+++"),
            s(.headerMarker, "#"),
            s(.headerContent(level: 1), "H")
        ]
        #expect(actual == expected)
    }

    @Test
    func unterminatedFrontMatterOpenerIsHorizontalRule() {
        let actual = samples("---\ntitle: x")
        #expect(actual == [s(.horizontalRule, "---")])
    }

    @Test
    func frontMatterOnlyAtDocumentStart() {
        let text = "x\n---\ny\n---\n# H"
        #expect(texts(.frontMatterDelimiter, text).isEmpty)
        #expect(texts(.frontMatterContent, text).isEmpty)
        let leading = "\n---\ntitle: x\n---"
        #expect(texts(.frontMatterDelimiter, leading).isEmpty)
    }

    @Test
    func linkReferenceDefinitionWithTitle() {
        let actual = samples("[a]: http://x \"t\"")
        #expect(actual == [s(.linkLabel, "[a]"), s(.linkDestination, "http://x"), s(.linkTitle, "\"t\"")])
    }

    @Test
    func linkReferenceDefinitionWithAngleDestinationAndSingleQuotedTitle() {
        let actual = samples("[a]: <http://x> 't'")
        #expect(actual == [s(.linkLabel, "[a]"), s(.linkDestination, "<http://x>"), s(.linkTitle, "'t'")])
    }

    @Test(arguments: [
        "# a\n\n```x\ny\n```\n- [ ] t",
        "Title\n===",
        "| a | b |\n| - | - |",
        "---\nt: x\n---\n# H",
        "[a]: http://x \"t\"\nnext",
        "<div>\nx\n</div>\n\n- [x] done\n1. one",
        "    code\n\npara *em* `c`"
    ])
    func crlfProducesSameTokensAsLfWithShiftedRanges(lf: String) {
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        let utf16 = Array(lf.utf16)
        func shifted(_ offset: Int) -> Int {
            offset + utf16.prefix(offset).filter { $0 == 10 }.count
        }
        let expected = MarkdownLexerSupport.tokens(lf).map { token in
            MarkdownToken(token.kind, from: shifted(token.range.location), to: shifted(token.range.location + token.range.length))
        }
        let actual = MarkdownLexerSupport.tokens(crlf)
        #expect(actual == expected)
    }

    @Test
    func rangesAreUtf16OffsetsAfterMultibyteCharacters() {
        let text = "é😀\n# H"
        let tokens = MarkdownLexerSupport.tokens(text)
        #expect(tokens.map(\.kind) == [.headerMarker, .headerContent(level: 1)])
        #expect(tokens.map(\.range) == [NSRange(location: 4, length: 1), NSRange(location: 6, length: 1)])
        let headers = MarkdownBlockLexer.scan(text).headers
        #expect(headers.first?.contentRange == NSRange(location: 6, length: 1))
    }

    @Test
    func tokensInsideEmojiLineUseUtf16Length() {
        let text = "😀 *a* é"
        let tokens = MarkdownLexerSupport.tokens(text)
        let italic = tokens.first { $0.kind == .italic }
        #expect(italic?.range == NSRange(location: 3, length: 3))
    }

    @Test(arguments: ["", " ", "   \n  ", "\n\n", "\t\n"])
    func emptyAndWhitespaceOnlyTextProducesNoTokens(text: String) {
        let scan = MarkdownBlockLexer.scan(text)
        #expect(scan.tokens.isEmpty)
        #expect(scan.headers.isEmpty)
    }
}
