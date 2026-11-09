import AppKit

@MainActor
enum ShowUsagesController {
    @discardableResult
    static func present(
        in controller: DreamderWindowController,
        lspService: LSPService? = .shared
    ) -> Task<Void, Never>? {
        switch LSPEditorContextResolver.resolve(workspace: controller.workspace, lspService: lspService) {
        case .ready(let context):
            return Task { @MainActor in
                let rows = await LSPUsagesLoader.rows(for: context)
                guard !rows.isEmpty else {
                    let message = context.symbol.isEmpty
                        ? "No usages found"
                        : "No usages found for '\(context.symbol)'"
                    ShowUsagesPanelHost.shared.showMessage(message, in: controller)
                    return
                }
                ShowUsagesPanelHost.shared.show(rows: rows, symbol: context.symbol, in: controller)
            }
        case .missingServer:
            ShowUsagesPanelHost.shared.showMessage(
                "Show Usages needs a language server for this file",
                in: controller
            )
            return nil
        case .unavailable:
            return nil
        }
    }
}

extension DreamderWindowController {
    @IBAction func showUsages(_ sender: Any?) {
        ShowUsagesController.present(in: self)
    }

    @IBAction func findUsages(_ sender: Any?) {
        ShowUsagesController.present(in: self)
    }
}
