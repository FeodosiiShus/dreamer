//
//  LSPService+Events.swift
//  Dreamder
//
//  Created by Abe Malla on 6/1/24.
//

import Foundation
import LanguageClient
import LanguageServerProtocol

extension LSPService {
    func startListeningToEvents(for key: ClientKey) {
        guard let languageClient = languageClients[key] else {
            logger.error("Language client not found for \(key.languageId.rawValue)")
            return
        }

        let events = languageClient.lspInstance.eventSequence
        eventListeningTasks[key]?.cancel()
        let task = Task { [weak self] in
            for await event in events {
                guard !Task.isCancelled else { return }
                self?.handleEvent(event, for: key)
            }
        }
        eventListeningTasks[key] = task
    }

    func stopListeningToEvents(for key: ClientKey) {
        if let task = eventListeningTasks[key] {
            task.cancel()
            eventListeningTasks.removeValue(forKey: key)
        }
    }

    private func handleEvent(_ event: ServerEvent, for key: ClientKey) {
        guard let client = languageClient(for: key.languageId, workspacePath: key.workspacePath) else {
            if case let .request(_, request) = event {
                let message = "The \(key.languageId.rawValue) language client is not running"
                Task { await LSPClientRequestHandler.reject(request, message: message) }
            }
            return
        }

        switch event {
        case let .request(_, request):
            handleRequest(request, client: client, key: key)
        case let .notification(notification):
            handleNotification(notification, client: client, key: key)
        case let .error(error):
            logger.warning("Error from server \(key.languageId.rawValue, privacy: .public): \(error)")
        }
    }

    private func handleRequest(_ request: ServerRequest, client: LanguageServerType, key: ClientKey) {
        let handler = makeClientRequestHandler(for: key, client: client)
        Task { await handler.handle(request) }
    }

    private func handleNotification(
        _ notification: ServerNotification,
        client: LanguageServerType,
        key: ClientKey
    ) {
        switch notification {
        case let .windowLogMessage(message):
            client.logContainer.appendLog(message)
        case let .textDocumentPublishDiagnostics(params):
            LSPDiagnosticsPublisher.publish(
                params.diagnostics,
                forDocument: params.uri,
                workspacePath: key.workspacePath
            )
        case let .protocolProgress(params):
            client.workDoneProgress.apply(params)
        default:
            return
        }
    }
}
