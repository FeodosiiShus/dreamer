import SwiftUI

struct RefactorCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandMenu("Refactor") {
            RefactorMenu(windowController: windowController)
        }
        CommandGroup(after: .textEditing) {
            EditorIntelligenceMenu(windowController: windowController)
        }
    }
}

@MainActor
enum EditorLanguageServerAvailability {
    static func isAvailable(in workspace: WorkspaceDocument?, lspService: LSPService) -> Bool {
        guard let url = workspace?.editorManager?.activeEditor.selectedTab?.file.url else { return false }
        return lspService.languageClient(forDocument: url) != nil
    }
}

struct RefactorMenu: View {
    let windowController: DreamderWindowController?
    let sendAction: @MainActor (Selector) -> Void
    private var lspService: LSPService { .shared }

    init(
        windowController: DreamderWindowController?,
        sendAction: @escaping @MainActor (Selector) -> Void = MenuResponderChain.send
    ) {
        self.windowController = windowController
        self.sendAction = sendAction
    }

    var canRefactor: Bool {
        EditorLanguageServerAvailability.isAvailable(in: windowController?.workspace, lspService: lspService)
    }

    var body: some View {
        Button("Rename…", action: rename)
            .keymapShortcut(.renameSymbol)
            .disabled(!canRefactor)
    }

    func rename() {
        sendAction(#selector(DreamderWindowController.renameSymbol(_:)))
    }
}

struct EditorIntelligenceMenu: View {
    let windowController: DreamderWindowController?
    private var lspService: LSPService { .shared }

    init(windowController: DreamderWindowController?) {
        self.windowController = windowController
    }

    private var workspace: WorkspaceDocument? {
        windowController?.workspace
    }

    var hasEditor: Bool {
        workspace?.editorManager?.activeEditor.selectedTab != nil
    }

    var hasLanguageServer: Bool {
        EditorLanguageServerAvailability.isAvailable(in: workspace, lspService: lspService)
    }

    var body: some View {
        Divider()
        Button("Extend Selection") { Task { await expandSelection() } }
            .keymapShortcut(.extendSelection)
            .disabled(!hasEditor)
        Button("Shrink Selection", action: shrinkSelection)
            .keymapShortcut(.shrinkSelection)
            .disabled(!hasEditor)
        Button("Parameter Info") { Task { await showParameterInfo() } }
            .keymapShortcut(.parameterInfo)
            .disabled(!hasLanguageServer)
        Menu("Code Folding") {
            Button("Collapse") { Task { await collapseCodeBlock() } }
                .keymapShortcut(.collapseCodeBlock)
            Button("Expand", action: expandCodeBlock)
                .keymapShortcut(.expandCodeBlock)
            Button("Collapse All") { Task { await collapseAll() } }
                .keymapShortcut(.collapseAll)
            Button("Expand All", action: expandAll)
                .keymapShortcut(.expandAll)
            Button("Collapse Comments") { Task { await collapseComments() } }
                .keymapShortcut(.collapseComments)
        }
        .disabled(!hasEditor)
    }

    func expandSelection() async {
        await EditorFeatureCommands.expandSelection(workspace: workspace)
    }

    func shrinkSelection() {
        EditorFeatureCommands.shrinkSelection(workspace: workspace)
    }

    func showParameterInfo() async {
        await EditorFeatureCommands.showParameterInfo(workspace: workspace)
    }

    func collapseCodeBlock() async {
        await EditorFeatureCommands.collapseCodeBlock(workspace: workspace)
    }

    func expandCodeBlock() {
        EditorFeatureCommands.expandCodeBlock(workspace: workspace)
    }

    func collapseAll() async {
        await EditorFeatureCommands.collapseAll(workspace: workspace)
    }

    func expandAll() {
        EditorFeatureCommands.expandAll(workspace: workspace)
    }

    func collapseComments() async {
        await EditorFeatureCommands.collapseComments(workspace: workspace)
    }
}

struct NavigationExtrasMenuItems: View {
    let windowController: DreamderWindowController?
    let sendAction: @MainActor (Selector) -> Void
    private var lspService: LSPService { .shared }

    init(
        windowController: DreamderWindowController?,
        sendAction: @escaping @MainActor (Selector) -> Void = MenuResponderChain.send
    ) {
        self.windowController = windowController
        self.sendAction = sendAction
    }

    var canNavigate: Bool {
        EditorLanguageServerAvailability.isAvailable(in: windowController?.workspace, lspService: lspService)
    }

    var body: some View {
        Button("Go to Implementation", action: goToImplementation)
            .keymapShortcut(.goToImplementation)
            .disabled(!canNavigate)
        Button("Recent Locations", action: showRecentLocations)
            .keymapShortcut(.recentLocations)
            .disabled(windowController?.workspace == nil)
    }

    func goToImplementation() {
        LSPNavigationCommands.goToImplementation(workspace: windowController?.workspace)
    }

    func showRecentLocations() {
        sendAction(#selector(DreamderWindowController.showRecentLocations(_:)))
    }
}
