import Foundation
import Testing
@testable import Dreamder

struct JoinLinesTests {
    private static let multiCaretDirectory = "platform/platform-tests/testData/editor/multiCaret"
    private static let javaDirectory = "java/java-tests/testData/codeInsight/joinLines"
    private static let pythonDirectory = "python/testData/joinLines"

    struct Fixture: Sendable, CustomStringConvertible {
        let before: String
        let after: String

        var description: String { before }
    }

    static let genericFixtures: [Fixture] = [
        Fixture(before: "\(javaDirectory)/Normal.java", after: "\(javaDirectory)/Normal_after.java"),
        Fixture(
            before: "\(javaDirectory)/ReformatInsertsNewlines.java",
            after: "\(javaDirectory)/ReformatInsertsNewlines_after.java"
        ),
        Fixture(before: "\(javaDirectory)/SCR6299.java", after: "\(javaDirectory)/SCR6299_after.java"),
        Fixture(before: "\(javaDirectory)/AtEOF.java", after: "\(javaDirectory)/AtEOF_after.java"),
        Fixture(before: "\(pythonDirectory)/SlashAtFirstLine.py", after: "\(pythonDirectory)/SlashAtFirstLine-after.py"),
    ]

    private func joinedMarkup(_ markup: String, lineCommentPrefix: String? = nil) -> EditorMarkup? {
        let source = EditorMarkup(markup)
        guard let result = JoinLines.perform(
            in: NSString(string: source.text),
            selections: source.selections,
            lineCommentPrefix: lineCommentPrefix
        ) else {
            return nil
        }
        let storage = NSMutableString(string: source.text)
        for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return EditorMarkup(text: storage as String, selections: result.selections)
    }

    private func joined(_ markup: String, lineCommentPrefix: String? = nil) -> String? {
        joinedMarkup(markup, lineCommentPrefix: lineCommentPrefix)?.rendered
    }

    @Test
    func editorJoinLinesFixtureMatchesIntelliJ() throws {
        let before = try IntelliJTestData.text("\(Self.multiCaretDirectory)/EditorJoinLines-before.txt")
        let after = try IntelliJTestData.text("\(Self.multiCaretDirectory)/EditorJoinLines-after.txt")
        #expect(joined(before) == EditorMarkup.normalized(after))
    }

    @Test(arguments: JoinLinesTests.genericFixtures)
    func languageIndependentJoinLinesFixturesMatchIntelliJ(fixture: Fixture) throws {
        let before = try IntelliJTestData.text(fixture.before)
        let expected = EditorMarkup(try IntelliJTestData.text(fixture.after))
        let actual = try #require(joinedMarkup(before))
        #expect(actual.text == expected.text)
        if !expected.selections.isEmpty {
            #expect(actual.selections == expected.selections)
        }
    }

    @Test
    func selectionJoinsEveryTouchedLineWithSingleSpaces() {
        #expect(joined("<selection>a\n  b\n  c</selection>\nd") == EditorMarkup.normalized("<selection>a b c<caret></selection>\nd"))
    }

    @Test
    func selectionEndingAtLineStartJoinsNothing() {
        #expect(joined("<selection>a\n</selection>b\nc") == nil)
    }

    @Test
    func leadingBlankLineIsRemovedTogetherWithItsLineBreak() {
        #expect(joined("<caret>  \n  a") == EditorMarkup.normalized("<caret>a"))
    }

    @Test
    func blankFirstLineInsideASelectionIsRemovedAndTheRestJoined() {
        #expect(joined("<selection> \n a\n b</selection>") == EditorMarkup.normalized("<selection>a b<caret></selection>"))
    }

    @Test
    func trailingWhitespaceOfTheFirstLineIsCollapsed() {
        #expect(joined("a  <caret>\n  b") == EditorMarkup.normalized("a<caret> b"))
    }

    @Test
    func noSpaceIsInsertedWhenNothingFollowsTheJoinPoint() {
        #expect(joined("a<caret>\n   ") == EditorMarkup.normalized("a<caret>"))
    }

