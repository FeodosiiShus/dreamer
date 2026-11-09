import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct SearchStateFindCoverageTests {
    private actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
        }
    }

    private struct MaskFailure: Error {}

    private func openWorkspace(
        _ directory: URL,
        files: [String: String]
    ) throws -> (WorkspaceDocument, WorkspaceDocument.SearchState) {
        for (name, text) in files {
            try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let state = try #require(workspace.searchState)
        return (workspace, state)
    }

    @Test
    func regexPatternFollowsTheMatchingMode() throws {
        try withTempDir { dir in
            let (workspace, state) = try openWorkspace(dir, files: [:])
            defer { workspace.close() }

            state.selectedMode = [.Find, .Text, .Containing]
            #expect(state.getRegexPattern(" a.b ") == "a\\.b")
            state.selectedMode = [.Find, .Text, .StartingWith]
            #expect(state.getRegexPattern("a.b") == "\\ba\\.b")
            state.selectedMode = [.Find, .Text, .EndingWith]
            #expect(state.getRegexPattern("a.b") == "a\\.b\\b")
            state.selectedMode = [.Find, .Text, .MatchingWord]
            #expect(state.getRegexPattern("a.b") == "\\ba\\.b\\b")
            state.selectedMode = [.Find, .RegularExpression]
            #expect(state.getRegexPattern("a.b") == "a.b")
        }
    }

    @Test
    func regexPatternFallsBackToTheEscapedQueryWithoutAMatchingMode() throws {
        try withTempDir { dir in
            let (workspace, state) = try openWorkspace(dir, files: [:])
            defer { workspace.close() }

            state.selectedMode = [.Find]
            #expect(state.getRegexPattern("a.b") == "a\\.b")
            state.selectedMode = [.Find, .Text, .Text]
            #expect(state.getRegexPattern("a.b") == "a\\.b")
        }
    }

    @Test
    func anInvalidFileMaskFailsThePlan() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try openWorkspace(dir, files: ["a.txt": "needle\n"])
            defer { workspace.close() }

            do {
                _ = try await state.makeFindPlan(query: "needle", makeMask: { _ in throw MaskFailure() })
                Issue.record("the plan was created despite the invalid file mask")
            } catch {
                #expect(error as? FindFailure == .invalidFileMask)
            }
        }
    }

    @Test
    func evaluationOverridesReplaceTheDiskEvaluation() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try openWorkspace(
                dir,
                files: ["kept.txt": "needle\n", "hidden.txt": "needle\n"]
            )
            defer { workspace.close() }
            state.fileEvaluationOverride = { @Sendable url in
                url.lastPathComponent == "hidden.txt" ? FileEvaluation.empty : nil
            }

            await state.search("needle")

            #expect(state.searchResult.map(\.file.name) == ["kept.txt"])
            #expect(state.findNavigatorStatus == .found)
        }
    }

    @Test
    func moreFilesThanTheConcurrencyWidthAreAllEvaluated() async throws {
        try await withTempDir { dir in
            let count = max(2, ProcessInfo.processInfo.activeProcessorCount) + 5
            var files: [String: String] = [:]
            for number in 0..<count {
                files["file\(number).txt"] = "needle \(number)\n"
            }
            let (workspace, state) = try openWorkspace(dir, files: files)
            defer { workspace.close() }

            await state.search("needle")

            #expect(state.searchResultsFileCount == count)
            #expect(state.searchResultsCount == count)
            #expect(state.findNavigatorStatus == .found)
        }
    }

    @Test
    func hitsArrivingInsideTheFlushIntervalAreSharedByTheScheduledFlush() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try openWorkspace(
                dir,
                files: ["a.txt": "needle a\n", "b.txt": "needle b\n", "c.txt": "needle c\n"]
            )
            defer { workspace.close() }
            let gate = Gate()
            defer { Task { await gate.open() } }
            state.flushInterval = .seconds(2)
            state.fileEvaluationOverride = { @Sendable url in
                if url.lastPathComponent == "c.txt" {
                    await gate.wait()
                }
                return nil
            }

            let search = Task { await state.search("needle") }
            try await eventually(timeout: .seconds(30)) { state.searchResult.count == 2 }
            #expect(state.findNavigatorStatus == .searching)
            #expect(state.searchResultsCount == 2)

            await gate.open()
            await search.value

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResult.map(\.file.name) == ["a.txt", "b.txt", "c.txt"])
        }
    }
}
