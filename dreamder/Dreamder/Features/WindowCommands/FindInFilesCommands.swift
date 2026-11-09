import SwiftUI

struct FindInFilesCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            FindInFilesMenu(windowController: windowController)
        }
    }
}

@MainActor
enum FindInFilesAction {
    static func show(replace: Bool, in workspace: WorkspaceDocument?) {
        guard let workspace else { return }
        workspace.toolWindowManager.show(.find)
        workspace.searchState?.setReplaceMode(replace)
        workspace.searchState?.shouldFocusSearchField = true
    }
}

struct FindInFilesMenu: View {
    let windowController: DreamderWindowController?

    var hasWorkspace: Bool {
        windowController?.workspace != nil
    }

    var body: some View {
        Divider()
        Button("Find in Files…", action: findInFiles)
            .keymapShortcut(.findInFiles)
            .disabled(!hasWorkspace)
        Button("Replace in Files…", action: replaceInFiles)
            .keymapShortcut(.replaceInFiles)
            .disabled(!hasWorkspace)
    }

    func findInFiles() {
        FindInFilesAction.show(replace: false, in: windowController?.workspace)
    }

    func replaceInFiles() {
        FindInFilesAction.show(replace: true, in: windowController?.workspace)
    }
}
