import AppKit
import CodeEditSourceEditor
import CodeEditTextView
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
        guard let client = languageClients[key] else {
            return ApplyWorkspaceEditResult(applied: false, failureReason: "The language server is not running")
        }
        return await applyWorkspaceEdit(params.edit, via: client)
    }

    func applyWorkspaceEdit(_ edit: WorkspaceEdit, via client: LanguageServerType) async -> ApplyWorkspaceEditResult {
        await WorkspaceEditApplier(client: client).apply(edit)
    }

    func showDocument(_ params: ShowDocumentParams, for key: ClientKey) -> Bool {
        switch LSPShowDocumentPlan.make(for: params) {
        case let .external(url):
            return dependencies.openExternalURL(url)
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
        guard let actions = params.actions, !actions.isEmpty else {
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
        let response = dependencies.runAlert(alert)
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
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
        case .inlayHint:
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
        await WorkspaceDiagnosticsPuller.shared.pull(client: client, key: key)
    }

    private static func cursorPosition(for selection: LSPRange?) -> CursorPosition {
        guard let selection else { return CursorPosition(line: 1, column: 1) }
        let start = CursorPosition.Position(line: selection.start.line + 1, column: selection.start.character + 1)
        guard !selection.isEmpty else { return CursorPosition(start: start, end: nil) }
        let end = CursorPosition.Position(line: selection.end.line + 1, column: selection.end.character + 1)
        return CursorPosition(start: start, end: end)
    }
}

final class WorkspaceEditApplier {
    typealias Client = LSPService.LanguageServerType
    typealias OpenDocuments = @MainActor () -> [CodeFileDocument]

    private let client: Client
    private let trashItem: LSPWorkspaceEditExecutor.TrashHandler
    private let openDocuments: OpenDocuments

    init(
        client: Client,
        trashItem: @escaping LSPWorkspaceEditExecutor.TrashHandler = LSPWorkspaceEditExecutor.trashWithFileManager,
        openDocuments: @escaping OpenDocuments = WorkspaceEditApplier.registeredDocuments
    ) {
        self.client = client
        self.trashItem = trashItem
        self.openDocuments = openDocuments
    }

    static func registeredDocuments() -> [CodeFileDocument] {
        DreamderDocumentController.shared.documents.compactMap { $0 as? CodeFileDocument }
    }

    func apply(_ edit: WorkspaceEdit) async -> ApplyWorkspaceEditResult {
        let executor = LSPWorkspaceEditExecutor(
            workspaceRoot: client.rootPath,
            trashItem: trashItem,
            editOpenDocuments: { [self] requests in
                await editOpenDocuments(requests)
            }
        )
        return await executor.apply(edit)
    }

    func editOpenDocuments(_ requests: [LSPOpenDocumentEdit]) async -> [LSPOpenDocumentOutcome] {
        var simulatedTexts: [ObjectIdentifier: String] = [:]
        var plans: [OpenDocumentPlan?] = []
        for request in requests {
            do {
                plans.append(try plan(request, validatesCurrentState: true, simulatedTexts: &simulatedTexts))
            } catch {
                return requests.map { $0.index == request.index ? .failed(error) : .notOpen }
            }
        }
        let syncs = plans.compactMap { $0 }.compactMap { applyNow($0) }
        for sync in syncs {
            await notifyServer(sync)
        }
        return plans.map { $0 == nil ? .notOpen : .handled }
    }

    func editOpenDocument(uri: String, edits: [TextEdit]) async throws -> Bool {
        var simulatedTexts: [ObjectIdentifier: String] = [:]
        let request = LSPOpenDocumentEdit(index: 0, uri: uri, edits: edits, version: nil)
        guard let prepared = try plan(request, validatesCurrentState: false, simulatedTexts: &simulatedTexts) else {
            return false
        }
        if let sync = applyNow(prepared) {
            await notifyServer(sync)
        }
        return true
    }

    private struct OpenDocumentPlan {
        let document: CodeFileDocument
        let storage: NSTextStorage
        let trackedKey: String?
        let resolved: [LSPResolvedTextEdit]
    }

    private struct ServerSync {
        let key: String
        let changes: [Client.DocumentChange]
    }

    private func plan(
        _ request: LSPOpenDocumentEdit,
        validatesCurrentState: Bool,
        simulatedTexts: inout [ObjectIdentifier: String]
    ) throws -> OpenDocumentPlan? {
        let tracked = trackedDocument(for: request.uri)
        guard let document = tracked?.document ?? untrackedDocument(for: request.uri),
              let storage = document.content else {
            return nil
        }
        if validatesCurrentState, let tracked {
            try validate(tracked, request: request)
        }
        let identifier = ObjectIdentifier(document)
        let text = simulatedTexts[identifier] ?? storage.string
        let resolved = try LSPTextEditApplier.resolve(request.edits, in: text)
        simulatedTexts[identifier] = try LSPTextEditApplier.apply(request.edits, to: text)
        return OpenDocumentPlan(document: document, storage: storage, trackedKey: tracked?.key, resolved: resolved)
    }

    private func validate(_ tracked: (document: CodeFileDocument, key: String), request: LSPOpenDocumentEdit) throws {
        if let version = request.version, version != client.openFiles.documentVersion(for: tracked.key) {
            throw LSPWorkspaceEditError.staleDocument(request.uri)
        }
        if tracked.document.languageServerObjects.textCoordinator.hasPendingChanges {
            throw LSPWorkspaceEditError.unsyncedLocalEdits(request.uri)
        }
    }

    private func applyNow(_ plan: OpenDocumentPlan) -> ServerSync? {
        if let textView = plan.document.attachedTextView, textView.textStorage === plan.storage, textView.isEditable {
            Self.apply(plan.resolved, to: textView)
            return nil
        }
        plan.storage.beginEditing()
        for item in plan.resolved.reversed() {
            plan.storage.replaceCharacters(in: item.range, with: item.edit.newText)
        }
        plan.storage.endEditing()
        plan.document.updateChangeCount(.changeDone)
        guard let key = plan.trackedKey else { return nil }
        let changes = plan.resolved.reversed().map {
            Client.DocumentChange(replacingContentsIn: $0.edit.range, with: $0.edit.newText)
        }
        return ServerSync(key: key, changes: changes)
    }

    private func notifyServer(_ sync: ServerSync) async {
        do {
            try await client.documentChanged(uri: sync.key, changes: sync.changes)
        } catch {
            client.logger.warning("Failed to sync workspace edit for \(sync.key, privacy: .private): \(error)")
        }
    }

    private func trackedDocument(for uri: String) -> (document: CodeFileDocument, key: String)? {
        let keys = [uri, LSPFileURI.fileURL(from: uri)?.lspURI].compactMap { $0 }
        for key in keys {
            if let document = client.openFiles.document(for: key) {
                return (document, key)
            }
        }
        return nil
    }

    private func untrackedDocument(for uri: String) -> CodeFileDocument? {
        guard let url = LSPFileURI.fileURL(from: uri) else { return nil }
        let target = url.resolvingSymlinksInPath()
        return openDocuments().first { $0.fileURL?.resolvingSymlinksInPath() == target }
    }

    static func apply(_ resolved: [LSPResolvedTextEdit], to textView: TextView) {
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        for item in resolved.reversed() {
            textView.replaceCharacters(in: item.range, with: item.edit.newText)
        }
        undoManager?.endUndoGrouping()
    }
}
