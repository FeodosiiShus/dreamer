import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private struct MergeConflictsMenuStateProbeView: View {
    @MergeConflictsMenuState private var hasUnmergedFiles

    var body: some View {
        Text(hasUnmergedFiles ? "unmerged files" : "clean tree")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red)
    }
}

@MainActor
@Suite(.uiGate)
struct MergeConflictsMenuStateCoverageTests {
    private func workspace(_ root: URL) -> WorkspaceDocument {
        let document = WorkspaceDocument()
        document.sourceControlManager = SourceControlManager(workspaceURL: root, editorManager: EditorManager())
        return document
    }

    @Test
    func propertyWrapperStartsTrackingWhenItsViewRenders() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            MergeConflictsMenuStateProbeView()
        }
        defer { hosted.close() }

        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func storeFollowsTheConflictsOfTheActiveWorkspace() async throws {
        try await withTempDir { dir in
            let fixture = try await GitMergeFixture.mergeConflict(in: dir)
            let active = workspace(dir)
            let store = MergeConflictsMenuState.Store(activeWorkspace: { active })

            store.refresh()
            #expect(store.hasUnmergedFiles == false)

            store.start()
            try await eventually { store.hasUnmergedFiles }

            try await fixture.run("checkout", "--ours", "--", "app/config.txt", "docs/notes.txt")
            try await fixture.run("add", "-A")
            let manager = try #require(active.sourceControlManager)
            manager.changedFiles = [
                GitChangedFile(
                    status: .modified,
                    stagedStatus: .none,
                    fileURL: dir.appending(path: "app/config.txt"),
                    originalFilename: nil
                )
            ]

            try await eventually { store.hasUnmergedFiles == false }
        }
    }

    @Test
    func storeWithoutAnActiveWorkspaceStaysClean() {
        let store = MergeConflictsMenuState.Store(activeWorkspace: { nil })

        store.refresh()
        store.refresh()

        #expect(store.hasUnmergedFiles == false)
    }
}
