import Foundation
import LanguageServerProtocol

extension LanguageServer {
    static var codeActionMethod: String { "textDocument/codeAction" }

    var supportsCodeActions: Bool {
        switch serverCapabilities.codeActionProvider {
        case .optionA(let enabled):
            return enabled
        case .optionB:
            return true
        case nil:
            return dynamicCapabilities.hasCapability(Self.codeActionMethod)
        }
    }

    var resolvesCodeActionEdits: Bool {
        guard case .optionB(let options) = serverCapabilities.codeActionProvider else { return false }
        return options.resolveProvider ?? false
    }

    func requestCodeActions(
        for documentURI: String,
        range: LSPRange,
        diagnostics: [Diagnostic],
        only: [CodeActionKind]? = nil,
        triggerKind: CodeActionTriggerKind = .invoked
    ) async throws -> CodeActionResponse {
        await flushPendingEdits(for: documentURI)
        do {
            let params = CodeActionParams(
                textDocument: TextDocumentIdentifier(uri: documentURI),
                range: range,
                context: CodeActionContext(diagnostics: diagnostics, only: only, triggerKind: triggerKind)
            )
            return try await lspInstance.codeAction(params)
        } catch {
            logger.warning("requestCodeActions: Error \(error)")
            throw error
        }
    }

    func requestResolveCodeAction(_ action: CodeAction, for documentURI: String) async throws -> CodeAction {
        await flushPendingEdits(for: documentURI)
        do {
            return try await lspInstance.codeActionResolve(action)
        } catch {
            logger.warning("requestResolveCodeAction: Error \(error)")
            throw error
        }
    }

    @discardableResult
    func requestExecuteCommand(_ command: LSPCommand, for documentURI: String) async throws -> LSPAny? {
        await flushPendingEdits(for: documentURI)
        do {
            let params = ExecuteCommandParams(command: command.command, arguments: command.arguments)
            return try await lspInstance.executeCommand(params)
        } catch {
            logger.warning("requestExecuteCommand: Error \(error)")
            throw error
        }
    }
}
