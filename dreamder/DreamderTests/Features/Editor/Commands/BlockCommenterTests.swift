import Foundation
import Testing
@testable import Dreamder

struct BlockCommenterTests {
    private static let javaDirectory = "java/java-tests/testData/codeInsight/commentByBlock/java"
    private static let xmlDirectory = "xml/tests/testData/codeInsight/commentByBlock/xml"
    private static let htmlDirectory = "xml/tests/testData/codeInsight/commentByBlock/html"
    private static let jsonDirectory = "json/backend/tests/testData/commenter"

    private static let intersectsMessage = "Block comment intersects an existing comment"
    private static let wrappingSuffixMessage = "Selection contains a block comment suffix outside of a comment"

    private static let javaIndented: CommentLanguage = {
        var language = CommentLanguage.javaStyle
        language.blockCommentAtFirstColumn = false
        return language
    }()

    private static let javaWithoutTokenDetection: CommentLanguage = {
        var language = CommentLanguage.javaStyle
        language.detectsCommentTokens = false
        return language
    }()

    struct Fixture: Sendable, CustomStringConvertible {
        let before: String
        let after: String
        let language: CommentLanguage

        var description: String { "\(before) -> \(after)" }
    }

    static let fixtures: [Fixture] = [
        Fixture(before: "\(javaDirectory)/before1.java", after: "\(javaDirectory)/after1.java", language: .javaStyle),
        Fixture(before: "\(javaDirectory)/before2.java", after: "\(javaDirectory)/after2.java", language: .javaStyle),
        Fixture(before: "\(javaDirectory)/before3.java", after: "\(javaDirectory)/after3.java", language: .javaStyle),
        Fixture(before: "\(javaDirectory)/before4.java", after: "\(javaDirectory)/after4.java", language: javaIndented),
        Fixture(before: "\(javaDirectory)/before5.java", after: "\(javaDirectory)/after5.java", language: javaIndented),
        Fixture(
            before: "\(javaDirectory)/beforeIdeadev27995.java",
            after: "\(javaDirectory)/afterIdeadev27995.java",
            language: .javaStyle
        ),
        Fixture(
            before: "\(javaDirectory)/MulticaretBefore.java",
            after: "\(javaDirectory)/MulticaretAfter.java",
            language: .javaStyle
        ),
        Fixture(
            before: "\(javaDirectory)/MulticaretUncommentBefore.java",
            after: "\(javaDirectory)/MulticaretUncommentAfter.java",
            language: .javaStyle
        ),
        Fixture(before: "\(xmlDirectory)/before1.xml", after: "\(xmlDirectory)/after1.xml", language: .markup),
        Fixture(before: "\(xmlDirectory)/before2.xml", after: "\(xmlDirectory)/after2.xml", language: .markup),
        Fixture(before: "\(xmlDirectory)/before3.xml", after: "\(xmlDirectory)/after3.xml", language: .markup),
        Fixture(before: "\(xmlDirectory)/after3.xml", after: "\(xmlDirectory)/before3.xml", language: .markup),
        Fixture(
            before: "\(xmlDirectory)/beforeDoubleDash.xml",
            after: "\(xmlDirectory)/afterDoubleDash.xml",
            language: .markup
        ),
        Fixture(
            before: "\(xmlDirectory)/afterDoubleDash.xml",
            after: "\(xmlDirectory)/beforeDoubleDash.xml",
            language: .markup
        ),
        Fixture(
            before: "\(xmlDirectory)/beforeSingleDash.xml",
            after: "\(xmlDirectory)/afterSingleDash.xml",
            language: .markup
        ),
        Fixture(
            before: "\(xmlDirectory)/beforeSelfClosing.xml",
            after: "\(xmlDirectory)/afterSelfClosing.xml",
            language: .markup
        ),
        Fixture(
            before: "\(xmlDirectory)/afterSelfClosing.xml",
            after: "\(xmlDirectory)/beforeSelfClosing.xml",
            language: .markup
        ),
        Fixture(before: "\(xmlDirectory)/before4.xml", after: "\(xmlDirectory)/after4.xml", language: .markup),
        Fixture(before: "\(xmlDirectory)/before5.xml", after: "\(xmlDirectory)/after5.xml", language: .markup),
        Fixture(
            before: "\(xmlDirectory)/beforeIdeaDev25498_1.xml",
            after: "\(xmlDirectory)/afterIdeaDev25498_1.xml",
            language: .markup
        ),
        Fixture(
            before: "\(xmlDirectory)/beforeIdeaDev25498_2.xml",
            after: "\(xmlDirectory)/afterIdeaDev25498_2.xml",
            language: .markup
        ),
        Fixture(before: "\(htmlDirectory)/before1.html", after: "\(htmlDirectory)/after1.html", language: .markup),
        Fixture(before: "\(htmlDirectory)/before2.html", after: "\(htmlDirectory)/after2.html", language: .markup),
        Fixture(before: "\(htmlDirectory)/before3.html", after: "\(htmlDirectory)/after3.html", language: .markup),
        Fixture(
            before: "\(jsonDirectory)/BlockComment.json",
            after: "\(jsonDirectory)/BlockComment_after.json",
            language: .json
        ),
    ]

