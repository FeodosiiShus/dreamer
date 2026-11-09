import Foundation
import Testing
@testable import Dreamder

extension ReplaceInFilesTests {
    @Test
    func replaceInFileOnlyTouchesThatFile() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\n", "b.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }

            await state.replaceInFile(try #require(FindStateSupport.result("a.txt", in: state)))

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread thread\n")
            #expect(try FindStateSupport.read("b.txt", in: dir) == "needle\n")
            #expect(state.searchResult.map(\.file.name) == ["b.txt"])
            #expect(state.findNavigatorStatus == .found)

            await state.replaceInFile(try #require(FindStateSupport.result("b.txt", in: state)))

            #expect(try FindStateSupport.read("b.txt", in: dir) == "thread\n")
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 1))
        }
    }

    @Test
    func replaceSelectedFollowsTheResultSelection() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }

            state.resultSelection = nil
            await state.replaceSelected()
            #expect(try FindStateSupport.read("a.txt", in: dir) == "needle needle\n")
            #expect(state.findNavigatorStatus == .found)

            state.resultSelection = .match(try FindStateSupport.matches("a.txt", in: state).required(at: 1))
            await state.replaceSelected()
            #expect(try FindStateSupport.read("a.txt", in: dir) == "needle thread\n")
            #expect(state.resultSelection == nil)
            #expect(state.searchResultsCount == 1)

            state.resultSelection = .file(try #require(FindStateSupport.result("a.txt", in: state)))
            await state.replaceSelected()
            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread thread\n")
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 1))
        }
    }

    @Test
    func skippingTogglesMatchesAndFilesAndBumpsTheRevision() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\n", "b.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            let fileA = try #require(FindStateSupport.result("a.txt", in: state))
            let fileB = try #require(FindStateSupport.result("b.txt", in: state))
            let first = try fileA.lineMatches.required(at: 0)
            let second = try fileA.lineMatches.required(at: 1)
            let revision = state.skipRevision

            state.toggleSkip(first)
            #expect(first.isSkipped)
            #expect(state.skipRevision == revision + 1)
            state.toggleSkip(first)
            #expect(!first.isSkipped)
            #expect(state.skipRevision == revision + 2)

            state.toggleSkip(fileA)
            #expect(fileA.lineMatches.allSatisfy { $0.isSkipped })
            state.toggleSkip(fileA)
            #expect(fileA.lineMatches.allSatisfy { !$0.isSkipped })

            state.toggleSkip(first)
            state.toggleSkip(fileA)
            #expect(fileA.lineMatches.allSatisfy { $0.isSkipped })
            #expect(second.isSkipped)

            let beforeSelection = state.skipRevision
            state.resultSelection = nil
            state.toggleSkipSelected()
            #expect(state.skipRevision == beforeSelection)

            state.resultSelection = .match(second)
            state.toggleSkipSelected()
            #expect(!second.isSkipped)
            #expect(state.skipRevision == beforeSelection + 1)

            state.resultSelection = .file(fileB)
            state.toggleSkipSelected()
            #expect(fileB.lineMatches.allSatisfy { $0.isSkipped })
            #expect(state.skipRevision == beforeSelection + 2)
        }
    }

    @Test
    func skippedMatchesStayInTheListAndAreReplacedOnlyExplicitly() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\n", "b.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            state.toggleSkip(try FindStateSupport.matches("a.txt", in: state).required(at: 1))

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread needle\n")
            #expect(try FindStateSupport.read("b.txt", in: dir) == "thread\n")
            #expect(state.findNavigatorStatus == .found)
            #expect(state.replaceNotice == nil)
            #expect(state.searchResult.map(\.file.name) == ["a.txt"])
            #expect(state.searchResultsCount == 1)
            let skipped = try #require(FindStateSupport.matches("a.txt", in: state).first)
            #expect(skipped.isSkipped)
            #expect(skipped.usage == usage(7, 6, "thread", from: (1, 8), to: (1, 14)))

            await state.replace(skipped)

            #expect(!skipped.isSkipped)
            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread thread\n")
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 1))
        }
    }

    @Test
    func replaceAllWithEverythingSkippedChangesNothing() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            state.toggleSkip(try #require(FindStateSupport.result("a.txt", in: state)))

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "needle needle\n")
            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResultsCount == 2)
        }
    }

    @Test
    func aMatchOutsideTheResultsIsIgnored() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            let text = "needle"
            let stranger = SearchResultMatchModel(
                rangeWithinFile: text.startIndex..<text.endIndex,
                file: CEWorkspaceFile(url: dir.appending(path: "a.txt")),
                lineContent: text,
                keywordRange: text.startIndex..<text.endIndex
            )

            await state.replace(stranger)

            #expect(try FindStateSupport.read("a.txt", in: dir) == "needle\n")
            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResultsCount == 1)
        }
    }

    @Test
    func theReplacementTextIsReadAtApplyTime() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            state.replaceText = "string"

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "string\n")
        }
    }

    @Test
    func anInvalidTemplateAtApplyTimeSetsTheNoticeAndKeepsEverything() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "a\n"],
                query: "(a)",
                replacement: "$1",
                regex: true,
                in: dir
            )
            defer { workspace.close() }
            #expect(state.replacementError == nil)
            state.replaceText = "$5"

            await state.replaceAll()

            #expect(state.replaceNotice == "Invalid replacement string: No group 5")
            #expect(try FindStateSupport.read("a.txt", in: dir) == "a\n")
            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResultsCount == 1)
        }
    }

    @Test
    func aFileChangedOnDiskIsStaleAndItsMatchesAreDropped() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            try FindStateSupport.write("nothing\n", "a.txt", in: dir)

            await state.replaceAll()

            #expect(try FindStateSupport.read("a.txt", in: dir) == "nothing\n")
            #expect(state.searchResult.isEmpty)
            #expect(state.replaceNotice == Self.allFailedOne)
            #expect(state.findNavigatorStatus == .failed(errorMessage: Self.allFailedOne))
        }
    }

    @Test
    func aStaleFileKeepsItsMatchesWithoutUsage() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            let result = try #require(FindStateSupport.result("a.txt", in: state))
            let text = "needle"
            let usageless = SearchResultMatchModel(
                rangeWithinFile: text.startIndex..<text.endIndex,
                file: result.file,
                lineContent: text,
                keywordRange: text.startIndex..<text.endIndex
            )
            result.lineMatches.append(usageless)
            try FindStateSupport.write("nothing\n", "a.txt", in: dir)

            await state.replaceAll()

            #expect(result.lineMatches.count == 1)
            #expect(result.lineMatches.first === usageless)
            #expect(state.searchResultsCount == 1)
        }
    }

    @Test
    func aRemainingMatchBeyondTheRewrittenTextIsDropped() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            var matches = FindStateSupport.matches("a.txt", in: state)
            let first = try matches.required(at: 0)
            let second = try matches.required(at: 1)
            second.usage = usage(500, 6, "thread", from: (1, 501), to: (1, 507))

            await state.replace(first)

            #expect(try FindStateSupport.read("a.txt", in: dir) == "thread needle\n")
            matches = FindStateSupport.matches("a.txt", in: state)
            #expect(matches.isEmpty)
            #expect(state.searchResult.isEmpty)
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 1))
        }
    }
}
