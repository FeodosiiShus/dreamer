import AppKit

@MainActor
enum IntentionPopupController {
    typealias RequestFactory = @MainActor (CodeFileDocument, [WorkspaceDiagnostic]) -> CodeActionRequest?

    static let missingServerMessage = "Context actions need a language server for this file"
    static let noActionsMessage = "No context actions available at this location"

    static func defaultRequest(codeFile: CodeFileDocument, diagnostics: [WorkspaceDiagnostic]) -> CodeActionRequest? {
        CodeActionRequest.make(codeFile: codeFile, diagnostics: diagnostics)
    }

    static func reportFailure() {
        NSSound.beep()
    }

    static func present(
        in controller: DreamderWindowController,
        codeFile: CodeFileDocument,
        makeRequest: @escaping RequestFactory = { IntentionPopupController.defaultRequest(codeFile: $0, diagnostics: $1) },
        failureHandler: @escaping @MainActor () -> Void
    ) async {
        var diagnostics: [WorkspaceDiagnostic] = []
        if let url = codeFile.fileURL, let store = controller.workspace?.diagnosticsStore {
            diagnostics = store.diagnostics(for: url)
        }
        guard let request = makeRequest(codeFile, diagnostics) else {
            IntentionPopupHost.shared.showMessage(missingServerMessage, in: controller)
            return
        }
        let groups = await request.fetch()
        guard !groups.isEmpty else {
            IntentionPopupHost.shared.showMessage(noActionsMessage, in: controller)
            return
        }
        IntentionPopupHost.shared.show(
            groups: groups,
            in: controller,
            anchor: LSPCaretAnchor.screenRect(in: controller.window)
        ) { action in
            Task { @MainActor in
                await perform(action, request: request, failureHandler: failureHandler)
            }
        }
    }

    static func perform(
        _ action: IntentionAction,
        request: CodeActionRequest,
        failureHandler: @MainActor () -> Void
    ) async {
        if await !request.perform(action) {
            failureHandler()
        }
    }
}

extension DreamderWindowController {
    @IBAction func showContextActions(_ sender: Any?) {
        guard let codeFile = workspace?.editorManager?.activeEditor.selectedTab?.file.fileDocument else { return }
        Task { @MainActor in
            await IntentionPopupController.present(
                in: self,
                codeFile: codeFile,
                failureHandler: IntentionPopupController.reportFailure
            )
        }
    }
}
