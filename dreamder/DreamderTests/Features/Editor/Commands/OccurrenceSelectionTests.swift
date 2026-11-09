import Foundation
import Testing
@testable import Dreamder

private nonisolated func render(_ text: String, _ result: OccurrenceSelectionResult?) -> String? {
    result.map { EditorMarkup(text: text, selections: $0.selections).rendered }
}

private nonisolated func selectNext(_ markup: String, primary: NSRange? = nil) -> String? {
    let parsed = EditorMarkup(markup)
    return render(
        parsed.text,
        OccurrenceSelection.selectNext(in: parsed.text as NSString, selections: parsed.selections, primary: primary)
    )
}

private nonisolated func selectAll(_ markup: String, primary: NSRange? = nil) -> String? {
    let parsed = EditorMarkup(markup)
    return render(
        parsed.text,
        OccurrenceSelection.selectAll(in: parsed.text as NSString, selections: parsed.selections, primary: primary)
    )
}

nonisolated struct OccurrenceSelectionWordTests {
    @Test
    func selectsTheWordAroundTheCaret() {
        #expect(selectNext("foo b<caret>ar foo") == EditorMarkup.normalized("foo <selection>bar<caret></selection> foo"))
    }

    @Test
    func selectsTheWordWhenTheCaretIsAtItsEnd() {
        #expect(selectNext("foo bar<caret> baz") == EditorMarkup.normalized("foo <selection>bar<caret></selection> baz"))
    }

    @Test
    func selectsTheWordWhenTheCaretIsAtItsStart() {
        #expect(selectNext("foo <caret>bar") == EditorMarkup.normalized("foo <selection>bar<caret></selection>"))
    }

    @Test
    func selectsTheLastWordWhenTheCaretIsAtTheEndOfText() {
        #expect(selectNext("foo<caret>") == EditorMarkup.normalized("<selection>foo<caret></selection>"))
    }

    @Test
    func doesNothingBetweenWhitespace() {
        #expect(selectNext("foo <caret> bar") == nil)
        #expect(selectNext("foo <caret>") == nil)
        #expect(selectAll("foo <caret> bar") == nil)
    }

    @Test
    func doesNothingInAnEmptyDocumentOrWithoutSelections() {
        #expect(selectNext("<caret>") == nil)
        let text = "foo" as NSString
        #expect(OccurrenceSelection.selectNext(in: text, selections: [], primary: nil) == nil)
        #expect(OccurrenceSelection.selectAll(in: text, selections: [], primary: nil) == nil)
        #expect(OccurrenceSelection.unselectLast(selections: [], primary: nil) == nil)
    }

    @Test
    func onlyThePrimaryCaretGetsTheWord() {
        let text = "foo bar" as NSString
        let result = OccurrenceSelection.selectNext(
            in: text,
            selections: [NSRange(location: 1, length: 0), NSRange(location: 5, length: 0)],
            primary: NSRange(location: 5, length: 0)
        )
        #expect(result == OccurrenceSelectionResult(
            selections: [NSRange(location: 1, length: 0), NSRange(location: 4, length: 3)],
            primary: NSRange(location: 4, length: 3)
        ))
    }

    @Test
    func theWordAbsorbsCaretsInsideIt() {
        let text = "foo" as NSString
        let result = OccurrenceSelection.selectNext(
            in: text,
            selections: [NSRange(location: 1, length: 0), NSRange(location: 2, length: 0)],
            primary: NSRange(location: 2, length: 0)
        )
        #expect(result == OccurrenceSelectionResult(
            selections: [NSRange(location: 0, length: 3)],
            primary: NSRange(location: 0, length: 3)
        ))
    }

    @Test
    func identifierPartsFollowJavaRules() {
        #expect(selectNext("a_b$1<caret> é") == EditorMarkup.normalized("<selection>a_b$1<caret></selection> é"))
        #expect(selectNext("😀<caret>") == nil)
        #expect(OccurrenceSelection.isIdentifierPart(0x2D) == false)
    }

    @Test
    func wholeWordRulesMatchFindManager() {
        let backslash = "\\nfoo" as NSString
        #expect(OccurrenceSelection.isWholeWord(in: backslash, range: NSRange(location: 2, length: 3)))
        let plusses = "a++b" as NSString
        #expect(OccurrenceSelection.isWholeWord(in: plusses, range: NSRange(location: 1, length: 1)) == false)
        #expect(OccurrenceSelection.isWholeWord(in: plusses, range: NSRange(location: 2, length: 1)) == false)
        #expect(OccurrenceSelection.isWholeWord(in: plusses, range: NSRange(location: 1, length: 2)))
        let spaced = " + " as NSString
        #expect(OccurrenceSelection.isWholeWord(in: spaced, range: NSRange(location: 1, length: 1)))
        let embedded = "afoob" as NSString
        #expect(OccurrenceSelection.isWholeWord(in: embedded, range: NSRange(location: 1, length: 3)) == false)
        let trailing = "afoo" as NSString
        #expect(OccurrenceSelection.isWholeWord(in: trailing, range: NSRange(location: 1, length: 3)) == false)
        let leading = "foob" as NSString
        #expect(OccurrenceSelection.isWholeWord(in: leading, range: NSRange(location: 0, length: 3)) == false)
    }
}

