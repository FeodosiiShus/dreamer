import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct FindToolWindowTests {
    @Test
    func rendersAndFocusesTheSearchFieldOnAppear() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            workspace.toolWindowManager.show(.find)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindToolWindow() }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(workspace.toolWindowManager.isVisible(.find))
        }
    }

    @Test
    func appearingRequestsFocusAndTheFormConsumesIt() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindToolWindow() }
            defer { hosted.close() }

            try await eventually { !state.shouldFocusSearchField }
            try await hosted.settle()
            #expect(hosted.renders())
        }
    }

    @Test
    func replaceInFilesSwitchesTheHostedWindowToReplaceMode() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let state = try #require(workspace.searchState)

            let hosted = try HostedViewFixture.hostInWorkspace(workspace) { FindToolWindow() }
            defer { hosted.close() }
            try await hosted.settle()
            let findMode = hosted.snapshot()

            FindInFilesAction.show(replace: true, in: workspace)
            try await hosted.settle()
            #expect(state.selectedMode.isReplaceMode)
            #expect(!state.shouldFocusSearchField)
            let replaceMode = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(findMode, replaceMode))

            FindInFilesAction.show(replace: false, in: workspace)
            try await hosted.settle()
            #expect(!state.selectedMode.isReplaceMode)
            #expect(HostedView.pixelsDiffer(replaceMode, hosted.snapshot()))
        }
    }

    @Test
    func hideCallbackHidesOnlyTheGivenToolWindow() throws {
        let manager = ToolWindowManager()
        manager.show(.find)
        manager.show(.run)

        manager.hideCallback(for: .find)()

        #expect(!manager.isVisible(.find))
        #expect(manager.isVisible(.run))

        manager.hideCallback(for: .run)()
        #expect(!manager.isVisible(.run))
    }
}
