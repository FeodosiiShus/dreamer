import Foundation
import Testing
@testable import Dreamder

private nonisolated enum CloneCaretFixtures {
    static let directory = "platform/platform-tests/testData/editor/multiCaret"

    static func markup(_ name: String) throws -> String {
        try IntelliJTestData.text("\(directory)/\(name).txt").trimmingCharacters(in: .newlines)
    }
}

private nonisolated func clonedMarkup(_ markup: String, above: Bool) -> String? {
    let parsed = EditorMarkup(markup)
    guard let selections = CloneCaret.perform(in: parsed.text as NSString, selections: parsed.selections, above: above) else {
        return nil
    }
    return EditorMarkup(text: parsed.text, selections: selections).rendered
}

nonisolated struct CloneCaretTests {
    @Test(arguments: ["EditorCloneCaretAbove", "EditorCloneCaretBelow"])
    func intelliJFixturesMatch(name: String) throws {
        let before = try CloneCaretFixtures.markup("\(name)-before")
        let after = try CloneCaretFixtures.markup("\(name)-after")
        let cloned = clonedMarkup(before, above: name.hasSuffix("Above"))
        #expect(cloned == EditorMarkup.normalized(after))
    }

    @Test
    func clonesCaretsBelowAtTheSameColumn() {
        let cloned = clonedMarkup("line\n<caret>li<caret>ne\nline", above: false)
        #expect(cloned == EditorMarkup.normalized("line\n<caret>li<caret>ne\n<caret>li<caret>ne"))
    }

    @Test
    func clampsTheColumnToTheShorterLine() {
        let cloned = clonedMarkup("long line<caret>\nline\nlong line\nvery long line", above: false)
        #expect(cloned == EditorMarkup.normalized("long line<caret>\nline<caret>\nlong line\nvery long line"))
    }

    @Test
    func clonesAboveFromTheCaretColumnNotTheLineEnd() {
        let cloned = clonedMarkup("long long line\nshort line<caret>", above: true)
        #expect(cloned == EditorMarkup.normalized("long long <caret>line\nshort line<caret>"))
    }

    @Test
    func clonesASelectionWithTheSameColumnSpan() {
        let cloned = clonedMarkup("<selection>one<caret></selection> two \nthree four ", above: false)
        #expect(cloned == EditorMarkup.normalized("<selection>one<caret></selection> two \n<selection>thr<caret></selection>ee four "))
    }

    @Test
    func skipsLinesWhereTheSelectionCollapses() {
        let cloned = clonedMarkup("long <selection>line<caret></selection>\nline\nlong line", above: false)
        #expect(cloned == EditorMarkup.normalized("long <selection>line<caret></selection>\nline\nlong <selection>line<caret></selection>"))
    }

    @Test
    func truncatesTheSelectionStartAtTheDocumentStart() {
        let cloned = clonedMarkup("abcdef\n<selection>xy<caret></selection>", above: true)
        #expect(cloned == EditorMarkup.normalized("<selection>ab<caret></selection>cdef\n<selection>xy<caret></selection>"))
        let multiline = clonedMarkup("abcd<selection>ef\nxy<caret></selection>", above: true)
        #expect(multiline == EditorMarkup.normalized("<selection>ab<caret></selection>cd<selection>ef\nxy<caret></selection>"))
    }

    @Test
    func returnsNilAtTheDocumentEdges() {
        #expect(clonedMarkup("<caret>one\ntwo", above: true) == nil)
        #expect(clonedMarkup("one\n<caret>two", above: false) == nil)
    }

    @Test
    func skipsClonesThatCoincideWithExistingCarets() {
        #expect(clonedMarkup("a<caret>b\na<caret>b", above: false) == nil)
        let partial = clonedMarkup("a<caret>b\na<caret>b\nab", above: false)
        #expect(partial == EditorMarkup.normalized("a<caret>b\na<caret>b\na<caret>b"))
    }

    @Test
    func skipsSelectionClonesOverlappingExistingSelections() {
        let cloned = clonedMarkup("<selection>ab<caret></selection>cd\nx<selection>ab<caret></selection>x", above: false)
        #expect(cloned == nil)
    }
}

@MainActor
@Suite(.uiGate)
struct CloneCaretHostedTests {
    @Test(arguments: ["EditorCloneCaretAbove", "EditorCloneCaretBelow"])
    func intelliJFixturesMatch(name: String) async throws {
        let before = try CloneCaretFixtures.markup("\(name)-before")
        let after = try CloneCaretFixtures.markup("\(name)-after")
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: before)
            defer { harness.close() }
            harness.actions.cloneCaret(above: name.hasSuffix("Above"))
            #expect(harness.rendered == EditorMarkup.normalized(after))
        }
    }

    @Test
    func leavesTheDocumentAlone() async throws {
        try await withTempDir { directory in
            let harness = try await EditorCommandHarness.open(in: directory, markup: "<caret>one\ntwo")
            defer { harness.close() }
            harness.actions.cloneCaret(above: true)
            #expect(harness.rendered == EditorMarkup.normalized("<caret>one\ntwo"))
        }
    }
}
