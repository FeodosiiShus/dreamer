import AppKit

@MainActor
enum QuickDocumentationController {
    @discardableResult
    static func present(
        in controller: DreamderWindowController,
        lspService: LSPService? = .shared
    ) -> Task<Void, Never>? {
        switch LSPEditorContextResolver.resolve(workspace: controller.workspace, lspService: lspService) {
        case .ready(let context):
            return Task { @MainActor in
                let response = (try? await context.client.requestHover(
                    for: context.documentURI,
                    context.position
                )) ?? nil
                guard let content = QuickDocumentationMarkup.content(from: response) else {
                    QuickDocumentationPanelHost.shared.showMessage("No documentation found", in: controller)
                    return
                }
                QuickDocumentationPanelHost.shared.show(content: content, tab: context.tab, in: controller)
            }
        case .missingServer:
            QuickDocumentationPanelHost.shared.showMessage(
                "Quick Documentation needs a language server for this file",
                in: controller
            )
            return nil
        case .unavailable:
            return nil
        }
    }
}

extension DreamderWindowController {
    @IBAction func showQuickDocumentation(_ sender: Any?) {
        QuickDocumentationController.present(in: self)
    }
}
