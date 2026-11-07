//
//  LSPService.swift
//  Dreamder
//
//  Created by Abe Malla on 2/7/24.
//

import os.log
import JSONRPC
import SwiftUI
import Foundation
import LanguageClient
import LanguageServerProtocol
import CodeEditLanguages

/// `LSPService` is a service class responsible for managing the lifecycle and event handling
/// of Language Server Protocol (LSP) clients within the Dreamder application. It handles the initialization,
/// communication, and termination of language servers, ensuring that code assistance features
/// such as code completion, diagnostics, and more are available for various programming languages.
///
/// This class uses Swift's concurrency model to manage background tasks and event streams
/// efficiently. Each language server runs in its own asynchronous task, listening for events and
/// handling them as they occur. The `LSPService` class also provides functionality to start
/// and stop individual language servers, as well as to stop all running servers.
///
/// ## Example Usage
///
/// ```swift
/// @Service var lspService
///
/// try await lspService.startServer(
///    for: .python,
///    projectURL: projectURL,
///    workspaceFolders: workspaceFolders
/// )
/// try await lspService.stopServer(for: .python)
/// ```
///
/// ## Completion Example
///
/// ```swift
/// func testCompletion() async throws {
///     do {
///         guard var languageClient = self.languageClient(for: .python) else {
///             print("Failed to get client")
///             throw LSPServiceError.languageClientNotFound
///         }
///
///         let testFilePathStr = ""
///         let testFileURL = URL(fileURLWithPath: testFilePathStr)
///
///         // Tell server we opened a document
///         _ = await languageClient.addDocument(testFileURL)
///
///         // Completion example
///         let textPosition = Position(line: 32, character: 18)  // Lines and characters start at 0
///         let completions = try await languageClient.requestCompletion(
///             document: testFileURL.lspURI,
///             position: textPosition
///         )
///         switch completions {
///         case .optionA(let completionItems):
///             // Handle the case where completions is an array of CompletionItem
///             print("\n*******\nCompletion Items:\n*******\n")
///             for item in completionItems {
///                 let textEdits = LSPCompletionItemsUtil.getCompletionItemEdits(
///                     startPosition: textPosition,
///                     item: item
///                 )
///                 for edit in textEdits {
///                     print(edit)
///                 }
///             }
///
///         case .optionB(let completionList):
///             // Handle the case where completions is a CompletionList
///             print("\n*******\nCompletion Items:\n*******\n")
///             for item in completionList.items {
///                 let textEdits = LSPCompletionItemsUtil.getCompletionItemEdits(
///                     startPosition: textPosition,
///                     item: item
///                 )
///                 for edit in textEdits {
///                     print(edit)
///                 }
///             }
///
///             print(completionList.items[0])
///
///         case .none:
///             print("No completions found")
///         }
///
///         // Close the document
///         _ = await languageClient.closeDocument(testFilePathStr)
///     } catch {
///         print(error)
///     }
/// }
/// ```
@MainActor
final class LSPService: ObservableObject {
    typealias LanguageServerType = LanguageServer<CodeFileDocument>

