import Foundation
import Testing
@testable import Dreamder

struct LineCommenterTests {
    private static let javaDirectory = "java/java-tests/testData/codeInsight/commentByLine/java"
    private static let perlDirectory = "platform/platform-tests/testData/codeInsight/commentByLine/pl"
    private static let xmlDirectory = "xml/tests/testData/codeInsight/commentByLine/xml"
    private static let htmlDirectory = "xml/tests/testData/codeInsight/commentByLine/html"
    private static let jsonDirectory = "json/backend/tests/testData/commenter"

    struct Fixture: Sendable, CustomStringConvertible {
        let before: String
        let after: String
        let language: CommentLanguage

        var description: String { before }
    }

    private static func configured(
        _ language: CommentLanguage,
        atFirstColumn: Bool? = nil,
        addsSpace: Bool? = nil
    ) -> CommentLanguage {
        var result = language
        if let atFirstColumn { result.lineCommentAtFirstColumn = atFirstColumn }
        if let addsSpace { result.lineCommentAddsSpace = addsSpace }
        return result
    }

    private static func java(_ suffix: String, _ language: CommentLanguage, reversed: Bool = false) -> Fixture {
        let before = "\(javaDirectory)/before\(suffix).java"
        let after = "\(javaDirectory)/after\(suffix).java"
        return Fixture(before: reversed ? after : before, after: reversed ? before : after, language: language)
    }

    private static func markupPair(
        _ directory: String,
        _ name: String,
        _ fileExtension: String,
        _ language: CommentLanguage,
        reversed: Bool = false
    ) -> Fixture {
        let before = "\(directory)/before\(name).\(fileExtension)"
        let after = "\(directory)/after\(name).\(fileExtension)"
        return Fixture(before: reversed ? after : before, after: reversed ? before : after, language: language)
    }

    private static let indentedJava = configured(.javaStyle, atFirstColumn: false)
    private static let indentedSpacedJava = configured(.javaStyle, atFirstColumn: false, addsSpace: true)
    private static let spacedJava = configured(.javaStyle, addsSpace: true)
    private static let indentedMarkup = configured(.markup, atFirstColumn: false)
    private static let perl = CommentLanguage(linePrefix: "#")

    static let javaFixtures: [Fixture] = [
        java("1", .javaStyle),
        java("2", .javaStyle),
        java("3", .javaStyle),
        java("4", indentedJava),
        java("5", indentedJava),
        java("6", indentedJava),
        java("MulticaretSingleLine", .javaStyle),
        java("MulticaretBlock", .javaStyle),
        java("MulticaretUncommentSeveralBlocks", .javaStyle),
        java("AddSpace", indentedSpacedJava),
        java("UncommentRemovingSpace", spacedJava),
        java("CommentUncommentDoesNotAddSpacesOnEmptyLine", indentedJava),
        java("CommentUncommentDoesNotAddSpacesOnEmptyLine", indentedJava, reversed: true),
        java("AlignedWithSmartTabs", indentedJava),
    ]

    static let perlFixtures: [Fixture] = [
        Fixture(before: "\(perlDirectory)/before1.pl", after: "\(perlDirectory)/after1.pl", language: perl),
        Fixture(before: "\(perlDirectory)/before2.pl", after: "\(perlDirectory)/after2.pl", language: perl),
    ]

    static let xmlFixtures: [Fixture] = [
        markupPair(xmlDirectory, "1", "xml", .markup),
        markupPair(xmlDirectory, "2", "xml", .markup),
        markupPair(xmlDirectory, "3", "xml", .markup),
        markupPair(xmlDirectory, "4", "xml", indentedMarkup),
        markupPair(xmlDirectory, "5", "xml", indentedMarkup),
        markupPair(xmlDirectory, "6", "xml", .markup),
        markupPair(xmlDirectory, "7", "xml", .markup),
        markupPair(xmlDirectory, "8", "xml", .markup),
        markupPair(xmlDirectory, "9", "xml", .markup),
        markupPair(xmlDirectory, "10", "xml", .markup),
        markupPair(xmlDirectory, "11", "xml", .markup),
        markupPair(xmlDirectory, "DoubleDash", "xml", .markup),
        markupPair(xmlDirectory, "DoubleDash", "xml", .markup, reversed: true),
        markupPair(xmlDirectory, "SingleDash", "xml", .markup),
        markupPair(xmlDirectory, "SingleDashWithSpace", "xml", .markup),
        markupPair(xmlDirectory, "OtherLine", "xml", .markup),
    ]