nonisolated struct OccurrenceSelectionNextTests {
    @Test
    func addsTheNextWholeWordOccurrence() {
        let first = selectNext("<selection>foo<caret></selection> bar foo foobar foo")
        #expect(first == EditorMarkup.normalized("<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar foo"))
    }

    @Test
    func skipsOccurrencesInsideLongerWords() {
        let next = selectNext("<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar foo")
        #expect(next == EditorMarkup.normalized(
            "<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar <selection>foo<caret></selection>"
        ))
    }

    @Test
    func doesNothingWhenEveryOccurrenceIsSelected() {
        let all = "<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar <selection>foo<caret></selection>"
        #expect(selectNext(all) == nil)
        let parsed = EditorMarkup(all)
        let primary = parsed.selections[2]
        #expect(selectNext(all, primary: primary) == nil)
    }

    @Test
    func substringSearchWhenTheSelectionIsNotAWholeWord() {
        let next = selectNext("f<selection>oo<caret></selection> foo ooh")
        #expect(next == EditorMarkup.normalized("f<selection>oo<caret></selection> f<selection>oo<caret></selection> ooh"))
    }

    @Test
    func wrapsAroundTheEndOfTheDocument() {
        let next = selectNext("foo bar <selection>foo<caret></selection>")
        #expect(next == EditorMarkup.normalized("<selection>foo<caret></selection> bar <selection>foo<caret></selection>"))
    }

    @Test
    func skipsOccurrencesThatAreAlreadySelected() {
        let parsed = EditorMarkup("<selection>foo<caret></selection> bar <selection>foo<caret></selection> foo")
        let result = OccurrenceSelection.selectNext(
            in: parsed.text as NSString,
            selections: parsed.selections,
            primary: parsed.selections[0]
        )
        #expect(result?.primary == NSRange(location: 12, length: 3))
        #expect(result?.selections == [
            NSRange(location: 0, length: 3), NSRange(location: 8, length: 3), NSRange(location: 12, length: 3)
        ])
    }

    @Test
    func withoutAnExplicitPrimaryTheLastSelectionIsUsed() {
        let parsed = EditorMarkup("<selection>foo<caret></selection> bar <selection>foo<caret></selection> foo")
        let result = OccurrenceSelection.selectNext(in: parsed.text as NSString, selections: parsed.selections, primary: nil)
        #expect(result?.primary == NSRange(location: 12, length: 3))
        let unknown = OccurrenceSelection.selectNext(
            in: parsed.text as NSString,
            selections: parsed.selections,
            primary: NSRange(location: 100, length: 1)
        )
        #expect(unknown == result)
    }

    @Test
    func repeatedInvocationsWalkThroughTheDocument() {
        let source = EditorMarkup("f<caret>oo bar foo foobar foo")
        var selections = source.selections
        var primary: NSRange?
        var rendered: [String] = []
        for _ in 0..<3 {
            guard let result = OccurrenceSelection.selectNext(in: source.text as NSString, selections: selections, primary: primary) else {
                break
            }
            selections = result.selections
            primary = result.primary
            rendered.append(EditorMarkup(text: source.text, selections: selections).rendered)
        }
        #expect(rendered == [
            EditorMarkup.normalized("<selection>foo<caret></selection> bar foo foobar foo"),
            EditorMarkup.normalized("<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar foo"),
            EditorMarkup.normalized("<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar <selection>foo<caret></selection>"),
        ])
    }
}

