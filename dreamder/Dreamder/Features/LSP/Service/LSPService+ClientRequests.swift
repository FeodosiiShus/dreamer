import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol

extension LSPService {
    static let refreshRequestedNotification = Notification.Name("LSPService.refreshRequested")
    static let refreshKindUserInfoKey = "kind"
    static let refreshWorkspacePathUserInfoKey = "workspacePath"

    func makeClientRequestHandler(for key: ClientKey, client: LanguageServerType) -> LSPClientRequestHandler {
        let configuration = LSPWorkspaceConfiguration()
        let folders = [LSPWorkspaceFolders.folder(forWorkspacePath: key.workspacePath)]
        let environment = LSPClientRequestEnvironment(
            workspaceFolders: { folders },
            configuration: { configuration.value(for: $0) },
            applyEdit: { [weak self] params in
                guard let self else {
                    return ApplyWorkspaceEditResult(applied: false, failureReason: "The language service is gone")
                }
                return await self.applyWorkspaceEdit(params, for: key)
            },
            showMessage: { [weak self] params in
                await self?.presentMessageRequest(params, for: key)
            },
            showDocument: { [weak self] params in
                await self?.showDocument(params, for: key) ?? false
            },
            refresh: { [weak self] kind in
                await self?.refresh(kind, for: key)
            }
        )
        return LSPClientRequestHandler(
            environment: environment,
            capabilities: client.dynamicCapabilities,
            progress: client.workDoneProgress,
            repliesToCapabilityRegistration: false
        )
    }

    func applyWorkspaceEdit(_ params: ApplyWorkspaceEditParams, for key: ClientKey) async -> ApplyWorkspaceEditResult {
        guard languageClients[key] != nil else {
            return ApplyWorkspaceEditResult(applied: false, failureReason: "The language server is not running")
        }
        let executor = LSPWorkspaceEditExecutor { [weak self] uri, edits in
            guard let self else { return false }
            return try await self.editOpenDocument(uri: uri, edits: edits, for: key)
        }
        return await executor.apply(params.edit)
    }

    func editOpenDocument(uri: String, edits: [TextEdit], for key: ClientKey) async throws -> Bool {
        guard let client = languageClients[key] else { return false }
        let canonicalURI = LSPFileURI.fileURL(from: uri)?.lspURI
        let document = client.openFiles.document(for: uri)
            ?? canonicalURI.flatMap { client.openFiles.document(for: $0) }
        guard let document, let storage = document.content else { return false }

        let resolved = try LSPTextEditApplier.resolve(edits, in: storage.string)
        storage.beginEditing()
        for item in resolved.reversed() {
            storage.replaceCharacters(in: item.range, with: item.edit.newText)
        }
        storage.endEditing()
        document.updateChangeCount(.changeDone)

        let changes = resolved.reversed().map {
            LanguageServerType.DocumentChange(replacingContentsIn: $0.edit.range, with: $0.edit.newText)
        }
        do {
            try await client.documentChanged(uri: document.languageServerURI ?? uri, changes: changes)
        } catch {
            logger.warning("Failed to sync workspace edit for \(uri, privacy: .private): \(error)")
        }
        return true
    }

    func showDocument(_ params: ShowDocumentParams, for key: ClientKey) -> Bool {
        switch LSPShowDocumentPlan.make(for: params) {
        case let .external(url):
            guard !DreamderHeadless.isEnabled else { return false }
            return NSWorkspace.shared.open(url)
        case let .editor(url, selection, _):
            guard FileManager.default.fileExists(atPath: url.path),
                  let workspace = LSPDiagnosticsPublisher.workspace(containing: url, workspacePath: key.workspacePath),
                  workspace.editorManager != nil else {
                return false
            }
            LSPDefinitionNavigator.open(url: url, position: Self.cursorPosition(for: selection), in: workspace)
            return true
        case .invalid:
            return false
        }
    }

    func presentMessageRequest(_ params: ShowMessageRequestParams, for key: ClientKey) -> MessageActionItem? {
        languageClients[key]?.logContainer.appendLog(LogMessageParams(type: params.type, message: params.message))
        guard let actions = params.actions, !actions.isEmpty, !DreamderHeadless.isEnabled else {
            return nil
        }
        let alert = NSAlert()
        switch params.type {
        case .error:
            alert.alertStyle = .critical
        case .warning:
            alert.alertStyle = .warning
        case .info, .log:
            alert.alertStyle = .informational
        }
        alert.messageText = "\(key.languageId.rawValue.capitalized) language server"
        alert.informativeText = params.message
        for action in actions {
            alert.addButton(withTitle: action.title)
        }
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return actions.indices.contains(index) ? actions[index] : nil
    }

    func refresh(_ kind: LSPRefreshKind, for key: ClientKey) async {
        guard let client = languageClients[key] else { return }
        switch kind {
        case .semanticTokens:
            for document in client.openFiles.documents {
                do {
                    try await document.languageServerObjects.highlightProvider.documentDidChange()
                } catch {
                    logger.warning("Failed to refresh semantic tokens: \(error)")
                }
            }
        case .diagnostics:
            await refreshDiagnostics(of: client, key: key)
        case .inlayHint, .codeLens:
            NotificationCenter.default.post(
                name: Self.refreshRequestedNotification,
                object: self,
                userInfo: [
                    Self.refreshKindUserInfoKey: kind.rawValue,
                    Self.refreshWorkspacePathUserInfoKey: key.workspacePath
                ]
            )
        }
    }

    private func refreshDiagnostics(of client: LanguageServerType, key: ClientKey) async {
        let supportsPull = client.serverCapabilities.diagnosticProvider != nil
            || client.dynamicCapabilities.hasCapability("textDocument/diagnostic")
        guard supportsPull else { return }
        for uri in client.openFiles.uris {
            do {
                let report = try await client.requestPullDiagnostics(document: uri)
                guard report.kind == .full, let items = report.items else { continue }
                LSPDiagnosticsPublisher.publish(items, forDocument: uri, workspacePath: key.workspacePath)
            } catch {
                logger.warning("Failed to refresh diagnostics for \(uri, privacy: .private): \(error)")
            }
        }
    }

    private static func cursorPosition(for selection: LSPRange?) -> CursorPosition {
        guard let selection else { return CursorPosition(line: 1, column: 1) }
        let start = CursorPosition.Position(line: selection.start.line + 1, column: selection.start.character + 1)
        guard !selection.isEmpty else { return CursorPosition(start: start, end: nil) }
        let end = CursorPosition.Position(line: selection.end.line + 1, column: selection.end.character + 1)
        return CursorPosition(start: start, end: end)
    }
}