    static let htmlFixtures: [Fixture] = [
        markupPair(htmlDirectory, "1", "html", .markup),
        markupPair(htmlDirectory, "2", "html", .markup),
        markupPair(htmlDirectory, "3", "html", .markup),
        markupPair(htmlDirectory, "4", "html", indentedMarkup),
        markupPair(htmlDirectory, "5", "html", indentedMarkup),
        markupPair(htmlDirectory, "6", "html", .markup),
        markupPair(htmlDirectory, "7", "html", .markup),
        markupPair(htmlDirectory, "8", "html", .markup),
        markupPair(htmlDirectory, "9", "html", .markup),
        markupPair(htmlDirectory, "10", "html", .markup),
    ]

    static let jsonFixtures: [Fixture] = [
        Fixture(before: "\(jsonDirectory)/LineComment.json", after: "\(jsonDirectory)/LineComment_after.json", language: .json),
        Fixture(before: "\(jsonDirectory)/LineComment2.json", after: "\(jsonDirectory)/LineComment2_after.json", language: .json),
        Fixture(before: "\(jsonDirectory)/LineComment3.json", after: "\(jsonDirectory)/LineComment3_after.json", language: .json),
    ]

    private static func toggledMarkup(_ source: EditorMarkup, language: CommentLanguage) -> EditorMarkup? {
        let selections = source.selections.isEmpty ? [NSRange(location: 0, length: 0)] : source.selections
        let outcome = LineCommenter.toggle(in: NSString(string: source.text), selections: selections, language: language)
        guard case .edit(let result) = outcome else { return nil }
        let storage = NSMutableString(string: source.text)
        for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return EditorMarkup(text: storage as String, selections: result.selections)
    }

    private static func toggled(_ markup: String, language: CommentLanguage) -> String? {
        toggledMarkup(EditorMarkup(markup), language: language)?.rendered
    }

    private static func significant(_ selections: [NSRange], matching expected: [NSRange]) -> [NSRange] {
        expected.contains { $0.length > 0 } ? selections.filter { $0.length > 0 } : selections
    }

