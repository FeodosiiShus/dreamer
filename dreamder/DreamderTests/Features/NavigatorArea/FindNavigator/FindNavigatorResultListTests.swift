import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindNavigatorResultListTests {
    @Test
    func hostedListFollowsTheSearchResults() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let results = state.searchResult
            let firstResult = try results.required(at: 0)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorResultList() }
            defer { hosted.close() }
            try await eventually { hosted.views(of: NSOutlineView.self).first?.numberOfRows == 5 }
            let outline = try #require(hosted.views(of: NSOutlineView.self).first)
            #expect(outline.isItemExpanded(firstResult))

            state.searchResult = [firstResult]
            try await eventually { outline.numberOfRows == 1 + firstResult.lineMatches.count }

            state.searchResult = []
            try await eventually { outline.numberOfRows == 0 }

            state.searchResult = results
            try await eventually { outline.numberOfRows == 5 }
        }
    }

    @Test
    func listWithoutASearchStateStartsEmpty() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            workspace.searchState = nil

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorResultList() }
            defer { hosted.close() }
            try await hosted.settle()
            let outline = try #require(hosted.views(of: NSOutlineView.self).first)
            #expect(outline.numberOfRows == 0)
        }
    }

    @Test
    func coordinatorWithoutStateDoesNotObserveAndReleasesItsTask() async throws {
        let coordinator = FindNavigatorResultList.Coordinator(state: nil, controller: nil)
        #expect(coordinator.observation == nil)
        #expect(coordinator.focusObservation == nil)
        #expect(coordinator.controller == nil)
    }

    @Test
    func coordinatorCancelsItsObservationWhenReleased() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let controller = FindNavigatorListViewController(workspace: workspace)

            var coordinator: FindNavigatorResultList.Coordinator? = .init(state: state, controller: controller)
            let observation = try #require(coordinator?.observation)
            let focusObservation = try #require(coordinator?.focusObservation)
            #expect(!observation.isCancelled)
            #expect(!focusObservation.isCancelled)
            coordinator = nil
            try await eventually { observation.isCancelled && focusObservation.isCancelled }
        }
    }

    @Test
    func focusRequestsMoveFocusIntoTheOutlineAndAreConsumed() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let results = state.searchResult
            let firstResult = try results.required(at: 0)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindNavigatorResultList() }
            defer { hosted.close() }
            try await eventually { hosted.views(of: NSOutlineView.self).first?.numberOfRows == 5 }
            let outline = try #require(hosted.views(of: NSOutlineView.self).first)
            #expect(outline.selectedRow == -1)

            state.shouldFocusResults = true
            try await eventually { !state.shouldFocusResults }
            try await eventually { outline.window?.firstResponder === outline }
            #expect(outline.selectedRow == 0)
            #expect(state.resultSelection == .file(firstResult))
        }
    }

    @Test
    func focusingAnEmptyListChangesNothing() async throws {
        try await withTempDir { dir in
            let workspace = try await FindNavigatorTestWorkspace.searched(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)
            let controller = FindNavigatorListViewController(workspace: workspace)

            controller.focusResults()

            #expect(state.resultSelection == nil)
        }
    }
}
