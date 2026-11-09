import Foundation
import Testing
@testable import Dreamder

@Suite
struct FindReplaceEngineTests {
    private func job(
        find: String,
        replace: String,
        ranges: [NSRange],
        configure: (inout FindModel) -> Void = { _ in }
    ) throws -> FindReplaceJob {
        var model = FindModel()
        model.stringToFind = find
        model.stringToReplace = replace
        configure(&model)
        let regex = try #require(model.compileMatcher())
        return FindReplaceJob(url: URL(fileURLWithPath: "/tmp/engine.txt"), ranges: ranges, model: model, regex: regex)
    }

    @Test
    func onlyTheSelectedRangesAreEdited() throws {
        let job = try job(find: "foo", replace: "bar", ranges: [NSRange(location: 4, length: 3)])
        let result = FindReplaceEngine.edits(for: job, in: "foo foo foo")
        #expect(result.edits == [FindReplaceEdit(range: NSRange(location: 4, length: 3), replacement: "bar")])
        #expect(result.missing == 0)
    }

    @Test
    func rangesThatNoLongerMatchAreCountedAsMissing() throws {
        let job = try job(
            find: "foo",
            replace: "bar",
            ranges: [NSRange(location: 4, length: 3), NSRange(location: 20, length: 3), NSRange(location: 1, length: 3)]
        )
        let result = FindReplaceEngine.edits(for: job, in: "foo foo foo")
        #expect(result.edits.map(\.range) == [NSRange(location: 4, length: 3)])
        #expect(result.missing == 2)
    }

    @Test
    func noSelectedRangesProduceNoEdits() throws {
        let job = try job(find: "foo", replace: "bar", ranges: [])
        let result = FindReplaceEngine.edits(for: job, in: "foo foo")
        #expect(result.edits.isEmpty)
        #expect(result.missing == 0)
    }

    @Test
    func wholeWordModelRejectsEmbeddedMatches() throws {
        let job = try job(
            find: "foo",
            replace: "bar",
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)]
        ) { $0.isWholeWordsOnly = true }
        let result = FindReplaceEngine.edits(for: job, in: "foo foobar")
        #expect(result.edits.map(\.range) == [NSRange(location: 0, length: 3)])
        #expect(result.missing == 1)
    }

    @Test
    func regexGroupsExpandPerMatch() throws {
        let job = try job(
            find: "(\\w+)=(\\d+)",
            replace: "$2=$1",
            ranges: [NSRange(location: 0, length: 6), NSRange(location: 7, length: 6)]
        ) { $0.isRegularExpressions = true }
        let result = FindReplaceEngine.edits(for: job, in: "key=42 name=7")
        #expect(result.edits.map(\.replacement) == ["42=key", "7=name"])
        #expect(result.missing == 0)
    }

    @Test
    func caseConversionTemplateApplies() throws {
        let job = try job(
            find: "(\\w+)=",
            replace: "\\U$1\\E:",
            ranges: [NSRange(location: 0, length: 4)]
        ) { $0.isRegularExpressions = true }
        let result = FindReplaceEngine.edits(for: job, in: "key=1")
        #expect(result.edits.map(\.replacement) == ["KEY:"])
    }

    @Test
    func preserveCaseFollowsEachMatch() throws {
        let job = try job(
            find: "foo",
            replace: "bar",
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3), NSRange(location: 8, length: 3)]
        ) { $0.isPreserveCase = true }
        let result = FindReplaceEngine.edits(for: job, in: "Foo FOO foo")
        #expect(result.edits.map(\.replacement) == ["Bar", "BAR", "bar"])
    }

    @Test
    func templateErrorSkipsTheEditAndCountsItAsMissing() throws {
        let job = try job(
            find: "(a)",
            replace: "$5",
            ranges: [NSRange(location: 0, length: 1), NSRange(location: 1, length: 1)]
        ) { $0.isRegularExpressions = true }
        let result = FindReplaceEngine.edits(for: job, in: "aa")
        #expect(result.edits.isEmpty)
        #expect(result.missing == 2)
    }

    @Test
    func applyRewritesEveryEditWithLengthDeltas() {
        let edits = [
            FindReplaceEdit(range: NSRange(location: 0, length: 3), replacement: "quux"),
            FindReplaceEdit(range: NSRange(location: 4, length: 3), replacement: "x"),
            FindReplaceEdit(range: NSRange(location: 8, length: 3), replacement: "")
        ]
        #expect(FindReplaceEngine.apply(edits, to: "foo foo foo!") == "quux x !")
    }

    @Test
    func applyWithoutEditsReturnsTheText() {
        #expect(FindReplaceEngine.apply([], to: "unchanged 😀") == "unchanged 😀")
    }

    @Test
    func applyHandlesAdjacentEditsAndAstralText() {
        let edits = [
            FindReplaceEdit(range: NSRange(location: 0, length: 2), replacement: "a"),
            FindReplaceEdit(range: NSRange(location: 2, length: 2), replacement: "b")
        ]
        #expect(FindReplaceEngine.apply(edits, to: "😀😀tail") == "abtail")
    }

    @Test
    func deltaSumsOnlyEditsEndingBeforeTheLocation() {
        let applied = [
            FindReplaceEdit(range: NSRange(location: 0, length: 3), replacement: "quux"),
            FindReplaceEdit(range: NSRange(location: 8, length: 3), replacement: "x")
        ]
        #expect(FindReplaceEngine.delta(before: 0, applied: applied) == 0)
        #expect(FindReplaceEngine.delta(before: 3, applied: applied) == 1)
        #expect(FindReplaceEngine.delta(before: 5, applied: applied) == 1)
        #expect(FindReplaceEngine.delta(before: 10, applied: applied) == 1)
        #expect(FindReplaceEngine.delta(before: 11, applied: applied) == -1)
        #expect(FindReplaceEngine.delta(before: 40, applied: []) == 0)
    }

    @Test
    func deltaMeasuresReplacementsInUTF16Units() {
        let applied = [FindReplaceEdit(range: NSRange(location: 0, length: 1), replacement: "😀")]
        #expect(FindReplaceEngine.delta(before: 1, applied: applied) == 1)
    }

    @Test
    func outcomeCleanlinessRequiresNoMissingRanges() {
        let clean = FindReplaceOutcome.replaced(FindReplaceResult(text: "x", applied: [], missing: 0))
        let partial = FindReplaceOutcome.replaced(FindReplaceResult(text: "x", applied: [], missing: 1))
        #expect(clean.isClean)
        #expect(!partial.isClean)
        #expect(!FindReplaceOutcome.stale.isClean)
        #expect(!FindReplaceOutcome.failed("boom").isClean)
    }
}
