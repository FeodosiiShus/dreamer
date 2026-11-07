import Cocoa
import SwiftUI

final class DreamderSplitViewController: NSSplitViewController {
    private weak var workspace: WorkspaceDocument?
    private weak var windowRef: NSWindow?
    private var hasInstalledContent = false

    init(workspace: WorkspaceDocument, windowRef: NSWindow) {
        self.workspace = workspace
        self.windowRef = windowRef
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        guard !hasInstalledContent else { return }
        hasInstalledContent = true

        guard let windowRef,
              let workspace,
              let editorManager = workspace.editorManager,
              let statusBarViewModel = workspace.statusBarViewModel,
              let utilityAreaModel = workspace.utilityAreaModel,
              let taskManager = workspace.taskManager else {
            hasInstalledContent = false
            return
        }

        let content = NSHostingController(
            rootView: SettingsInjector {
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

        let item = NSSplitViewItem(viewController: content)
        item.canCollapse = false
        item.minimumThickness = 200
        addSplitViewItem(item)
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        guard let workspace else { return }

        ToolWindowLayout(workspace: workspace).apply(to: workspace.toolWindowManager)
        workspace.notificationPanel.updateToolbarItem()
    }
}