    private static func fixtureMarkup(_ raw: String) -> EditorMarkup {
        let parsed = EditorMarkup(raw)
        let ranged = parsed.selections.filter { $0.length > 0 }
        return EditorMarkup(text: parsed.text, selections: ranged.isEmpty ? parsed.selections : ranged)
    }

    private func applied(
        _ text: String,
        selections: [NSRange],
        language: CommentLanguage
    ) -> (text: String, selections: [NSRange])? {
        let outcome = BlockCommenter.toggle(in: NSString(string: text), selections: selections, language: language)
        guard case .edit(let result) = outcome else { return nil }
        let storage = NSMutableString(string: text)
        for edit in result.edits.sorted(by: { $0.range.location > $1.range.location }) {
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return (storage as String, result.selections)
    }

    private func toggled(_ markup: String, language: CommentLanguage) -> EditorMarkup? {
        let source = EditorMarkup(markup)
        guard let result = applied(source.text, selections: source.selections, language: language) else { return nil }
        return EditorMarkup(text: result.text, selections: result.selections)
    }

    private func outcome(_ markup: String, language: CommentLanguage) -> LineCommenter.Outcome {
        let source = EditorMarkup(markup)
        return BlockCommenter.toggle(in: NSString(string: source.text), selections: source.selections, language: language)
    }

    private func expectToggle(_ markup: String, _ expected: String, language: CommentLanguage) {
        #expect(toggled(markup, language: language)?.rendered == EditorMarkup.normalized(expected))
    }

    @Test(arguments: BlockCommenterTests.fixtures)
    func blockCommentFixturesMatchIntelliJ(fixture: Fixture) throws {
        let before = Self.fixtureMarkup(try IntelliJTestData.text(fixture.before))
        let expected = Self.fixtureMarkup(try IntelliJTestData.text(fixture.after))
        let actual = try #require(
            applied(before.text, selections: before.selections, language: fixture.language)
        )
        #expect(actual.text == expected.text)
        if !expected.selections.isEmpty {
            #expect(actual.selections == expected.selections)
        }
    }

    @Test
    func stringContainingBlockPrefixIsWrappedWithoutTouchingTheString() {
        expectToggle(
            "class C { <selection>String s = \"/*\";<caret></selection> }",
            "class C { <selection>/*String s = \"/*\";<caret>*/</selection> }",
            language: .javaStyle
        )
    }

