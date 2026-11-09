import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorIndexBarTests {
    private func withIndexedState(
        _ body: (WorkspaceDocument.SearchState) async throws -> Void
    ) async throws {
        try await withTempDir { dir in
            try "alpha\n".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            try await eventually { state.indexStatus == .done }
            try await body(state)
        }
    }

    private func hostBar(_ state: WorkspaceDocument.SearchState) -> HostedView {
        HostedViewFixture.host {
            FindNavigatorIndexBar(state: state)
                .frame(width: 320, height: 80)
        }
    }

    @Test
    func barIsHiddenWithoutIndexingAndTracksProgressUntilDone() async throws {
        try await withIndexedState { state in
            state.indexStatus = .none
            let hosted = hostBar(state)
            defer { hosted.close() }
            try await hosted.settle()
            let hidden = hosted.snapshot()

            state.indexStatus = .indexing(progress: 0.25)
            try await hosted.settle()
            let first = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(hidden, first))

            state.indexStatus = .indexing(progress: 0.75)
            try await hosted.settle()
            let second = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(first, second))

            state.indexStatus = .done
            try await eventually { !HostedView.pixelsDiffer(hidden, hosted.snapshot()) }
            #expect(HostedView.pixelsDiffer(second, hosted.snapshot()))

            state.indexStatus = .indexing(progress: 0.5)
            try await hosted.settle()
            state.indexStatus = .none
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(second, hosted.snapshot()))
        }
    }

    @Test
    func barStartsVisibleWhenIndexingIsAlreadyRunning() async throws {
        try await withIndexedState { state in
            state.indexStatus = .indexing(progress: 0.5)
            let hosted = hostBar(state)
            defer { hosted.close() }
            try await hosted.settle()
            let running = hosted.snapshot()
            #expect(hosted.renders())

            state.indexStatus = .none
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(running, hosted.snapshot()))
        }
    }

    @Test
    func barStartsHiddenWhenIndexingIsAlreadyDone() async throws {
        try await withIndexedState { state in
            state.indexStatus = .done
            let hosted = hostBar(state)
            defer { hosted.close() }
            try await hosted.settle()

            state.indexStatus = .none
            let reference = hostBar(state)
            defer { reference.close() }
            try await reference.settle()
            try await eventually { !HostedView.pixelsDiffer(reference.snapshot(), hosted.snapshot()) }
        }
    }
}
