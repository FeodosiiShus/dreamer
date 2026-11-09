import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI

extension LSPService {
    func restartServer(_ key: ClientKey) async throws {
        automaticRestarts[key] = 0
        restartTasks.removeValue(forKey: key)?.cancel()
        if let client = languageClients[key] {
            keepPendingDocuments(of: client, key: key)
            try? await stopServer(forLanguage: key.languageId, workspacePath: key.workspacePath)
        }
        _ = try await startServer(for: key.languageId, workspacePath: key.workspacePath)
    }

    private func keepPendingDocuments(of server: LanguageServerType, key: ClientKey) {
        for uri in server.openFiles.uris {
            pendingDocuments[key, default: [:]][uri] = server.openFiles.document(for: uri)
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
        keepPendingDocuments(of: server, key: key)
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
            notifyServerCrashed(name: name)
            return
        }
        automaticRestarts[key] = attempts + 1
        restartTasks[key] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.dependencies.restartBackoff)
            guard !Task.isCancelled, self.languageClients[key] == nil else { return }
            await self.performAutomaticRestart(key, name: name)
        }
    }

    private func performAutomaticRestart(_ key: ClientKey, name: String) async {
        do {
            _ = try await startServer(for: key.languageId, workspacePath: key.workspacePath)
        } catch {
            notifyServerCrashed(name: name)
        }
        restartTasks.removeValue(forKey: key)
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
