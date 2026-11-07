import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

struct MarkdownHighlightProviderTests {
    struct MappingCase: Sendable {
        let kind: MarkdownTokenKind
        let capture: CaptureName?
    }

    static let mappingCases: [MappingCase] = [
        MappingCase(kind: .headerMarker, capture: .keyword),
        MappingCase(kind: .headerContent(level: 1), capture: .variable),
        MappingCase(kind: .headerContent(level: 2), capture: .variable),
        MappingCase(kind: .headerContent(level: 3), capture: .variable),
        MappingCase(kind: .headerContent(level: 4), capture: .variable),
        MappingCase(kind: .headerContent(level: 5), capture: .variable),
        MappingCase(kind: .headerContent(level: 6), capture: .variable),
        MappingCase(kind: .blockQuoteMarker, capture: .comment),
        MappingCase(kind: .blockQuote, capture: nil),
        MappingCase(kind: .listMarker, capture: .keyword),
        MappingCase(kind: .checkbox, capture: nil),
        MappingCase(kind: .horizontalRule, capture: .keyword),
        MappingCase(kind: .codeFenceMarker, capture: .keyword),
        MappingCase(kind: .codeFenceLanguage, capture: .variable),
        MappingCase(kind: .codeFenceContent(hasLanguage: false), capture: .string),
        MappingCase(kind: .codeFenceContent(hasLanguage: true), capture: nil),
        MappingCase(kind: .codeBlock, capture: .string),
        MappingCase(kind: .tableSeparator, capture: .keyword),
        MappingCase(kind: .frontMatterDelimiter, capture: .keyword),
        MappingCase(kind: .frontMatterContent, capture: nil),
        MappingCase(kind: .htmlComment, capture: .comment),
        MappingCase(kind: .htmlTag, capture: nil),
        MappingCase(kind: .htmlTagName, capture: .keyword),
        MappingCase(kind: .htmlAttributeName, capture: nil),
        MappingCase(kind: .htmlAttributeValue, capture: .string),
        MappingCase(kind: .htmlCode, capture: nil),
        MappingCase(kind: .inlineHtml, capture: nil),
        MappingCase(kind: .codeSpan, capture: .string),
        MappingCase(kind: .codeSpanMarker, capture: .keyword),
        MappingCase(kind: .italic, capture: nil),
        MappingCase(kind: .italicMarker, capture: .keyword),
        MappingCase(kind: .bold, capture: nil),
        MappingCase(kind: .boldMarker, capture: .keyword),
        MappingCase(kind: .strikethrough, capture: nil),
        MappingCase(kind: .highlight, capture: .typeAlternate),
        MappingCase(kind: .inlineLink, capture: .string),
        MappingCase(kind: .image, capture: nil),
        MappingCase(kind: .linkText, capture: .number),
        MappingCase(kind: .linkLabel, capture: .keyword),
        MappingCase(kind: .linkDestination, capture: .number),
        MappingCase(kind: .linkTitle, capture: .string),
        MappingCase(kind: .autolink, capture: .number),
        MappingCase(kind: .escape, capture: nil),
        MappingCase(kind: .hardBreak, capture: nil)
    ]

    @Test(arguments: mappingCases)
    func mapsTokenKindToCapture(_ mapping: MappingCase) {
        let capture = MarkdownHighlightProvider.captureMapping[mapping.kind]
        #expect(capture == mapping.capture)
    }

    @Test func headerTextMarkerCodeAndQuoteUseFourDistinctCaptures() {
        let header = MarkdownHighlightProvider.captureMapping[.headerContent(level: 1)]
        let marker = MarkdownHighlightProvider.captureMapping[.headerMarker]
        let code = MarkdownHighlightProvider.captureMapping[.codeSpan]
        let quote = MarkdownHighlightProvider.captureMapping[.blockQuoteMarker]
        let distinct = Set([header, marker, code, quote].compactMap { $0 })
        #expect(distinct.count == 4)
    }

    private func runs(_ text: String, in range: NSRange? = nil) -> [String] {
        let query = range ?? NSRange(location: 0, length: (text as NSString).length)
        return MarkdownHighlightProvider.highlights(text: text, in: query).map { run in
            let capture = run.capture.map { "\($0)" } ?? "none"
            return "\((text as NSString).substring(with: run.range))|\(capture)"
        }
    }