    @Test
    func stringContainingBlockSuffixIsRejected() {
        #expect(
            outcome("class C { <selection>String s = \"*/\";<caret></selection> }", language: .javaStyle)
                == .unsupported(Self.wrappingSuffixMessage)
        )
    }

    @Test
    func selectionStartingInsideAnExistingCommentIsRejected() {
        #expect(
            outcome("class C { /* some <selection>comment */ int i = 3;<caret></selection> }", language: .javaStyle)
                == .unsupported(Self.intersectsMessage)
        )
    }

    @Test
    func selectionEndingInsideAnExistingCommentIsRejected() {
        #expect(
            outcome("<selection>a /* b</selection> c */", language: .javaStyle) == .unsupported(Self.intersectsMessage)
        )
    }

    @Test
    func selectionCoveringOnlyTheStartOfACommentIsRejected() {
        #expect(
            outcome("x <selection>/* a</selection>b */", language: .javaStyle) == .unsupported(Self.intersectsMessage)
        )
    }

    @Test
    func selectionStartingRightAfterALineCommentIsRejected() {
        #expect(
            outcome("// c<selection>\nfoo</selection>", language: .javaStyle) == .unsupported(Self.intersectsMessage)
        )
    }

    @Test
    func javadocInsideTheSelectionIsSplitOutOfTheNewComment() {
        expectToggle(
            "class C {\n    <selection>int a;\n    /** doc */\n    int b;<caret></selection>\n}",
            "class C {\n    <selection>/*int a;\n    *//** doc *//*\n    int b;*/<caret></selection>\n}",
            language: .javaStyle
        )
    }

    @Test
    func withoutTokenDetectionExistingCommentTokensAreSplitWithoutWarnings() {
        expectToggle(
            "class C { /* some <selection>comment */ int i = 3;</selection> }",
            "class C { /* some <selection>/*comment *//* int i = 3;*/</selection> }",
            language: Self.javaWithoutTokenDetection
        )
    }

    @Test
    func caretInsertsAnEmptyBlockCommentAndPlacesTheCaretInside() {
        expectToggle("a<caret>b", "a/*<caret>*/b", language: .javaStyle)
    }

    @Test
    func emptyBlockCommentGetsPaddingWhenTheLanguageAddsSpaces() {
        expectToggle("a<caret>b", "a/* <caret> */b", language: .cssLike)
    }

    @Test
    func everyCaretGetsItsOwnEmptyBlockComment() {
        expectToggle("a<caret>b<caret>c", "a/*<caret>*/b/*<caret>*/c", language: .javaStyle)
    }

    @Test
    func emptyCaretEditsAreReportedAsOneInsertion() {
        let outcome = BlockCommenter.toggle(
            in: NSString(string: "ab"),
            selections: [NSRange(location: 1, length: 0)],
            language: .javaStyle
        )
        #expect(
            outcome == .edit(
                EditorCommandResult(
                    edits: [EditorTextEdit(range: NSRange(location: 1, length: 0), replacement: "/**/")],
                    selections: [NSRange(location: 3, length: 0)]
                )
            )
        )
    }

    @Test
    func caretInsideACommentRemovesTheComment() {
        expectToggle("/* a<caret>b */", " a<caret>b ", language: .javaStyle)
    }

    @Test
    func uncommentingRemovesPaddingSpacesWhenTheLanguageAddsThem() {
        expectToggle("a /* <caret>b */ c", "a <caret>b c", language: .cssLike)
    }

    @Test
    func uncommentingAnEmptyPaddedCommentLeavesNothing() {
        expectToggle("/*<caret> */", "<caret>", language: .cssLike)
    }

    @Test
    func uncommentingAMixedSelectionRemovesOnlyTheBlockComment() {
        expectToggle("<selection>// x\n/* a */</selection>", "<selection>// x\n a </selection>", language: .javaStyle)
    }

    @Test
    func caretInsideAnUnterminatedCommentInsertsAnEmptyComment() {
        expectToggle("/* a<caret>bc", "/* a/*<caret>*/bc", language: .javaStyle)
    }

    @Test
    func uncommentingHandlesCrLfLineBreaksAroundTheMarkers() throws {
        let result = try #require(
            applied(
                "x\r\n/*\r\na\r\n*/\r\ny",
                selections: [NSRange(location: 7, length: 0)],
                language: .javaStyle
            )
        )
        #expect(result.text == "x\r\na\r\ny")
        #expect(result.selections == [NSRange(location: 3, length: 0)])
    }

    @Test
    func uncommentingAtTheEndOfTheDocumentKeepsTheTextBetweenTheMarkers() throws {
        let result = try #require(
            applied("/*\na\n*/", selections: [NSRange(location: 3, length: 0)], language: .javaStyle)
        )
        #expect(result.text == "a\n")
        #expect(result.selections == [NSRange(location: 0, length: 0)])
    }

    @Test
    func selectionOfOnlyBlankLinesIsWrappedAtColumnZero() {
        expectToggle("<selection>\n\n</selection>", "<selection>/*\n\n\n*/\n</selection>", language: Self.javaIndented)
    }

    @Test
    func uncommentingStopsAtATrailingPrefixWithoutASuffix() {
        expectToggle("<selection><!--a--> <!--></selection>", "<selection>a <!--></selection>", language: .markup)
    }

    @Test
    func uncommentingRemovesEveryTerminatedBlockBeforeAnUnterminatedPrefix() {
        expectToggle(
            "<selection><!--a--><!--b--> <!--></selection>",
            "<selection>ab <!--></selection>",
            language: .markup
        )
    }

    @Test
    func wholeDocumentSelectionIsWrappedOnItsOwnLines() {
        expectToggle("<selection>a</selection>", "<selection>/*\na*/\n</selection>", language: .javaStyle)
    }

    @Test
    func rejectedCaretsDoNotPreventTheOthersFromBeingCommented() {
        expectToggle(
            "<selection>a</selection> <selection>\"*/\"</selection>",
            "<selection>/*a*/</selection> <selection>\"*/\"</selection>",
            language: .javaStyle
        )
    }

    @Test
    func everyRejectedCaretKeepsTheFirstWarning() {
        #expect(
            outcome("<selection>\"*/\"</selection> <selection>\"*/\"</selection>", language: .javaStyle)
                == .unsupported(Self.wrappingSuffixMessage)
        )
    }

    @Test
    func noSelectionsMeansNothingChanges() {
        #expect(BlockCommenter.toggle(in: NSString(string: "abc"), selections: [], language: .javaStyle) == .unchanged)
    }

    @Test
    func languagesWithoutBlockCommentsAreReportedAsUnsupported() {
        let message = BlockCommenter.unsupportedMessage
        #expect(message == "Block comments are not supported for this file type")
        #expect(outcome("a<caret>", language: .unsupported) == .unsupported(message))
        #expect(outcome("a<caret>", language: .line(prefix: "#")) == .unsupported(message))
        #expect(outcome("a<caret>", language: CommentLanguage(blockPrefix: "/*")) == .unsupported(message))
        #expect(outcome("a<caret>", language: CommentLanguage(blockSuffix: "*/")) == .unsupported(message))
    }

    @Test
    func selectionInsideJsxMarkupUsesJsxExpressionComments() {
        expectToggle(
            "const a = <div><selection>text</selection></div>;",
            "const a = <div><selection>{/* text */}</selection></div>;",
            language: .jsx
        )
    }

    @Test
    func caretInsideJsxMarkupInsertsAnEmptyJsxComment() {
        expectToggle(
            "const a = <div><caret>t</div>;",
            "const a = <div>{/* <caret> */}t</div>;",
            language: .jsx
        )
    }

    @Test
    func jsxExpressionCommentIsUncommentedFromItsOpeningBrace() {
        expectToggle(
            "const a = <div><caret>{/* text */}</div>;",
            "const a = <div><caret>text</div>;",
            language: .jsx
        )
    }

    @Test
    func selectionOutsideJsxMarkupUsesPlainBlockComments() {
        expectToggle(
            "const a = <selection>1</selection>;",
            "const a = <selection>/*1*/</selection>;",
            language: .jsx
        )
    }
}
