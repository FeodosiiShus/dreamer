import AppKit
import os
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerGitBranchesCoverageTests {
    @Test
    func showGitBranchesPostsThePopupNotificationForItsWorkspace() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            workspace.makeWindowControllers()
            let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
            #expect(controller.workspace === workspace)
            let window = try #require(controller.window)
            window.isReleasedWhenClosed = false
            defer {
                window.close()
                workspace.close()
            }
            let received = OSAllocatedUnfairLock(initialState: [ObjectIdentifier]())
            let token = NotificationCenter.default.addObserver(
                forName: .showGitBranchesPopup,
                object: nil,
                queue: nil
            ) { notification in
                guard let object = notification.object else { return }
                let identifier = ObjectIdentifier(object as AnyObject)
                received.withLock { $0.append(identifier) }
            }
            defer { NotificationCenter.default.removeObserver(token) }

            controller.showGitBranches(nil)
            #expect(received.withLock { $0 }.filter { $0 == ObjectIdentifier(workspace) }.count == 1)

            let handled = NSApp.sendAction(
                #selector(DreamderWindowController.showGitBranches(_:)),
                to: controller,
                from: nil
            )
            #expect(handled)
            #expect(received.withLock { $0 }.filter { $0 == ObjectIdentifier(workspace) }.count == 2)
        }
    }

    @Test
    func popupNotificationNameIsStable() {
        #expect(Notification.Name.showGitBranchesPopup.rawValue == "dev.dreamder.showGitBranchesPopup")
    }
}
