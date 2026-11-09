import Foundation
import Testing
@testable import Dreamder

struct CommentRegionScannerTests {
    private func regions(_ text: String, language: CommentLanguage) -> [CommentRegion] {
        CommentRegionScanner.regions(in: Array(text.utf16), language: language)
    }

    @Test
    func lineAndBlockCommentsAreReportedWithTheirRanges() {
        #expect(
            regions("a // x\nb /* y */ c", language: .javaStyle)
                == [
                    CommentRegion(range: 2..<6, isLine: true),
                    CommentRegion(range: 9..<16, isLine: false),
                ]
        )
    }

    @Test
    func lineCommentEndsBeforeEitherLineBreakKind() {
        #expect(regions("// a\r\nb", language: .javaStyle) == [CommentRegion(range: 0..<4, isLine: true)])
        #expect(regions("// a\rb", language: .javaStyle) == [CommentRegion(range: 0..<4, isLine: true)])
    }

    @Test
    func lineCommentAtTheEndOfTheTextRunsToTheEnd() {
        #expect(regions("a // b", language: .javaStyle) == [CommentRegion(range: 2..<6, isLine: true)])
    }

    @Test
    func blockCommentSpansLinesAndIncludesItsSuffix() {
        #expect(regions("/* a\n b */x", language: .javaStyle) == [CommentRegion(range: 0..<10, isLine: false)])
    }

    @Test
    func unterminatedBlockCommentRunsToTheEnd() {
        #expect(regions("a /* b", language: .javaStyle) == [CommentRegion(range: 2..<6, isLine: false)])
        #expect(regions("/*/", language: .javaStyle) == [CommentRegion(range: 0..<3, isLine: false)])
    }

    @Test
    func blockCommentSuffixSearchStartsAfterThePrefix() {
        #expect(regions("/*/ x */", language: .javaStyle) == [CommentRegion(range: 0..<8, isLine: false)])
    }

    @Test
    func consecutiveCommentsAreSeparateRegions() {
        #expect(
            regions("/*a*//*b*/", language: .javaStyle)
                == [
                    CommentRegion(range: 0..<5, isLine: false),
                    CommentRegion(range: 5..<10, isLine: false),
                ]
        )
    }

    @Test
    func commentTokensInsideDoubleQuotedStringsAreIgnored() {
        #expect(regions("\"//\" /* a */", language: .javaStyle) == [CommentRegion(range: 5..<12, isLine: false)])
        #expect(regions("\"/*\" x", language: .javaStyle).isEmpty)
    }

    @Test
    func commentTokensInsideSingleQuotedStringsAreIgnored() {
        #expect(regions("'//' // b", language: .javaStyle) == [CommentRegion(range: 5..<9, isLine: true)])
    }

    @Test
    func backtickStringsMaySpanLines() {
        #expect(
            regions("`a\n// b` // c", language: .javaStyle) == [CommentRegion(range: 9..<13, isLine: true)]
        )
    }

    @Test
    func quotedStringsEndAtTheLineBreak() {
        #expect(regions("\"abc\n// d", language: .javaStyle) == [CommentRegion(range: 5..<9, isLine: true)])
    }

    @Test
    func escapedQuotesDoNotEndAString() {
        #expect(regions("\"a\\\"// b\" // c", language: .javaStyle) == [CommentRegion(range: 10..<14, isLine: true)])
        #expect(regions("\"a\\\"// b\"", language: .javaStyle).isEmpty)
    }

    @Test
    func emptyStringsAreSkippedWithoutSwallowingTheFollowingComment() {
        #expect(regions("\"\" // x", language: .javaStyle) == [CommentRegion(range: 3..<7, isLine: true)])
    }

    @Test
    func tripleQuotedStringsHideEverythingUntilTheClosingTriple() {
        #expect(
            regions("\"\"\"\n/* x */\n\"\"\" // y", language: .javaStyle)
                == [CommentRegion(range: 16..<20, isLine: true)]
        )
    }

    @Test
    func unterminatedTripleQuotedStringHidesTheRest() {
        #expect(regions("\"\"\"abc /* d */", language: .javaStyle).isEmpty)
    }

    @Test
    func unterminatedStringHidesTheRestOfTheText() {
        #expect(regions("\"abc // d", language: .javaStyle).isEmpty)
        #expect(regions("\"abc\\", language: .javaStyle).isEmpty)
        #expect(regions("`abc // d", language: .javaStyle).isEmpty)
    }

    @Test
    func languagesWithoutStringLiteralsTreatQuotesAsPlainText() {
        #expect(
            regions("\"<!-- a -->\"", language: .markup) == [CommentRegion(range: 1..<11, isLine: false)]
        )
    }

    @Test
    func languagesWithoutLineCommentsOnlyReportBlockComments() {
        #expect(regions("// a /* b */", language: .cssLike) == [CommentRegion(range: 5..<12, isLine: false)])
    }

    @Test
    func languagesWithoutBlockCommentsOnlyReportLineComments() {
        #expect(
            regions("a # b\n/* c */", language: .line(prefix: "#")) == [CommentRegion(range: 2..<5, isLine: true)]
        )
    }

    @Test
    func unsupportedLanguagesAndEmptyTextHaveNoRegions() {
        #expect(regions("// a /* b */", language: .unsupported).isEmpty)
        #expect(regions("", language: .javaStyle).isEmpty)
    }

    @Test
    func lineCommentPrefixWinsOverBlockPrefixAtTheSameOffset() {
        #expect(
            regions("-- [[x]]\n--[[y]]", language: .line(prefix: "--", blockPrefix: "--[[", blockSuffix: "]]"))
                == [
                    CommentRegion(range: 0..<8, isLine: true),
                    CommentRegion(range: 9..<16, isLine: true),
                ]
        )
    }
}
