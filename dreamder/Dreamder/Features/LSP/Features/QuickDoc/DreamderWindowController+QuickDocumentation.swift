import AppKit

@MainActor
enum QuickDocumentationController {
    static func present(in controller: DreamderWindowController) {
        switch LSPEditorContextResolver.resolve(workspace: controller.workspace) {
        case .ready(let context):
            Task { @MainActor in
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
        case .unavailable:
            break
        }
    }
}

extension DreamderWindowController {
    @IBAction func showQuickDocumentation(_ sender: Any?) {
        QuickDocumentationController.present(in: self)
    }
}