    @Test func codeSpanInsideHeaderKeepsMarkersAndCodeColors() {
        let result = runs("# Title `code`")
        #expect(result == ["#|keyword", "Title |variable", "`|keyword", "code|string", "`|keyword"])
    }

    @Test func adjacentEmphasisMarkersMergeIntoOneRun() {
        let result = runs("***x***")
        #expect(result == ["***|keyword", "***|keyword"])
    }

    @Test func fenceWithLanguageLeavesBodyToInjectedHighlighting() {
        let result = runs("```swift\nlet x = 1\n```")
        #expect(result == ["```|keyword", "swift|variable", "```|keyword"])
    }

    @Test func fenceWithoutLanguageColorsBodyAsString() {
        let result = runs("```\ncode\n```")
        #expect(result == ["```|keyword", "code|string", "```|keyword"])
    }

    @Test func blockQuoteMarkersUseCommentCapture() {
        let result = runs("> > x")
        #expect(result == [">|comment", ">|comment"])
    }

    @Test func listMarkerIsKeywordAndCheckboxIsUncolored() {
        let result = runs("- [ ] t")
        #expect(result == ["-|keyword"])
    }

    @Test func tablePipesAndDelimiterRowAreKeywords() {
        let result = runs("| a |\n|---|\n| b |")
        #expect(result == ["||keyword", "||keyword", "|---||keyword", "||keyword", "||keyword"])
    }

    @Test func frontMatterDelimitersAreKeywordsAndContentIsLeftToYaml() {
        let result = runs("---\ntitle: x\n---\n# H")
        #expect(result == ["---|keyword", "---|keyword", "#|keyword", "H|variable"])
    }

    @Test func htmlCommentUsesCommentCapture() {
        let result = runs("a <!-- c --> b")
        #expect(result == ["<!-- c -->|comment"])
    }

    @Test func inlineLinkLayersTextDestinationAndTitle() {
        let result = runs("[t](d \"x\")")
        #expect(result == ["[t]|number", "(|string", "d|number", " \"x\")|string"])
    }

    @Test func plainTextProducesNoRuns() {
        let result = runs("just some words, nothing special")
        #expect(result.isEmpty)
    }

    @Test func emptyQueryRangeProducesNoRuns() {
        let result = MarkdownHighlightProvider.highlights(
            text: "# Title",
            in: NSRange(location: 3, length: 0)
        )
        #expect(result.isEmpty)
    }

    @Test(arguments: [
        (NSRange(location: 8, length: 6), ["`|keyword", "code|string", "`|keyword"]),
        (NSRange(location: 3, length: 4), ["itle|variable"]),
        (NSRange(location: 0, length: 1), ["#|keyword"]),
        (NSRange(location: 9, length: 2), ["co|string"])
    ])
    func clipsRunsToTheQueriedRange(_ range: NSRange, _ expected: [String]) {
        let result = runs("# Title `code`", in: range)
        #expect(result == expected)
    }

    @Test func rangesCountUTF16UnitsForSurrogatePairs() {
        let text = "\u{1F600} `x`"
        let result = MarkdownHighlightProvider.highlights(
            text: text,
            in: NSRange(location: 0, length: (text as NSString).length)
        )
        let locations = result.map { [$0.range.location, $0.range.length] }
        #expect(locations == [[3, 1], [4, 1], [5, 1]])
    }

    @Test func runsAreSortedAndNeverOverlap() {
        let text = "# A **b** `c` [d](e \"f\")\n\n> g *h*\n\n- [x] i ==j==\n\n```\nk\n```\n"
        let result = MarkdownHighlightProvider.highlights(
            text: text,
            in: NSRange(location: 0, length: (text as NSString).length)
        )
        var previousEnd = 0
        var ordered = true
        for run in result {
            if run.range.location < previousEnd { ordered = false }
            previousEnd = run.range.location + run.range.length
        }
        #expect(ordered)
        #expect(!result.isEmpty)
    }
}
