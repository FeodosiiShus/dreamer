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

        // Create a new Task to listen to the events
        let task = Task.detached { [weak self] in
            for await event in languageClient.lspInstance.eventSequence {
                await self?.handleEvent(event, for: key)
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
            return
        }

        switch event {
        case let .request(_, request):
            handleRequest(request, client: client)
        case let .notification(notification):
            handleNotification(notification, client: client, key: key)
        case let .error(error):
            logger.warning("Error from server \(key.languageId.rawValue, privacy: .public): \(error)")
        }
    }

    private func handleRequest(_ request: ServerRequest, client: LanguageServerType) {
        // TODO: Handle Requests
        switch request {
            //        case let .workspaceConfiguration(params, _):
            //            print("workspaceConfiguration: \(params)")
            //        case let .workspaceFolders(handler):
            //            print("workspaceFolders: \(String(describing: handler))")
            //        case let .workspaceApplyEdit(params, _):
            //            print("workspaceApplyEdit: \(params)")
//        case let .clientRegisterCapability(params, _):
//            print("clientRegisterCapability: \(params)")
//        case let .clientUnregisterCapability(params, _):
//            print("clientUnregisterCapability: \(params)")
            //        case let .workspaceCodeLensRefresh(handler):
            //            print("workspaceCodeLensRefresh: \(String(describing: handler))")
//        case let .workspaceSemanticTokenRefresh(handler):
//            print("Refresh semantic tokens!", handler)
            //        case let .windowShowMessageRequest(params, _):
            //            print("windowShowMessageRequest: \(params)")
            //        case let .windowShowDocument(params, _):
            //            print("windowShowDocument: \(params)")
            //        case let .windowWorkDoneProgressCreate(params, _):
            //            print("windowWorkDoneProgressCreate: \(params)")
        default:
            return
        }
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
        default:
            return
        }
    }
}
