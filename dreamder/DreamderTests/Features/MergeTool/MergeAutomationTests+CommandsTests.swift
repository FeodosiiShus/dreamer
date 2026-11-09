import AppKit
import Foundation
import Testing
@testable import Dreamder

extension MergeAutomationTests {
    @Test
    func acceptYoursKeepsOursForTheSelectedFile() async throws {
        try await withSession { session in
            let model = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.configPath)")

            await MergeAutomation.perform("acceptYours")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.mainSide)
            #expect(try await session.fixture.isFullyStaged(Self.configPath))
            #expect(try await session.fixture.unmergedPaths() == [Self.notesPath])
            try await eventually { model.entries.map(\.path) == [Self.notesPath] }
            #expect(model.primaryPath == Self.notesPath)
            #expect(model.errorMessage == nil)
        }
    }

    @Test
    func acceptTheirsTakesTheOtherSideForEverySelectedFile() async throws {
        try await withSession { session in
            let model = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.configPath)")
            await MergeAutomation.perform("selectAdd:\(Self.notesPath)")

            await MergeAutomation.perform("acceptTheirs")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.featureSide)
            #expect(try trimmed(session.fixture.read(Self.notesPath)) == "one\nnotes-feature\nthree")
            #expect(try await session.fixture.unmergedPaths().isEmpty)
            try await eventually { model.entries.isEmpty }
            #expect(model.summary == "All conflicts have been resolved")
        }
    }

    @Test
    func mergeSelectedOpensTheRevisionsWindowForThePrimaryFile() async throws {
        try await withSession { session in
            _ = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.notesPath)")

            await MergeAutomation.perform("mergeSelected")

            #expect(MergeToolPresenter.lastRevisionsPath == Self.notesPath)
            let model = try #require(MergeToolPresenter.revisionsModel)
            #expect(model.path == Self.notesPath)
            try await eventually { model.isLoading == false }
            #expect(model.merge?.conflictCount == 1)
        }
    }

    @Test
    func mergeFileOpensTheRevisionsWindowForTheGivenPath() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)

            #expect(model.path == Self.configPath)
            #expect(model.isConflictValid)
            #expect(model.leftTitle == "Your version, branch main")
            #expect(model.rightTitle == "Theirs, branch feature")
            #expect(model.merge?.conflictCount == 1)
            #expect(model.resultText == Self.unresolvedResult)
        }
    }

    @Test
    func mergeFileWithoutPathOpensNothing() async throws {
        try await withSession { session in
            await MergeAutomation.perform("target:\(session.path)")
            await MergeAutomation.perform("mergeFile:")

            #expect(MergeToolPresenter.revisionsModel == nil)
            #expect(MergeToolPresenter.revisionsWindow == nil)
        }
    }

    @Test
    func mergeFileForAnAlreadyResolvedPathReportsAnInvalidConflict() async throws {
        try await withSession { session in
            let model = try await openRevisions(session, path: "not-in-conflict.txt")

            #expect(model.isConflictValid == false)
            #expect(model.errorMessage == "Conflict is not valid and no longer can be resolved.")
            #expect(model.merge == nil)
        }
    }

    @Test(arguments: [
        ("left", "epsilon\nzeta-main\neta"),
        ("right", "epsilon\nzeta-feature\neta"),
        ("ignored", "epsilon\nzeta\neta")
    ])
    func resolveCommandAppliesTheChosenSideToTheBlock(resolution: String, expectedFragment: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)

            await MergeAutomation.perform("resolve:\(blockID):\(resolution)")

            #expect(model.resultText.contains(expectedFragment))
            #expect(model.merge?.conflictCount == 0)
            #expect(model.isResultEdited == false)
        }
    }

    @Test(arguments: ["resolve:{id}:sideways", "resolve:{id}", "resolve:abc:left", "resolve::left"])
    func resolveCommandIgnoresMalformedArguments(template: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)

            await MergeAutomation.perform(template.replacingOccurrences(of: "{id}", with: String(blockID)))

            #expect(model.merge?.conflictCount == 1)
            #expect(model.resultText == Self.unresolvedResult)
        }
    }

    @Test(arguments: [
        ("left", "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nlambda\n"),
        ("right", "alpha\nbeta\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n"),
        ("all", "alpha\nbeta-main\ngamma\ndelta\nepsilon\nzeta\neta\ntheta\niota\nkappa\nfeature-added\nlambda\n")
    ])
    func applyNonConflictingCommandAppliesOnlyTheRequestedSide(mode: String, expected: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)

            await MergeAutomation.perform("applyNonConflicting:\(mode)")

            #expect(TextDiff.lines(in: model.resultText) == TextDiff.lines(in: expected))
        }
    }

    @Test
    func applyNonConflictingCommandIgnoresUnknownModes() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let before = model.resultText
            let revision = model.contentRevision

            await MergeAutomation.perform("applyNonConflicting:sideways")
            await MergeAutomation.perform("applyNonConflicting:")

            #expect(model.resultText == before)
            #expect(model.contentRevision == revision)
        }
    }

    @Test(arguments: [
        ("editResult:hand\\nwritten", "hand\nwritten"),
        ("editResult:let value: Int = 1", "let value: Int = 1"),
        ("editResult:a:b:c", "a:b:c"),
        ("editResult:a\\\\nb", "a\\nb"),
        ("editResult:tab\\r\\nend", "tab\nend"),
        ("editResult:dangling\\", "dangling\\"),
        ("editResult:odd\\tescape", "odd\\tescape"),
        ("editResult:", "")
    ])
    func editResultCommandUnescapesTheTypedText(command: String, expected: String) async throws {
        try await withSession { session in
            let model = try await openRevisions(session)

            await MergeAutomation.perform(command)

            #expect(model.resultText == expected)
            #expect(model.isResultEdited)
        }
    }
}