    let logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "LSPService")

    struct ClientKey: Hashable, Equatable {
        let languageId: LanguageIdentifier
        let workspacePath: String

        init(_ languageId: LanguageIdentifier, _ workspacePath: String) {
            self.languageId = languageId
            self.workspacePath = workspacePath
        }
    }

    enum ServerState: Equatable {
        case starting
        case running
        case failed(String)
        case stopped
    }

    /// Holds the active language clients
    @Published var languageClients: [ClientKey: LanguageServerType] = [:]
    @Published private(set) var serverStates: [ClientKey: ServerState] = [:]
    /// Holds the language server configurations for all the installed language servers
    var languageConfigs: [LanguageIdentifier: LanguageServerBinary] = [:]
    /// Holds all the event listeners for each active language client
    var eventListeningTasks: [ClientKey: Task<Void, Never>] = [:]

    @AppSettings(\.developerSettings.lspBinaries)
    var lspBinaries

    @Environment(\.openWindow)
    private var openWindow

    init() {
        loadConfiguredBinaries()

        NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didOpenNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let document = notification.object as? CodeFileDocument else { return }
            MainActor.assumeIsolated {
                self.openDocument(document)
            }
        }

        NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let url = notification.object as? URL else { return }
            MainActor.assumeIsolated {
                self.closeDocument(url)
            }
        }
    }

    /// Gets the language server for the specified language and workspace.
    func server(for languageId: LanguageIdentifier, workspacePath: String) -> InitializingServer? {
        return languageClients[ClientKey(languageId, workspacePath)]?.lspInstance
    }

    private func loadConfiguredBinaries() {
        for (languageKey, path) in lspBinaries {
            guard let language = LanguageIdentifier(rawValue: languageKey) else { continue }
            languageConfigs[language] = configuredBinary(for: path)
        }
    }

    private func configuredBinary(for path: String) -> LanguageServerBinary {
        let expanded = (path as NSString).expandingTildeInPath
        return LanguageServerBinary(
            execPath: expanded,
            args: LanguageServerDiscovery.arguments(forExecutablePath: expanded),
            env: LSPProcessEnvironment.shared.environment
        )
    }

    private func resolveServerBinary(for languageId: LanguageIdentifier) async -> LanguageServerBinary? {
        if let configured = configuredBinaryFromSettings(for: languageId) {
            languageConfigs[languageId] = configured
            return configured
        }
        if let existing = languageConfigs[languageId] {
            return existing
        }
        guard let discovered = await LanguageServerDiscovery.binary(for: languageId) else {
            return nil
        }
        logger.info("Discovered language server for \(languageId.rawValue): \(discovered.execPath, privacy: .public)")
        languageConfigs[languageId] = discovered
        return discovered
    }

    private func configuredBinaryFromSettings(for languageId: LanguageIdentifier) -> LanguageServerBinary? {
        guard let path = lspBinaries[languageId.rawValue], !path.isEmpty else { return nil }
        return configuredBinary(for: path)
    }

    /// Gets the language client for the specified language
    func languageClient(for languageId: LanguageIdentifier, workspacePath: String) -> LanguageServerType? {
        return languageClients[ClientKey(languageId, workspacePath)]
    }

    func languageClient(forDocument url: URL) -> LanguageServerType? {
        languageClients.values.first(where: { $0.openFiles.document(for: url.lspURI) != nil })
    }

    // MARK: - Start Server

    /// Given a language and workspace path, will attempt to start the language server
    /// - Parameters:
    ///   - languageId: The ID of the language server to start.
    ///   - workspacePath: The workspace this language server is being used in.
    /// - Returns: The new language server.
    func startServer(
        for languageId: LanguageIdentifier,
        workspacePath: String
    ) async throws -> LanguageServerType {
        guard let serverBinary = await resolveServerBinary(for: languageId) else {
            logger.error("Couldn't find language sever binary for \(languageId.rawValue)")
            throw LSPError.binaryNotFound
        }

        let key = ClientKey(languageId, workspacePath)
        logger.info("Starting \(languageId.rawValue) language server")
        serverStates[key] = .starting
        let server: LanguageServerType
        do {
            server = try await LanguageServerType.createServer(
                for: languageId,
                with: serverBinary,
                workspacePath: workspacePath
            )
        } catch {
            let message = String(describing: error)
            logger.error("Failed to start \(languageId.rawValue, privacy: .public): \(message, privacy: .public)")
            serverStates[key] = .failed(message)
            throw error
        }
        languageClients[key] = server
        serverStates[key] = .running
        logger.info("Successfully started \(languageId.rawValue) language server")

        self.startListeningToEvents(for: key)
        return server
    }

    func restartServer(_ key: ClientKey) async throws {
        let documents = languageClients[key]?.openFiles.documents ?? []
        if languageClients[key] != nil {
            try? await stopServer(forLanguage: key.languageId, workspacePath: key.workspacePath)
        }
        let server = try await startServer(for: key.languageId, workspacePath: key.workspacePath)
        for document in documents {
            try? await server.openDocument(document)
        }
    }

    // MARK: - Document Management

    /// Notify all relevant language clients that a document was opened.
    /// - Note: Must be invoked after the contents of the file are available.
    /// - Parameter document: The code document that was opened.
    func openDocument(_ document: CodeFileDocument) {
        guard let workspace = document.findWorkspace(),
              let workspacePath = workspace.fileURL?.absolutePath,
              let lspLanguage = document.getLanguage().lspLanguage else {
            return
        }
        Task {
            let languageServer: LanguageServerType
            do {
                if let server = self.languageClients[ClientKey(lspLanguage, workspacePath)] {
                    languageServer = server
                } else {
                    languageServer = try await self.startServer(for: lspLanguage, workspacePath: workspacePath)
                }
            } catch {
                notifyToInstallLanguageServer(language: lspLanguage)
                // swiftlint:disable:next line_length
                self.logger.error("Failed to find/start server for language: \(lspLanguage.rawValue), workspace: \(workspacePath, privacy: .private)")
                return
            }
            do {
                try await languageServer.openDocument(document)
            } catch {
                let uri = document.languageServerURI
                // swiftlint:disable:next line_length
                self.logger.error("Failed to close document: \(uri ?? "<NO URI>", privacy: .private), language: \(lspLanguage.rawValue). Error \(error)")
            }
        }
    }

    /// Notify all relevant language clients that a document was closed.
    /// - Parameter url: The url of the document that was closed
    func closeDocument(_ url: URL) {
        guard let languageClient = languageClient(forDocument: url) else { return }
        LSPDiagnosticsPublisher.clear(url.lspURI)
        Task {
            do {
                try await languageClient.closeDocument(url.lspURI)
            } catch {
                // swiftlint:disable:next line_length
                logger.error("Failed to close document: \(url.lspURI, privacy: .private), language: \(languageClient.languageId.rawValue). Error \(error)")
            }
        }
    }

    // MARK: - Close Workspace

    /// Close all language clients for a workspace.
    ///
    /// This is intentionally synchronous so we can exit from the workspace document's ``WorkspaceDocument/close()``
    /// method ASAP.
    ///
    /// Errors thrown in this method are logged and otherwise not handled.
    /// - Parameter workspacePath: The path of the workspace.
    func closeWorkspace(_ workspacePath: String) {
        Task {
            let clientKeys = self.languageClients.filter({ $0.key.workspacePath == workspacePath })
            for (key, languageClient) in clientKeys {
                do {
                    try await languageClient.shutdown()
                } catch {
                    logger.error("Failed to shutdown \(key.languageId.rawValue) Language Server: Error \(error)")
                }
            }
            for (key, languageClient) in clientKeys {
                LSPDiagnosticsPublisher.clear(
                    documentsAtURIs: languageClient.openFiles.uris,
                    workspacePath: key.workspacePath
                )
                self.languageClients.removeValue(forKey: key)
                self.serverStates.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Stop Servers

    /// Attempts to stop a running language server. Throws an error if the server is not found
    /// or if the language server throws an error while trying to shutdown.
    /// - Parameters:
    ///   - languageId: The ID of the language server to stop.
    ///   - workspacePath: The path of the workspace to stop the language server for.
    func stopServer(forLanguage languageId: LanguageIdentifier, workspacePath: String) async throws {
        let key = ClientKey(languageId, workspacePath)
        guard let languageClient = languageClients[key] else {
            logger.error("Server not found for language \(languageId.rawValue) during stop operation")
            throw LSPServiceError.serverNotFound
        }
        do {
            try await languageClient.shutdown()
        } catch {
            logger.error("Failed to stop server for language \(languageId.rawValue): \(error.localizedDescription)")
            throw error
        }
        let openURIs = languageClient.openFiles.uris
        languageClients.removeValue(forKey: key)
        serverStates[key] = .stopped
        logger.info("Server stopped for language \(languageId.rawValue)")

        stopListeningToEvents(for: key)
        LSPDiagnosticsPublisher.clear(documentsAtURIs: openURIs, workspacePath: workspacePath)
    }

    /// Goes through all active language servers and attempts to shut them down.
    func stopAllServers() async {
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
        }
        languageClients.removeAll()
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

extension LSPService {
    private func notifyToInstallLanguageServer(language lspLanguage: LanguageIdentifier) {
        // TODO: Re-Enable when this is more fleshed out (don't send duplicate notifications in a session)
        return
        // FIXME: Unreachable code - remove or re-enable when ready
        /*
        let lspLanguageTitle = lspLanguage.rawValue.capitalized
        let notificationTitle = "Install \(lspLanguageTitle) Language Server"
        // Make sure the user doesn't have the same existing notification
        guard !NotificationManager.shared.notifications.contains(where: { $0.title == notificationTitle }) else {
            return
        }

        NotificationManager.shared.post(
            iconSymbol: "arrow.down.circle",
            iconColor: .clear,
            title: notificationTitle,
            description: "Install the \(lspLanguageTitle) language server to enable code intelligence features.",
            actionButtonTitle: "Install"
        ) { [weak self] in
            // TODO: Warning:
            // Accessing Environment<OpenWindowAction>'s value outside of being installed on a View.
            // This will always read the default value and will not update
            self?.openWindow(sceneID: .settings)
        }
        */
    }
}

// MARK: - Errors

enum ServerManagerError: Error {
    case serverNotFound
    case serverStartFailed
    case serverStopFailed
    case languageClientNotFound
}
