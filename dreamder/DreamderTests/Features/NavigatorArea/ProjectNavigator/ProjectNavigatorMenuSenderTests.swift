import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorMenuSenderTests {
    private struct MadeMenu {
        let menu: ProjectNavigatorMenu
        let controller: ProjectNavigatorWeakController
    }

    private func makeMenu(in workspace: WorkspaceDocument) -> MadeMenu {
        let controller = ProjectNavigatorViewController()
        controller.workspace = workspace
        _ = controller.view
        let menu = ProjectNavigatorMenu(controller)
        menu.workspace = workspace
        return MadeMenu(menu: menu, controller: ProjectNavigatorWeakController(controller: controller))
    }

    @Test
    func theMenuDoesNotKeepItsControllerAlive() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }

            let made = makeMenu(in: workspace)

            try await eventually(timeout: .seconds(60)) { made.controller.controller == nil }
            #expect(made.menu.sender == nil)
        }
    }

    @Test
    func actionsOfAMenuWhoseControllerIsGoneDoNothing() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "a.txt")
            try "a\n".write(to: url, atomically: true, encoding: .utf8)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let file = try #require(workspace.workspaceFileManager?.getFile(url.path, createIfNotFound: true))
            let made = makeMenu(in: workspace)
            try await eventually(timeout: .seconds(60)) { made.controller.controller == nil }
            let menu = made.menu
            menu.item = file
            workspace.listenerModel.highlightedFileItem = file

            #expect(menu.selectedItems().isEmpty)
            menu.openInTab()
            menu.renameFile()

            #expect(workspace.editorManager?.activeEditor.tabs.isEmpty == true)
        }
    }
}
