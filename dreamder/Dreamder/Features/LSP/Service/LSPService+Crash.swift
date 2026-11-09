import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI

extension LSPService {
    func restartServer(_ key: ClientKey) async throws {
        automaticRestarts[key] = 0
        restartTasks.removeValue(forKey: key)?.cancel()
        let documents = languageClients[key]?.openFiles.documents ?? lostDocuments[key] ?? []
        if languageClients[key] != nil {
            try? await stopServer(forLanguage: key.languageId, workspacePath: key.workspacePath)
        }
        let server = try await startServer(for: key.languageId, workspacePath: key.workspacePath)
        await reopen(documents, on: server, key: key)
    }

    private func reopen(_ documents: [CodeFileDocument], on server: LanguageServerType, key: ClientKey) async {
        for document in documents {
            guard let uri = document.languageServerURI else { continue }
            if let fileManager = document.findWorkspace()?.workspaceFileManager {
                watchFiles(of: fileManager, key: key, client: server)
            }
            openDocumentURIs[key, default: []].insert(uri)
            try? await server.openDocument(document)
        }
    }

    // MARK: - Crash Handling

    func watchTermination(of server: LanguageServerType, key: ClientKey) {
        terminationTasks[key]?.cancel()
        terminationTasks[key] = Task { [weak self] in
            for await _ in server.terminationEvents {}
            guard !Task.isCancelled else { return }
            self?.serverTerminated(server, key: key)
        }
    }

    func serverTerminated(_ server: LanguageServerType, key: ClientKey) {
        guard languageClients[key] === server, !intentionalStops.contains(key) else { return }
        let documents = server.openFiles.documents
        discardWorkDoneProgress(of: server, key: key)
        languageClients.removeValue(forKey: key)
        openDocumentURIs.removeValue(forKey: key)
        stopListeningToEvents(for: key)
        terminationTasks.removeValue(forKey: key)
        stopWatchingFiles(for: key)
        LSPDiagnosticsPublisher.clear(documentsAtURIs: server.openFiles.uris, workspacePath: key.workspacePath)
        let name = server.serverInfo?.name ?? key.languageId.rawValue
        serverStates[key] = .failed("The \(name) language server terminated unexpectedly")
        logger.error("Language server \(key.languageId.rawValue, privacy: .public) terminated unexpectedly")

        let attempts = automaticRestarts[key, default: 0]
        guard attempts < Self.maximumAutomaticRestarts else {
            lostDocuments[key] = documents
            notifyServerCrashed(name: name)
            return
        }
        automaticRestarts[key] = attempts + 1
        restartTasks[key] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.dependencies.restartBackoff)
            guard !Task.isCancelled, self.languageClients[key] == nil else { return }
            await self.performAutomaticRestart(key, documents: documents, name: name)
        }
    }

    private func performAutomaticRestart(_ key: ClientKey, documents: [CodeFileDocument], name: String) async {
        do {
            let server = try await startServer(for: key.languageId, workspacePath: key.workspacePath)
            await reopen(documents, on: server, key: key)
            restartTasks.removeValue(forKey: key)
        } catch {
            restartTasks.removeValue(forKey: key)
            lostDocuments[key] = documents
            notifyServerCrashed(name: name)
        }
    }

    func waitForAutomaticRestarts() async {
        for task in Array(restartTasks.values) {
            await task.value
        }
    }

    func notifyToInstallLanguageServer(language: LSPLanguage) {
        guard notifiedMissingLanguages.insert(language).inserted else { return }
        let title = "Install \(language.rawValue.capitalized) Language Server"
        let notifications = dependencies.notifications()
        guard !notifications.notifications.contains(where: { $0.title == title }) else { return }
        let openSettings = dependencies.openSettings
        notifications.post(
            iconSymbol: "arrow.down.circle",
            title: title,
            description: "Install the \(language.rawValue.capitalized) language server to enable code intelligence "
                + "features, or set its path in Settings.",
            actionButtonTitle: "Open Settings"
        ) {
            Task { @MainActor in openSettings() }
        }
    }

    private func notifyServerCrashed(name: String) {
        let openSettings = dependencies.openSettings
        dependencies.notifications().post(
            iconSymbol: "exclamationmark.triangle",
            title: "Language server stopped",
            description: "The \(name) language server terminated unexpectedly. Restart it from Language Services.",
            actionButtonTitle: "Open Settings"
        ) {
            Task { @MainActor in openSettings() }
        }
    }
}
