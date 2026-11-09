import SwiftUI

struct CodeCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    var body: some Commands {
        CommandMenu("Code") {
            CodeMenu(windowController: windowController)
        }
    }
}

struct CodeMenu: View {
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

    private var selectedFileURL: URL? {
        windowController?.workspace?.editorManager?.activeEditor.selectedTab?.file.url
    }

    var hasCodeDocument: Bool {
        windowController?.workspace?.editorManager?.activeEditor.selectedTab?.file.fileDocument != nil
    }

    var hasLanguageServer: Bool {
        guard let url = selectedFileURL else { return false }
        return lspService.languageClient(forDocument: url) != nil
    }

    var body: some View {
        Button("Show Context Actions", action: showContextActions)
            .keymapShortcut(.showContextActions)
            .disabled(!hasLanguageServer)

        Divider()

        Button("Reformat Code", action: reformatCode)
            .keymapShortcut(.reformatCode)
            .disabled(!hasCodeDocument)

        Button("Optimize Imports", action: optimizeImports)
            .keymapShortcut(.optimizeImports)
            .disabled(!hasLanguageServer)
    }

    func showContextActions() {
        sendAction(#selector(DreamderWindowController.showContextActions(_:)))
    }

    func reformatCode() {
        sendAction(#selector(DreamderWindowController.reformatCode(_:)))
    }

    func optimizeImports() {
        sendAction(#selector(DreamderWindowController.optimizeImports(_:)))
    }
}
