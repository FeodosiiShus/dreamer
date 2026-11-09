import AppKit
import Foundation
import Testing
@testable import Dreamder

extension MergeAutomationTests {
    @Test
    func acceptLeftWritesTheLeftSideAndClosesTheWindow() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("acceptLeft")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.mainSide)
            #expect(try await session.fixture.isFullyStaged(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func acceptRightWritesTheRightSideAndClosesTheWindow() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("acceptRight")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.featureSide)
            #expect(try await session.fixture.unmergedPaths() == [Self.notesPath])
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func acceptLeftAfterEditsNeedsConfirmation() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("acceptLeft")

            #expect(MergeToolConfirmation.automationAnswer == nil)
            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            #expect(MergeToolPresenter.revisionsWindow != nil)
            #expect(model.isResultEdited)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("acceptLeft")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.mainSide)
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func applyWritesTheResolvedResultAndClosesTheWindow() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            await MergeAutomation.perform("resolve:\(blockID):left")

            await MergeAutomation.perform("apply")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == Self.resolvedLeft)
            #expect(session.fixture.hasConflictMarkers(Self.configPath) == false)
            #expect(try await session.fixture.isFullyStaged(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func applyWithUnresolvedConflictsAsksBeforeSaving() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("apply")

            #expect(MergeToolConfirmation.automationAnswer == nil)
            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            #expect(MergeToolPresenter.revisionsWindow != nil)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("apply")

            #expect(try trimmed(session.fixture.read(Self.configPath)) == trimmed(Self.unresolvedResult))
            #expect(try await session.fixture.unmergedPaths() == [Self.notesPath])
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func applyWritesTheTextTypedByEditResult() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)
            await MergeAutomation.perform("editResult:hand\\nwritten: text")
            await MergeAutomation.perform("confirm:yes")

            await MergeAutomation.perform("apply")

            #expect(try session.fixture.read(Self.configPath) == "hand\nwritten: text")
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func cancelClosesAnUneditedWindowWithoutTouchingTheFile() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("cancel")

            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func cancelAfterEditsKeepsTheWindowUnlessDiscardIsConfirmed() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("cancel")

            #expect(MergeToolPresenter.revisionsWindow != nil)
            #expect(model.isResultEdited)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("cancel")

            #expect(session.fixture.hasConflictMarkers(Self.configPath))
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func closeRevisionsClosesACleanWindow() async throws {
        try await withSession { session in
            _ = try await openRevisions(session)

            await MergeAutomation.perform("closeRevisions")

            try await eventually { MergeToolPresenter.revisionsWindow == nil }
            #expect(MergeToolPresenter.revisionsModel == nil)
        }
    }

    @Test
    func closeRevisionsAfterEditsAsksForConfirmationFirst() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            await MergeAutomation.perform("editResult:draft")

            await MergeAutomation.perform("confirm:no")
            await MergeAutomation.perform("closeRevisions")
            try await eventually { MergeToolConfirmation.automationAnswer == nil }

            #expect(MergeToolPresenter.revisionsWindow != nil)
            #expect(model.isResultEdited)

            await MergeAutomation.perform("confirm:yes")
            await MergeAutomation.perform("closeRevisions")
            try await eventually { MergeToolPresenter.revisionsWindow == nil }
        }
    }

    @Test
    func closeConflictsClosesTheConflictsDialog() async throws {
        try await withSession { session in
            _ = try await openConflicts(session)
            #expect(MergeToolPresenter.conflictsWindow != nil)

            await MergeAutomation.perform("closeConflicts")

            try await eventually { MergeToolPresenter.conflictsWindow == nil }
            #expect(MergeToolPresenter.conflictsModel == nil)
        }
    }
}