    @Test
    func caretOnTheLastLineJoinsNothing() {
        #expect(joined("a\nb<caret>") == nil)
    }

    @Test
    func emptyLinesFollowingTheCaretLineAreAbsorbed() {
        #expect(joined("a<caret>\n\n\nb") == EditorMarkup.normalized("a<caret> b"))
    }

    @Test
    func everyCaretOfALineJoinsTheNextLine() {
        #expect(joined("a<caret>b<caret>c\nd\ne") == EditorMarkup.normalized("abc<caret> d<caret> e"))
    }

    @Test
    func noSelectionsMeansNothingToDo() {
        #expect(JoinLines.perform(in: "a\nb", selections: []) == nil)
    }

    @Test
    func closingBracketsAndCommasAttachWithoutASpace() {
        #expect(joined("foo(<caret>\n    )") == EditorMarkup.normalized("foo(<caret>)"))
        #expect(joined("a<caret>\n  , b") == EditorMarkup.normalized("a<caret>, b"))
        #expect(joined("[1<caret>\n]") == EditorMarkup.normalized("[1<caret>]"))
        #expect(joined("a<caret>\n  (b") == EditorMarkup.normalized("a<caret> (b"))
    }

    @Test
    func lineCommentPrefixOfTheContinuationLineIsRemovedWhenBothLinesAreComments() {
        let prefix = "//"
        #expect(
            joined("// one<caret>\n// two", lineCommentPrefix: prefix) == EditorMarkup.normalized("// one<caret> two")
        )
        #expect(
            joined("<selection>// a\n// b\n// c</selection>", lineCommentPrefix: prefix)
                == EditorMarkup.normalized("<selection>// a b c<caret></selection>")
        )
        #expect(
            joined("// a<caret>\n// ,b", lineCommentPrefix: prefix) == EditorMarkup.normalized("// a<caret>,b")
        )
        #expect(joined("# a<caret>\n#b", lineCommentPrefix: "#") == EditorMarkup.normalized("# a<caret> b"))
    }

    @Test
    func lineCommentPrefixIsKeptWhenOnlyOneSideIsAComment() {
        let prefix = "//"
        #expect(joined("// one<caret>\ntwo", lineCommentPrefix: prefix) == EditorMarkup.normalized("// one<caret> two"))
        #expect(joined("one<caret>\n// two", lineCommentPrefix: prefix) == EditorMarkup.normalized("one<caret> // two"))
        #expect(
            joined("x // one<caret>\n// two", lineCommentPrefix: prefix)
                == EditorMarkup.normalized("x // one<caret> // two")
        )
    }

    @Test
    func withoutALineCommentPrefixCommentsAreJoinedVerbatim() {
        #expect(joined("// one<caret>\n// two") == EditorMarkup.normalized("// one<caret> // two"))
        #expect(joined("// one<caret>\n// two", lineCommentPrefix: "") == EditorMarkup.normalized("// one<caret> // two"))
    }
}

@MainActor
@Suite(.uiGate)
struct JoinLinesHostedTests {
    @Test
    func joinsTheCaretLineWithTheNextOne() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "one<caret>\n   two\nthree")
            defer { harness.close() }
            harness.actions.joinLines()
            #expect(harness.rendered == EditorMarkup.normalized("one<caret> two\nthree"))
        }
    }

    @Test
    func joinsTheIntelliJMultiCaretFixtureAndUndoesInOneStep() async throws {
        let before = try IntelliJTestData.text("platform/platform-tests/testData/editor/multiCaret/EditorJoinLines-before.txt")
        let after = try IntelliJTestData.text("platform/platform-tests/testData/editor/multiCaret/EditorJoinLines-after.txt")
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: before)
            defer { harness.close() }
            let original = harness.text
            harness.actions.joinLines()
            #expect(harness.rendered == EditorMarkup.normalized(after))
            harness.textView.undoManager?.undo()
            #expect(harness.text == original)
        }
    }
}
