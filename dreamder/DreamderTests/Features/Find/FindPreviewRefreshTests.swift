import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindPreviewRefreshTests {
    private func firstReplacement(_ state: FindStateSupport.State) -> String? {
        FindStateSupport.matches("a.txt", in: state).first?.usage?.replacement
    }

    @Test
    func changingTheReplacementTextRefreshesThePreviews() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle one\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            #expect(firstReplacement(state) == "thread")

            state.replaceText = "string"

            try await eventually { firstReplacement(state) == "string" && state.findNavigatorStatus == .found }
            #expect(state.findNavigatorStatus == .found)
            #expect(FindStateSupport.matches("a.txt", in: state).first?.replacementPreviewLine == "string one")
        }
    }

    @Test
    func togglingPreserveCaseRefreshesThePreviews() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "Needle one\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            #expect(firstReplacement(state) == "thread")

            state.findModel.isPreserveCase = true

            try await eventually { firstReplacement(state) == "Thread" && state.findNavigatorStatus == .found }
            #expect(state.findNavigatorStatus == .found)
        }
    }

    @Test
    func switchingFromFindToReplaceModeAddsPreviews() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle one\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            state.replaceText = "thread"
            try await FindStateSupport.settle()
            await state.search("needle")
            #expect(state.findNavigatorStatus == .found)
            #expect(firstReplacement(state) == nil)
            try await FindStateSupport.settle()

            state.setReplaceMode(true)

            try await eventually { firstReplacement(state) == "thread" && state.findNavigatorStatus == .found }
            #expect(state.findNavigatorStatus == .found)
        }
    }

    @Test
    func rapidEditsEndWithTheLastReplacement() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle one\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }

            state.replaceText = "x1"
            try await Task.sleep(for: .milliseconds(40))
            state.replaceText = "x2"

            try await eventually { firstReplacement(state) == "x2" }
        }
    }

    @Test
    func schedulingAgainCancelsThePreviousRefreshAndSearchesOnce() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle one\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            let counter = FindCallCounter()
            state.fileEvaluationOverride = { @Sendable url in
                if url.lastPathComponent == "a.txt" {
                    await counter.record()
                }
                return nil
            }

            state.schedulePreviewRefresh()
            let first = try #require(state.previewRefreshTask)
            state.schedulePreviewRefresh()
            let second = try #require(state.previewRefreshTask)

            #expect(first.isCancelled)
            #expect(!second.isCancelled)
            try await eventually { await counter.value == 1 }
            try await eventually { state.findNavigatorStatus == .found }
            try await Task.sleep(for: FindStateSupport.State.previewRefreshDelay + .milliseconds(300))
            #expect(await counter.value == 1)
        }
    }

    @Test
    func noRefreshIsScheduledWithoutAFoundReplaceSearch() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle one\n", "a.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            state.setReplaceMode(true)
            state.replaceText = "thread"
            try await FindStateSupport.settle()

            state.schedulePreviewRefresh()
            #expect(state.findNavigatorStatus == .none)
            #expect(state.previewRefreshTask == nil)

            await state.search("")
            #expect(state.findNavigatorStatus == .found)
            state.schedulePreviewRefresh()
            #expect(state.previewRefreshTask == nil)

            state.setReplaceMode(false)
            try await FindStateSupport.settle()
            await state.search("needle")
            state.schedulePreviewRefresh()
            #expect(state.previewRefreshTask == nil)
        }
    }

    @Test
    func rescheduleAfterAnIneligibleStateCancelsTheEarlierRefresh() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle one\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }

            state.schedulePreviewRefresh()
            let pending = try #require(state.previewRefreshTask)
            state.clearResults()
            state.schedulePreviewRefresh()

            #expect(pending.isCancelled)
            #expect(state.previewRefreshTask == nil)
        }
    }

    @Test
    func replaceModeKeepsOrResetsTheSecondMode() async throws {
        let cases: [(from: [SearchModeModel], replace: Bool, expected: [SearchModeModel])] = [
            ([.Find, .References], true, [.Replace, .Text, .Containing]),
            ([.Find, .RegularExpression], true, [.Replace, .RegularExpression]),
            ([.Find, .Text, .MatchingWord], true, [.Replace, .Text, .MatchingWord]),
            ([.Find, .Text, .Containing], true, [.Replace, .Text, .Containing]),
            ([.Replace, .RegularExpression], false, [.Find, .RegularExpression]),
            ([.Replace, .Text, .StartingWith], false, [.Find, .Text, .StartingWith]),
            ([.Find, .Definitions], false, [.Find, .Definitions]),
            ([.Find, .CallHierarchy], true, [.Replace, .Text, .Containing])
        ]
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            for item in cases {
                state.selectedMode = item.from
                state.setReplaceMode(item.replace)
                #expect(state.selectedMode == item.expected, "from \(item.from.map(\.title)) replace \(item.replace)")
            }
        }
    }

    @Test
    func replaceAllAfterEditingTheReplacementIsNotOverwrittenByALateRefresh() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle one\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            state.replaceText = "string"

            await state.replaceAll()

            #expect(state.previewRefreshTask == nil)
            #expect(state.findNavigatorStatus == .replaced(updatedFiles: 1))
            #expect(try FindStateSupport.read("a.txt", in: dir) == "string one\n")
            #expect(state.searchResult.isEmpty)
        }
    }

    @Test
    func replacingAMatchCancelsThePendingRefresh() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.replaceSession(
                files: ["a.txt": "needle needle\n"],
                query: "needle",
                replacement: "thread",
                in: dir
            )
            defer { workspace.close() }
            state.replaceText = "string"
            try await eventually { state.previewRefreshTask != nil }
            state.schedulePreviewRefresh()
            #expect(state.previewRefreshTask != nil)

            await state.replace(try FindStateSupport.matches("a.txt", in: state).required(at: 0))

            #expect(state.previewRefreshTask == nil)
        }
    }

    @Test
    func findFailuresHaveTheirMessages() {
        #expect(FindFailure.invalidFileMask.message == "Invalid file mask.")
        #expect(FindFailure.noProject.message == "No project is open.")
        #expect(FindFailure.invalidRegularExpression.message == "Invalid regular expression.")
        #expect(FindFailure.invalidReplacement("x").message == "Invalid replacement string: x")
    }
}
