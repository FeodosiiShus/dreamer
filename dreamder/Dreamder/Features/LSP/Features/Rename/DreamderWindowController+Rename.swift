import AppKit
import LanguageServerProtocol

@MainActor
enum RenameController {
    @discardableResult
    static func present(in controller: DreamderWindowController) -> Task<Void, Never>? {
        switch LSPEditorContextResolver.resolve(workspace: controller.workspace) {
        case .ready(let context):
            let request = RenameRequest(
                documentURI: context.documentURI,
                position: context.position,
                documentText: context.documentText,
                symbol: context.symbol
            )
            let backend = RenameBackend.make(
                client: context.client,
                documentText: { LSPEditorContextResolver.documentText(for: context.tab) },
                apply: { edit in await context.service.applyWorkspaceEdit(edit, via: context.client) }
            )
            let presenter = RenamePanelPresenter(controller: controller)
            return Task { @MainActor in
                await RenameFlow.run(request: request, backend: backend, presenter: presenter)
            }
        case .missingServer:
            ShowUsagesPanelHost.shared.showMessage(RenameMessages.missingServer, in: controller)
            return nil
        case .unavailable:
            return nil
        }
    }
}

extension DreamderWindowController {
    @IBAction func renameSymbol(_ sender: Any?) {
        RenameController.present(in: self)
    }
}