    private func verify(_ fixture: Fixture) throws {
        let source = EditorMarkup(try IntelliJTestData.text(fixture.before))
        let expected = EditorMarkup(try IntelliJTestData.text(fixture.after))
        let actual = try #require(Self.toggledMarkup(source, language: fixture.language))
        #expect(actual.text == expected.text)
        if !expected.selections.isEmpty {
            #expect(
                Self.significant(actual.selections, matching: expected.selections)
                    == Self.significant(expected.selections, matching: expected.selections)
            )
        }
    }

    private func expectToggle(
        _ markup: String,
        _ expected: String,
        _ language: CommentLanguage,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            Self.toggled(markup, language: language) == EditorMarkup.normalized(expected),
            sourceLocation: sourceLocation
        )
    }

    private func expectUnchanged(
        _ markup: String,
        _ language: CommentLanguage,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(Self.toggled(markup, language: language) == nil, sourceLocation: sourceLocation)
    }

    @Test(arguments: LineCommenterTests.javaFixtures)
    func javaFixturesMatchIntelliJ(fixture: Fixture) throws {
        try verify(fixture)
    }

    @Test(arguments: LineCommenterTests.perlFixtures)
    func customFileTypeFixturesMatchIntelliJ(fixture: Fixture) throws {
        try verify(fixture)
    }

    @Test(arguments: LineCommenterTests.xmlFixtures)
    func xmlFixturesMatchIntelliJ(fixture: Fixture) throws {
        try verify(fixture)
    }

    @Test(arguments: LineCommenterTests.htmlFixtures)
    func htmlFixturesMatchIntelliJ(fixture: Fixture) throws {
        try verify(fixture)
    }

    @Test(arguments: LineCommenterTests.jsonFixtures)
    func jsonFixturesMatchIntelliJ(fixture: Fixture) throws {
        try verify(fixture)
    }

    @Test
    func unsupportedLanguagesReportTheUnsupportedMessage() {
        let outcome = LineCommenter.toggle(
            in: NSString(string: "a"),
            selections: [NSRange(location: 0, length: 0)],
            language: .unsupported
        )

        #expect(outcome == .unsupported(LineCommenter.unsupportedMessage))
        #expect(LineCommenter.unsupportedMessage == "Comments are not supported for this file type")
    }

    @Test
    func incompleteBlockPairsAreUnsupported() {
        let outcome = LineCommenter.toggle(
            in: NSString(string: "a"),
            selections: [NSRange(location: 0, length: 0)],
            language: CommentLanguage(blockPrefix: "/*")
        )

        #expect(outcome == .unsupported(LineCommenter.unsupportedMessage))
    }

    @Test
    func emptyDocumentsAreLeftAlone() {
        let outcome = LineCommenter.toggle(
            in: NSString(string: ""),
            selections: [NSRange(location: 0, length: 0)],
            language: .javaStyle
        )

        #expect(outcome == .unchanged)
    }

    @Test
    func noSelectionsMeansNothingToDo() {
        #expect(LineCommenter.toggle(in: NSString(string: "a"), selections: [], language: .javaStyle) == .unchanged)
    }

    @Test
    func editAndResultingSelectionAreReported() {
        let outcome = LineCommenter.toggle(
            in: NSString(string: "a\nb"),
            selections: [NSRange(location: 1, length: 0)],
            language: .javaStyle
        )

        #expect(
            outcome == .edit(
                EditorCommandResult(
                    edits: [EditorTextEdit(range: NSRange(location: 0, length: 0), replacement: "//")],
                    selections: [NSRange(location: 5, length: 0)]
                )
            )
        )
    }

    @Test
    func commentingMovesTheCaretToTheSameColumnOfTheNextLine() {
        expectToggle("a<caret>\nxyzw", "//a\nxyz<caret>w", .javaStyle)
    }

    @Test
    func caretOnTheLastLineStaysPut() {
        expectToggle("a\nb<caret>", "a\n//b<caret>", .javaStyle)
    }

    @Test
    func caretAtTheInsertionPointStaysBeforeTheInsertedPrefix() {
        expectToggle("<caret>ab\ncdef", "//ab\n<caret>cdef", .javaStyle)
    }

    @Test
    func uncommentingMovesTheCaretToTheNextLine() {
        expectToggle("//a<caret>\nxyzw", "a\nx<caret>yzw", .javaStyle)
    }

    @Test
    func carriageReturnLineFeedLinesAreSkippedAsOneBreak() {
        expectToggle("a<caret>\r\nxyzw", "//a\r\nxyz<caret>w", .javaStyle)
    }

    @Test
    func spacedPrefixesAreAddedAndRemovedTogetherWithTheirSpace() {
        expectToggle("a<caret>\nb", "// a\nb<caret>", .cFamily)
        expectToggle("// a<caret>\nb", "a\nb<caret>", .cFamily)
        expectToggle("//a<caret>\nb", "a\nb<caret>", .cFamily)
    }

    @Test
    func caretOnAnEmptyLineLandsAfterTheNewPrefix() {
        expectToggle("  a\n<caret>\n  b", "  a\n  // <caret>\n  b", .cFamily)
    }

    @Test
    func selectedBlankLinesGetBarePrefixesAndUncommentToNothing() {
        expectToggle("<selection>a\n\nb</selection>", "//<selection>a\n//\n//b</selection>", .javaStyle)
        expectToggle("//<selection>a\n//\n//b</selection>", "<selection>a\n\nb</selection>", .javaStyle)
    }

    @Test
    func selectionOfOnlyEmptyLinesIsCommentedThenUncommentedAsWholeLines() {
        expectToggle("<selection>\n\n</selection>x", "<selection>//\n//\n</selection>x", .javaStyle)
        expectToggle("<selection>//\n//\n</selection>x", "<selection>\n\n</selection>x", .javaStyle)
    }

    @Test
    func aSelectionWithOneUncommentedLineCommentsEveryLine() {
        expectToggle("<selection>//a\nb</selection>", "//<selection>//a\n//b</selection>", .javaStyle)
    }

    @Test
    func separateBlocksAreCommentedTogetherWhenAnyLineIsUncommented() {
        expectToggle("//a<caret>\nx\nb<caret>", "////a\nx<caret>\n//b<caret>", .javaStyle)
    }

    @Test
    func tabsCountAsFourColumnsWhenAligningTheComment() {
        expectToggle(
            "<selection>\t\ta\n\tb</selection>",
            "<selection>\t// \ta\n\t// b</selection>",
            .cFamily
        )
    }

    @Test
    func shortWhitespaceOnlyLinesAreExtendedToTheCommonIndent() {
        expectToggle(
            "<selection>    a\n \n    b</selection>",
            "<selection>    // a\n    //\n    // b</selection>",
            .cFamily
        )
    }

    @Test
    func previousCommentIndentWinsWhenItIsNarrower() {
        expectToggle("  // x\n    a<caret>", "  // x\n  //   a<caret>", .cFamily)
    }

    @Test
    func blockIndentWinsWhenItIsNarrowerThanThePreviousComment() {
        expectToggle("      // x\n  a<caret>", "      // x\n  // a<caret>", .cFamily)
    }

    @Test
    func previousCommentIndentIsUsedWhenTheSelectedLinesAreAllEmpty() {
        expectToggle(
            "  // x\n<selection>\n\n</selection>y",
            "  // x\n<selection>  //\n  //\n</selection>y",
            .cFamily
        )
    }

    @Test
    func blockOnlyLanguagesWrapTheLineInABlockComment() {
        expectToggle("a {}<caret>", "/* a {}<caret> */", .cssLike)
        expectToggle("/* a {} */<caret>", "a {}<caret>", .cssLike)
        expectToggle("/*a*/<caret>", "a<caret>", .cssLike)
    }

    @Test
    func trailingWhitespaceStaysOutsideTheBlockComment() {
        expectToggle("a {}  <caret>", "/* a {} */  <caret>", .cssLike)
    }

    @Test
    func overlappingPrefixAndSuffixUncommentWithoutTrapping() {
        expectToggle("<caret>/*/", "<caret>", .cssLike)
    }

    @Test
    func paddedOverlappingSuffixKeepsTheSharedSlash() {
        expectToggle("<caret>/* /*/", "<caret>/", .cssLike)
    }

    @Test
    func emptyLineGetsAnEmptyBlockCommentWithTheCaretInside() {
        expectToggle("x\n<caret>\ny", "x\n/* <caret> */\ny", .cssLike)
    }

    @Test
    func caretMovedPastTheEndOfTheDocumentIsClamped() {
        expectToggle("<caret>x\ny\n<caret>\n", "/* x */\n<caret>y\n\n<caret>", .cssLike)
    }

    @Test
    func blockCommentsSkipEmptyLinesInsideASelection() {
        expectToggle(
            "<selection>a\n\nb\n</selection>c",
            "<selection>/* a */\n\n/* b */\n</selection>c",
            .cssLike
        )
        expectToggle(
            "<selection>/* a */\n\n/* b */\n</selection>c",
            "<selection>a\n\nb\n</selection>c",
            .cssLike
        )
    }

    @Test
    func blockCommentsOfOnlyEmptyLinesChangeNothing() {
        expectUnchanged("<selection>\n\n</selection>x", .cssLike)
    }

    @Test
    func trailingWhitespaceOnlyLineAtTheEndOfTheDocumentCannotBeCommented() {
        expectUnchanged("a\n  <caret>", .cssLike)
    }

    @Test
    func nestedBlockCommentsAreClosedAndReopenedAroundTheInnerComment() {
        expectToggle("<caret>a /* b */ c", "<caret>/* a  *//* b *//*  c */", .cssLike)
    }

    @Test
    func aTrailingInnerCommentNeedsNoExtraSuffix() {
        expectToggle("<caret>a /* b */", "<caret>/* a  *//* b */", .cssLike)
    }

    @Test
    func aLeadingInnerCommentNeedsNoExtraPrefix() {
        expectToggle("<caret>/* a */ b", "<caret>/* a *//*  b */", .cssLike)
    }

    @Test
    func aSuffixBeforeAPrefixIsHandledInDocumentOrder() {
        expectToggle("<caret>a */ b /* c", "<caret>/* a *//*  b  *//* c */", .cssLike)
    }

    @Test
    func jsxMarkupLinesAreWrappedInBracedBlockComments() {
        expectToggle(
            "function A() {\n  return (\n    <div>\n      <span><caret>x</span>\n    </div>\n  );\n}\n",
            "function A() {\n  return (\n    <div>\n      {/* <span>x</span> */}\n    </div><caret>\n  );\n}\n",
            .jsx
        )
    }

    @Test
    func jsxMarkupCommentsAreRemovedAgain() {
        expectToggle(
            "function A() {\n  return (\n    <div>\n      {/* <caret><span>x</span> */}\n    </div>\n  );\n}\n",
            "function A() {\n  return (\n    <div>\n      <span>x</span>\n    </<caret>div>\n  );\n}\n",
            .jsx
        )
    }

    @Test
    func scriptLinesInJsxFilesUseLineComments() {
        expectToggle("const a = 1;<caret>\nconst b = 2;", "// const a = 1;\nconst b = 2;<caret>", .jsx)
    }

    @Test
    func jsxMarkupCommentIndentFollowsThePreviousMarkupComment() {
        expectToggle(
            "const a = (\n  <div>\n      {/* <b/> */}\n    <caret><i/>\n  </div>\n);\n",
            "const a = (\n  <div>\n      {/* <b/> */}\n    {/* <i/> */}\n  </<caret>div>\n);\n",
            .jsx
        )
    }

    @Test
    func jsxSelectionMixesMarkupAndScriptCommentStyles() {
        expectToggle(
            "<selection>  <a/>\n  x = 1;</selection>",
            "<selection>  {/* <a/> */}\n  // x = 1;</selection>",
            .jsx
        )
    }
}
