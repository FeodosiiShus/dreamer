import Foundation
import Testing
@testable import Dreamder

extension ReplaceInFilesTests {
    @Test
    func movedContentIsStaleToo() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            try FindStateSupport.write(" needle\n", "a.txt", in: dir)

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == " needle\n")
            #expect(state.findNavigatorStatus == .failed(errorMessage: Self.allFailedOne))
        }
    }

    @Test
    func aPartiallyMissingFileIsUpdatedAndCountsAsAnError() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\nneedle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            try FindStateSupport.write("needle\nxxxxxx\n", "a.txt", in: dir)

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread\nxxxxxx\n")
            #expect(state.searchResult.isEmpty)
            #expect(state.findNavigatorStatus == .failed(errorMessage: Self.oneUpdatedOneFailed))
            #expect(state.replaceNotice == Self.oneUpdatedOneFailed)
        }
    }

    @Test
    func cleanAndStaleFilesReportTheMixedMessageWhileSkippedMatchesRemain() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n", "b.txt": "needle\n", "c.txt": "needle needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            state.toggleSkip(try #require(FindStateSupport.result("c.txt", in: state)))
            try FindStateSupport.write("nothing\n", "a.txt", in: dir)

            await state.replaceAll()

            #expect(try FindStateSupport.read("b.txt", in: dir) == "thread\n")
            #expect(try FindStateSupport.read("c.txt", in: dir) == "needle needle\n")
            #expect(state.searchResult.map(\.file.name) == ["c.txt"])
            #expect(state.findNavigatorStatus == .found)
            #expect(state.replaceNotice == Self.oneUpdatedOneFailed)
        }
    }

    @Test
    func onlyStaleFilesWithSkippedMatchesRemainingReportTheAllFailedMessage() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n", "c.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            state.toggleSkip(try #require(FindStateSupport.result("c.txt", in: state)))
            try FindStateSupport.write("nothing\n", "a.txt", in: dir)

            await state.replaceAll()

            #expect(state.searchResult.map(\.file.name) == ["c.txt"])
            #expect(state.findNavigatorStatus == .found)
            #expect(state.replaceNotice == Self.allFailedOne)
        }
    }

    @Test
    func unreadableAndReadOnlyFilesFailAndKeepTheirMatches() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n", "b.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            try setPermissions(0o444, "a.txt", in: dir)
            try setPermissions(0o000, "b.txt", in: dir)
            defer {
                try? setPermissions(0o644, "a.txt", in: dir)
                try? setPermissions(0o644, "b.txt", in: dir)
            }

            await state.replaceAll()

            try setPermissions(0o644, "a.txt", in: dir)
            try setPermissions(0o644, "b.txt", in: dir)
            #expect(try FindStateSupport.read("a.txt", in: dir) == "needle\n")
            #expect(try FindStateSupport.read("b.txt", in: dir) == "needle\n")
            #expect(state.searchResult.map(\.file.name) == ["a.txt", "b.txt"])
            #expect(state.searchResultsCount == 2)
            #expect(state.findNavigatorStatus == .found)
            #expect(state.replaceNotice == Self.allFailedTwo)
        }
    }

    @Test
    func replaceAllSearchesFirstWhenNothingWasFound() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            state.setReplaceMode(true)
            state.replaceText = "thread"
            state.searchQuery = "needle"
            #expect(state.findNavigatorStatus == .none)

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread\n")
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 1))
        }
    }

    @Test
    func replaceAllWithoutAQueryDoesNothing() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            state.setReplaceMode(true)
            state.replaceText = "thread"

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "needle\n")
            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResult.isEmpty)
        }
    }

    @Test
    func clearingResultsWhileReplacingDropsTheOutcomeBookkeeping() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }

            let task = Task { await state.replaceAll() }
            await Task.yield()
            state.clearResults()
            await task.value

            #expect(state.findNavigatorStatus == .none)
            #expect(state.searchResult.isEmpty)
            #expect(state.replaceNotice == nil)
        }
    }
}
