import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorViewTests {
    @Test
    func rendersEveryStatusOfTheSearch() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            #expect(state.searchResultsCount == 3)
            #expect(state.searchResult.count == 2)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorView() }
            defer { hosted.close() }
            try await hosted.settle()
            try await eventually { !hosted.views(of: NSOutlineView.self).isEmpty }
            #expect(hosted.renders())
            let found = hosted.snapshot()

            state.findNavigatorStatus = .searching
            try await hosted.settle()
            #expect(hosted.views(of: NSOutlineView.self).count == 1)
            state.searchResultsCount = 0
            state.searchResult = []
            try await eventually { hosted.views(of: NSOutlineView.self).isEmpty }
            try await hosted.settle()
            let searching = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(found, searching))

            state.findNavigatorStatus = .replacing
            try await hosted.settle()
            let replacing = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(searching, replacing))

            state.findNavigatorStatus = .replaced(updatedFiles: 2)
            try await hosted.settle()
            let replaced = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(replacing, replaced))

            state.findNavigatorStatus = .failed(errorMessage: "Invalid regular expression.")
            try await hosted.settle()
            let failed = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(replaced, failed))

            state.findNavigatorStatus = .none
            try await hosted.settle()
            let idle = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(failed, idle))

            state.searchQuery = "missing"
            state.searchResultsCount = 0
            state.searchResult = []
            state.findNavigatorStatus = .found
            try await hosted.settle()
            #expect(hosted.views(of: NSOutlineView.self).isEmpty)
            let empty = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(idle, empty))
            #expect(hosted.renders())
        }
    }

    @Test
    func showsTheResultListOnceResultsExist() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let results = state.searchResult
            state.findNavigatorStatus = .none
            state.searchResultsCount = 0
            state.searchResult = []

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorView() }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.views(of: NSOutlineView.self).isEmpty)
            let idle = hosted.snapshot()

            state.searchResult = results
            state.searchResultsCount = results.reduce(0) { $0 + $1.lineMatches.count }
            state.findNavigatorStatus = .found
            try await eventually { hosted.views(of: NSOutlineView.self).first?.numberOfRows == 5 }
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()))
        }
    }

    @Test
    func createsAFreshSearchStateWhenTheWorkspaceHasNone() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            workspace.searchState = nil

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorView() }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            #expect(hosted.views(of: NSOutlineView.self).isEmpty)
        }
    }
}
