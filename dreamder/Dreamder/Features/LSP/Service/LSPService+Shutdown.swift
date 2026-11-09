import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI

extension LSPService {
    // MARK: - Close Workspace

    /// Close all language clients for a workspace.
    ///
    /// This is intentionally synchronous so we can exit from the workspace document's ``WorkspaceDocument/close()``
    /// method ASAP.
    ///
    /// Errors thrown in this method are logged and otherwise not handled.
    /// - Parameter workspacePath: The path of the workspace.
    func closeWorkspace(_ workspacePath: String) {
        for key in restartTasks.keys where key.workspacePath == workspacePath {
            restartTasks.removeValue(forKey: key)?.cancel()
        }
        for key in serverStates.keys where key.workspacePath == workspacePath && startTasks[key] == nil {
            serverStates.removeValue(forKey: key)
        }
        for key in lostDocuments.keys where key.workspacePath == workspacePath {
            lostDocuments.removeValue(forKey: key)
        }
        for key in automaticRestarts.keys where key.workspacePath == workspacePath {
            automaticRestarts.removeValue(forKey: key)
        }
        let closing = languageClients.filter { $0.key.workspacePath == workspacePath }
        for (key, client) in closing {
            languageClients.removeValue(forKey: key)
            openDocumentURIs.removeValue(forKey: key)
            terminationTasks.removeValue(forKey: key)?.cancel()
            stopListeningToEvents(for: key)
            stopWatchingFiles(for: key)
            discardWorkDoneProgress(of: client, key: key)
            LSPDiagnosticsPublisher.clear(documentsAtURIs: client.openFiles.uris, workspacePath: key.workspacePath)
        }
        Task {
            for (key, languageClient) in closing {
                do {
                    try await languageClient.shutdown()
                } catch {
                    logger.error("Failed to shutdown \(key.languageId.rawValue) Language Server: Error \(error)")
                }
            }
        }
    }

    // MARK: - Stop Servers

    /// Attempts to stop a running language server. Throws an error if the server is not found
    /// or if the language server throws an error while trying to shutdown.
    /// - Parameters:
    ///   - languageId: The ID of the language server to stop.
    ///   - workspacePath: The path of the workspace to stop the language server for.
    func stopServer(forLanguage languageId: LSPLanguage, workspacePath: String) async throws {
        let key = ClientKey(languageId, workspacePath)
        guard let languageClient = languageClients[key] else {
            logger.error("Server not found for language \(languageId.rawValue) during stop operation")
            throw LSPServiceError.serverNotFound
        }
        intentionalStops.insert(key)
        defer { intentionalStops.remove(key) }
        restartTasks.removeValue(forKey: key)?.cancel()
        discardWorkDoneProgress(of: languageClient, key: key)
        do {
            try await languageClient.shutdown()
        } catch {
            logger.error("Failed to stop server for language \(languageId.rawValue): \(error.localizedDescription)")
            throw error
        }
        guard languageClients[key] === languageClient else { return }
        let openURIs = languageClient.openFiles.uris
        languageClients.removeValue(forKey: key)
        openDocumentURIs.removeValue(forKey: key)
        serverStates[key] = .stopped
        logger.info("Server stopped for language \(languageId.rawValue)")

        terminationTasks.removeValue(forKey: key)?.cancel()
        stopListeningToEvents(for: key)
        stopWatchingFiles(for: key)
        LSPDiagnosticsPublisher.clear(documentsAtURIs: openURIs, workspacePath: key.workspacePath)
    }

    /// Goes through all active language servers and attempts to shut them down.
    func stopAllServers() async {
        intentionalStops.formUnion(languageClients.keys)
        for task in restartTasks.values {
            task.cancel()
        }
        restartTasks.removeAll()
        for (key, server) in languageClients {
            discardWorkDoneProgress(of: server, key: key)
        }
        await withTaskGroup(of: Void.self) { group in
            for (key, server) in languageClients {
                group.addTask {
                    do {
                        try await server.shutdown()
                    } catch {
                        self.logger.warning("Shutting down \(key.languageId.rawValue): Error \(error)")
                    }
                }
            }
        }
        for (key, server) in languageClients {
            LSPDiagnosticsPublisher.clear(documentsAtURIs: server.openFiles.uris, workspacePath: key.workspacePath)
        }
        for key in languageClients.keys {
            serverStates[key] = .stopped
            stopWatchingFiles(for: key)
        }
        languageClients.removeAll()
        openDocumentURIs.removeAll()
        intentionalStops.removeAll()
        for task in terminationTasks.values {
            task.cancel()
        }
        terminationTasks.removeAll()
        eventListeningTasks.forEach { (_, value) in
            value.cancel()
        }
        eventListeningTasks.removeAll()
    }

    /// Call this when a server is refusing to terminate itself. Sends the `SIGKILL` signal to all lsp processes.
    func killAllServers() {
        for (_, server) in languageClients {
            kill(server.pid, SIGKILL)
        }
    }
}
