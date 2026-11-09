import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI

extension LSPService {
    // MARK: - Document Management

    /// Notify all relevant language clients that a document was opened. A second open of a document that is already
    /// open (an external reload) is sent as a full-text change.
    /// - Note: Must be invoked after the contents of the file are available.
    /// - Parameter document: The code document that was opened.
    func openDocument(_ document: CodeFileDocument) {
        guard let workspace = document.findWorkspace(),
              let workspacePath = workspace.fileURL?.absolutePath,
              let lspLanguage = document.getLanguage().lspLanguage,
              let uri = document.languageServerURI else {
            return
        }
        let key = ClientKey(lspLanguage, workspacePath)
        let isReload = openDocumentURIs[key]?.contains(uri) ?? false
        openDocumentURIs[key, default: []].insert(uri)
        let fileManager = workspace.workspaceFileManager
        enqueueDocumentOperation(uri: uri) {
            let languageServer: LanguageServerType
            do {
                if let server = self.languageClients[key] {
                    languageServer = server
                } else {
                    languageServer = try await self.startServer(for: lspLanguage, workspacePath: workspacePath)
                }
            } catch {
                self.openDocumentURIs[key]?.remove(uri)
                // swiftlint:disable:next line_length
                self.logger.error("Failed to find/start server for language: \(lspLanguage.rawValue), workspace: \(workspacePath, privacy: .private)")
                return
            }
            if let fileManager {
                self.watchFiles(of: fileManager, key: key, client: languageServer)
            }
            do {
                if isReload, languageServer.openFiles.document(for: uri) != nil {
                    try await languageServer.reloadDocument(document)
                } else {
                    try await languageServer.openDocument(document)
                }
            } catch {
                // swiftlint:disable:next line_length
                self.logger.error("Failed to open document: \(uri, privacy: .private), language: \(lspLanguage.rawValue). Error \(error)")
            }
        }
    }

    /// Notify all relevant language clients that a document was closed.
    /// - Parameter url: The url of the document that was closed
    func closeDocument(_ url: URL) {
        let uri = url.lspURI
        for key in Array(openDocumentURIs.keys) {
            openDocumentURIs[key]?.remove(uri)
        }
        for key in Array(lostDocuments.keys) {
            lostDocuments[key]?.removeAll { $0.languageServerURI == uri }
        }
        enqueueDocumentOperation(uri: uri) {
            guard let languageClient = self.languageClient(forDocument: url) else { return }
            LSPDiagnosticsPublisher.clear(uri)
            do {
                try await languageClient.closeDocument(uri)
            } catch {
                // swiftlint:disable:next line_length
                self.logger.error("Failed to close document: \(uri, privacy: .private), language: \(languageClient.languageId.rawValue). Error \(error)")
            }
        }
    }

    private func enqueueDocumentOperation(uri: String, _ operation: @escaping @MainActor () async -> Void) {
        let previous = documentOperations[uri]
        documentOperations[uri] = Task {
            await previous?.value
            await operation()
        }
    }

    func waitForDocumentOperations() async {
        for task in Array(documentOperations.values) {
            await task.value
        }
    }

    // MARK: - Watched Files

    func watchFiles(of fileManager: CEWorkspaceFileManager, key: ClientKey, client: LanguageServerType) {
        guard watchedFilesForwarders[key] == nil else { return }
        let forwarder = LSPWatchedFilesForwarder(
            fileManager: fileManager,
            workspacePath: key.workspacePath,
            watchers: { [weak client] in
                Self.registeredWatchers(of: client)
            },
            send: { [weak client] params in
                await Self.sendWatchedFileChanges(params, to: client)
            }
        )
        watchedFilesForwarders[key] = forwarder
        forwarder.start()
    }

    static func registeredWatchers(of client: LanguageServerType?) -> [FileSystemWatcher] {
        client?.dynamicCapabilities
            .registerOptions(for: watchedFilesMethod, as: DidChangeWatchedFilesRegistrationOptions.self)
            .flatMap(\.watchers) ?? []
    }

    static func sendWatchedFileChanges(_ params: DidChangeWatchedFilesParams, to client: LanguageServerType?) async {
        guard let client else { return }
        try? await client.lspInstance.workspaceDidChangeWatchedFiles(params)
    }

    func stopWatchingFiles(for key: ClientKey) {
        watchedFilesForwarders.removeValue(forKey: key)?.stop()
    }

    func watchedFilesForwarder(for key: ClientKey) -> LSPWatchedFilesForwarder? {
        watchedFilesForwarders[key]
    }
}
