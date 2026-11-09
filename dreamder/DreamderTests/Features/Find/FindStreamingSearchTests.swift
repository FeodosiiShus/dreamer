import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindStreamingSearchTests {
    @Test
    func resultsArriveBeforeTheSearchCompletes() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle in a\n", "a.txt", in: dir)
            try FindStateSupport.write("needle in b\nneedle again\n", "b.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            let gate = FindGate()
            FindStateSupport.hold("b.txt", with: gate, in: state)

            let task = Task { await state.search("needle") }
            try await eventually { state.searchResult.count == 1 }

            #expect(state.findNavigatorStatus == .searching)
            #expect(state.searchResultsCount == 1)
            #expect(state.searchResultsFileCount == 1)
            #expect(state.searchResult.first?.file.name == "a.txt")

            await gate.open()
            await task.value

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResult.map(\.file.name) == ["a.txt", "b.txt"])
            #expect(state.searchResultsCount == 3)
            #expect(state.searchResultsFileCount == 2)
            #expect(state.tempSearchResults.isEmpty)
        }
    }

    @Test
    func secondHitWithinTheFlushIntervalIsPublishedByTheScheduledFlush() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle a\n", "a.txt", in: dir)
            try FindStateSupport.write("needle b\n", "b.txt", in: dir)
            try FindStateSupport.write("needle c\n", "c.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            let gateB = FindGate()
            let gateC = FindGate()
            state.fileEvaluationOverride = { @Sendable url in
                switch url.lastPathComponent {
                case "b.txt": await gateB.wait()
                case "c.txt": await gateC.wait()
                default: break
                }
                return nil
            }

            let task = Task { await state.search("needle") }
            try await eventually { state.searchResult.count == 1 }
            await gateB.open()
            try await eventually { state.searchResult.count == 2 }

            #expect(state.findNavigatorStatus == .searching)
            #expect(state.searchResultsFileCount == 2)
            #expect(state.searchResultsCount == 2)

            await gateC.open()
            await task.value

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResult.map(\.file.name) == ["a.txt", "b.txt", "c.txt"])
        }
    }

    @Test
    func cancellingTheAwaitingTaskFinalisesTheResultsSoFar() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle in a\n", "a.txt", in: dir)
            try FindStateSupport.write("needle in b\n", "b.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            let gate = FindGate()
            FindStateSupport.hold("b.txt", with: gate, in: state)

            let task = Task { await state.search("needle") }
            try await eventually { state.searchResult.count == 1 }
            task.cancel()
            await task.value

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchResult.map(\.file.name) == ["a.txt"])
            #expect(state.tempSearchResults.isEmpty)

            await gate.open()
        }
    }

    @Test
    func aNewQueryCancelsTheRunningSearch() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle in a\n", "a.txt", in: dir)
            try FindStateSupport.write("needle in b\n", "b.txt", in: dir)
            try FindStateSupport.write("other thing\n", "c.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            let gate = FindGate(holds: 1)
            FindStateSupport.hold("b.txt", with: gate, in: state)

            let first = Task { await state.search("needle") }
            try await eventually { state.searchResult.count == 1 }
            try await eventually { await gate.arrivals == 1 }

            await state.search("other")
            await gate.open()
            await first.value
            try await Task.sleep(for: .milliseconds(150))

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchQuery == "other")
            #expect(state.searchResult.map(\.file.name) == ["c.txt"])
            #expect(state.searchResultsCount == 1)
            #expect(state.searchResultsFileCount == 1)
        }
    }

    @Test
    func clearingResultsCancelsTheRunningSearch() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle in a\n", "a.txt", in: dir)
            try FindStateSupport.write("needle in b\n", "b.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            let gate = FindGate()
            FindStateSupport.hold("b.txt", with: gate, in: state)

            let task = Task { await state.search("needle") }
            try await eventually { state.searchResult.count == 1 }
            state.clearResults()

            #expect(state.findNavigatorStatus == .none)
            #expect(state.searchResult.isEmpty)
            #expect(state.searchResultsCount == 0)
            #expect(state.searchResultsFileCount == 0)

            await gate.open()
            await task.value
            try await Task.sleep(for: .milliseconds(150))

            #expect(state.findNavigatorStatus == .none)
            #expect(state.searchResult.isEmpty)
            #expect(state.tempSearchResults.isEmpty)
        }
    }

    @Test
    func aSearchStartedBeforeItsPredecessorRanIsSuperseded() async throws {
        try await withTempDir { dir in
            try FindStateSupport.write("needle in a\n", "a.txt", in: dir)
            try FindStateSupport.write("other in b\n", "b.txt", in: dir)
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }

            let first = Task { await state.search("needle") }
            let second = Task { await state.search("other") }
            await first.value
            await second.value

            #expect(state.findNavigatorStatus == .found)
            #expect(state.searchQuery == "other")
            #expect(state.searchResult.map(\.file.name) == ["b.txt"])
        }
    }

    @Test
    func theGenerationGuardRejectsStaleSearches() async throws {
        try await withTempDir { dir in
            let (workspace, state) = try await FindStateSupport.prepare(in: dir)
            defer { workspace.close() }
            await state.search("needle")
            let generation = state.searchGeneration

            #expect(state.isCurrentSearch(generation))
            #expect(!state.isCurrentSearch(generation - 1))
            #expect(!state.isCurrentSearch(generation + 1))
        }
    }
}