nonisolated struct OccurrenceSelectionAllTests {
    @Test
    func selectsEveryWholeWordOfTheWordUnderTheCaret() {
        let result = selectAll("fo<caret>o bar foo foobar foo")
        #expect(result == EditorMarkup.normalized(
            "<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar <selection>foo<caret></selection>"
        ))
    }

    @Test
    func selectsEverySubstringOfAnExistingSelection() {
        let result = selectAll("<selection>foo<caret></selection> bar foobar")
        #expect(result == EditorMarkup.normalized("<selection>foo<caret></selection> bar <selection>foo<caret></selection>bar"))
    }

    @Test
    func occurrencesDoNotOverlap() {
        let result = selectAll("<selection>aa<caret></selection>aaa")
        #expect(result == EditorMarkup.normalized("<selection>aa<caret></selection><selection>aa<caret></selection>a"))
    }

    @Test
    func theLastOccurrenceBecomesPrimary() {
        let parsed = EditorMarkup("<selection>foo<caret></selection> foo")
        let result = OccurrenceSelection.selectAll(in: parsed.text as NSString, selections: parsed.selections, primary: nil)
        #expect(result?.primary == NSRange(location: 4, length: 3))
    }

    @Test
    func replacesAllOtherCarets() {
        let result = selectAll("<caret>x foo <selection>foo<caret></selection> y", primary: NSRange(location: 6, length: 3))
        #expect(result == EditorMarkup.normalized("x <selection>foo<caret></selection> <selection>foo<caret></selection> y"))
    }
}

nonisolated struct OccurrenceSelectionUnselectTests {
    private let occurrences = [
        NSRange(location: 0, length: 3), NSRange(location: 8, length: 3), NSRange(location: 19, length: 3),
    ]

    @Test
    func removesThePrimaryAndFallsBackToThePreviousSelection() {
        let last = OccurrenceSelection.unselectLast(selections: occurrences, primary: occurrences[2])
        #expect(last == OccurrenceSelectionResult(selections: [occurrences[0], occurrences[1]], primary: occurrences[1]))
        let middle = OccurrenceSelection.unselectLast(selections: occurrences, primary: occurrences[1])
        #expect(middle == OccurrenceSelectionResult(selections: [occurrences[0], occurrences[2]], primary: occurrences[0]))
        let first = OccurrenceSelection.unselectLast(selections: occurrences, primary: occurrences[0])
        #expect(first == OccurrenceSelectionResult(selections: [occurrences[1], occurrences[2]], primary: occurrences[1]))
    }

    @Test
    func withoutAPrimaryTheLastSelectionIsRemoved() {
        let result = OccurrenceSelection.unselectLast(selections: occurrences, primary: nil)
        #expect(result == OccurrenceSelectionResult(selections: [occurrences[0], occurrences[1]], primary: occurrences[1]))
    }

    @Test
    func aSingleSelectionCollapsesToACaretAtItsEnd() {
        let result = OccurrenceSelection.unselectLast(selections: [NSRange(location: 4, length: 3)], primary: nil)
        #expect(result == OccurrenceSelectionResult(selections: [NSRange(location: 7, length: 0)], primary: NSRange(location: 7, length: 0)))
    }

    @Test
    func aSingleCaretHasNothingToUnselect() {
        #expect(OccurrenceSelection.unselectLast(selections: [NSRange(location: 4, length: 0)], primary: nil) == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct OccurrenceSelectionHostedTests {
    private func run(markup: String, _ steps: (EditorCommandHarness) -> Void) async throws -> String {
        var rendered = ""
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: markup)
            defer { harness.close() }
            steps(harness)
            rendered = harness.rendered
        }
        return rendered
    }

    @Test
    func selectNextThreeTimesThenUnselect() async throws {
        let rendered = try await run(markup: "f<caret>oo bar foo foobar foo") { harness in
            harness.actions.selectNextOccurrence()
            harness.actions.selectNextOccurrence()
            harness.actions.selectNextOccurrence()
            harness.actions.unselectLastOccurrence()
        }
        #expect(rendered == EditorMarkup.normalized("<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar foo"))
    }

    @Test
    func selectNextSelectsTheWordUnderTheCaret() async throws {
        let rendered = try await run(markup: "foo b<caret>ar foo") { $0.actions.selectNextOccurrence() }
        #expect(rendered == EditorMarkup.normalized("foo <selection>bar<caret></selection> foo"))
    }

    @Test
    func selectNextWrapsAround() async throws {
        let rendered = try await run(markup: "foo bar <selection>foo<caret></selection>") { $0.actions.selectNextOccurrence() }
        #expect(rendered == EditorMarkup.normalized("<selection>foo<caret></selection> bar <selection>foo<caret></selection>"))
    }

    @Test
    func selectAllSelectsEveryWholeWordOccurrence() async throws {
        let rendered = try await run(markup: "f<caret>oo bar foo foobar foo") { $0.actions.selectAllOccurrences() }
        #expect(rendered == EditorMarkup.normalized(
            "<selection>foo<caret></selection> bar <selection>foo<caret></selection> foobar <selection>foo<caret></selection>"
        ))
    }

    @Test
    func unselectCollapsesASingleSelection() async throws {
        let rendered = try await run(markup: "foo b<caret>ar foo") { harness in
            harness.actions.selectNextOccurrence()
            harness.actions.unselectLastOccurrence()
        }
        #expect(rendered == EditorMarkup.normalized("foo bar<caret> foo"))
    }
}
