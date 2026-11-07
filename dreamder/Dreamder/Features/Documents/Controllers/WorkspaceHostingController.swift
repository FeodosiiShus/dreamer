import Cocoa
import SwiftUI

final class WorkspaceHostingController: NSHostingController<AnyView> {
    private weak var workspace: WorkspaceDocument?

    init?(workspace: WorkspaceDocument, windowRef: NSWindow) {
        guard let editorManager = workspace.editorManager,
              let statusBarViewModel = workspace.statusBarViewModel,
              let utilityAreaModel = workspace.utilityAreaModel,
              let taskManager = workspace.taskManager else {
            return nil
        }

        let rootView = AnyView(
            SettingsInjector {
                WindowObserver(window: WindowBox(value: windowRef)) {
                    IslandsWorkspaceView()
                        .environment(workspace)
                        .environment(editorManager)
                        .environment(statusBarViewModel)
                        .environment(utilityAreaModel)
                        .environment(taskManager)
                        .environment(workspace.undoRegistration)
                        .environment(workspace.toolWindowManager)
                        .environment(workspace.sourceControlManager)
                }
            }
        )

        super.init(rootView: rootView)
        self.workspace = workspace
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        guard let workspace else { return }

        ToolWindowLayout(workspace: workspace).apply(to: workspace.toolWindowManager)
        workspace.notificationPanel.updateToolbarItem()
    }
}
