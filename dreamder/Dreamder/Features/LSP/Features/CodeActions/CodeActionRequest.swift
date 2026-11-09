import CodeEditTextView
import Foundation
import LanguageServerProtocol

@MainActor
struct CodeActionRequest {
    typealias Client = LSPService.LanguageServerType

    let client: Client
    let documentURI: String
    let range: LSPRange
    let diagnostics: [Diagnostic]

    static func make(
        codeFile: CodeFileDocument,
        diagnostics workspaceDiagnostics: [WorkspaceDiagnostic],
        lspService: LSPService? = .shared
    ) -> CodeActionRequest? {
        guard let fileURL = codeFile.fileURL,
              let textView = codeFile.attachedTextView,
              let client = lspService?.languageClient(forDocument: fileURL) else {
            return nil
        }
        let selection = textView.selectionManager.textSelections.first?.range ?? NSRange(location: 0, length: 0)
        guard let range = textView.lspRangeFrom(nsRange: selection) else { return nil }
        return CodeActionRequest(
            client: client,
            documentURI: fileURL.lspURI,
            range: range,
            diagnostics: LSPCodeActionDiagnostics.diagnostics(in: workspaceDiagnostics, intersecting: range)
        )
    }

    static func makeForLine(
        _ line: Int,
        codeFile: CodeFileDocument,
        diagnostics workspaceDiagnostics: [WorkspaceDiagnostic],
        lspService: LSPService? = .shared
    ) -> CodeActionRequest? {
        guard let fileURL = codeFile.fileURL,
              let client = lspService?.languageClient(forDocument: fileURL) else {
            return nil
        }
        let lineDiagnostics = LSPCodeActionDiagnostics.diagnostics(in: workspaceDiagnostics, onLine: line)
        guard let range = LSPCodeActionDiagnostics.range(covering: lineDiagnostics) else { return nil }
        return CodeActionRequest(
            client: client,
            documentURI: fileURL.lspURI,
            range: range,
            diagnostics: lineDiagnostics
        )
    }

    func fetch(
        only: [CodeActionKind]? = nil,
        triggerKind: CodeActionTriggerKind = .invoked
    ) async -> [IntentionGroup] {
        guard client.supportsCodeActions else { return [] }
        do {
            let response = try await client.requestCodeActions(
                for: documentURI,
                range: range,
                diagnostics: diagnostics,
                only: only,
                triggerKind: triggerKind
            )
            return LSPCodeActionMapping.groups(from: response, diagnostics: diagnostics)
        } catch {
            return []
        }
    }

    @discardableResult
    func perform(_ intention: IntentionAction) async -> Bool {
        switch intention.payload {
        case .command(let command):
            return await execute(command)
        case .codeAction(let action):
            return await perform(action)
        }
    }

    private func perform(_ original: CodeAction) async -> Bool {
        var action = original
        if action.edit == nil, client.resolvesCodeActionEdits || action.data != nil {
            if let resolved = try? await client.requestResolveCodeAction(action, for: documentURI) {
                action = resolved
            }
        }
        if let edit = action.edit {
            let result = await WorkspaceEditApplier(client: client).apply(edit)
            guard result.applied else { return false }
            if let command = action.command {
                return await execute(command)
            }
            return true
        }
        if let command = action.command {
            return await execute(command)
        }
        return false
    }

    private func execute(_ command: LSPCommand) async -> Bool {
        do {
            try await client.requestExecuteCommand(command, for: documentURI)
            return true
        } catch {
            return false
        }
    }
}
