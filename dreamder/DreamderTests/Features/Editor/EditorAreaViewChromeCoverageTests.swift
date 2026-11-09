import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private struct EditorAreaChromeHarness: View {
    let editor: Editor
    let store: Dreamder.Settings
    @FocusState private var focus: Editor?

    var body: some View {
        EditorAreaView(editor: editor, focus: $focus)
            .environment(\.settingsStore, store)
    }
}

@MainActor
@Suite(.uiGate)
struct EditorAreaViewChromeCoverageTests {
    @Test
    func theEmptyStateSendsItsActionsThroughTheResponderChain() {
        let unhandled = Selector(("dreamderEditorAreaEmptyStateProbe:"))

        EditorAreaView.emptyState().sendAction(unhandled)

        #expect(NSApp.target(forAction: unhandled) == nil)
    }

    @Test
    func hidingTheTabBarChangesTheEditorAreaChrome() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.editorManager)
            let editor = manager.activeEditor
            editor.workspace = workspace
            let inPlace = Dreamder.Settings(
                baseURL: directory.appending(path: "in-place-settings", directoryHint: .isDirectory)
            )
            inPlace.preferences.navigation.navigationStyle = .openInPlace
            let inTabs = Dreamder.Settings(
                baseURL: directory.appending(path: "tabs-settings", directoryHint: .isDirectory)
            )
            inTabs.preferences.navigation.navigationStyle = .openInTabs

            let hidden = try HostedViewFixture.hostInWorkspace(workspace) {
                EditorAreaChromeHarness(editor: editor, store: inPlace)
            }
            defer { hidden.close() }
            let shown = try HostedViewFixture.hostInWorkspace(workspace) {
                EditorAreaChromeHarness(editor: editor, store: inTabs)
            }
            defer { shown.close() }
            try await hidden.settle()
            try await shown.settle()

            #expect(manager.activeEditor === editor)
            #expect(hidden.renders())
            #expect(shown.renders())
            #expect(HostedView.pixelsDiffer(hidden.snapshot(), shown.snapshot()))
        }
    }
}
