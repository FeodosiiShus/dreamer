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
/// let lspService = LSPService.shared
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
@Observable
final class LSPService {
    typealias LanguageServerType = LanguageServer<CodeFileDocument>

    static let restartBackoff: Duration = .seconds(2)
    static let maximumAutomaticRestarts = 1
    static let watchedFilesMethod = "workspace/didChangeWatchedFiles"
    static let shared = LSPService()

    struct Dependencies {
        var createServer: @MainActor (LSPLanguage, LanguageServerBinary, String) async throws -> LanguageServerType
        var discoverBinary: @MainActor (LSPLanguage, String) async -> LanguageServerBinary?
        var restartBackoff: Duration
        var observesDocumentNotifications: Bool
        var notifications: @MainActor () -> NotificationManager
        var openSettings: @MainActor () -> Void
        var runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse = { alert in
            DreamderHeadless.isEnabled ? .abort : alert.runModal()
        }
        var openExternalURL: @MainActor (URL) -> Bool = { url in
            DreamderHeadless.isEnabled ? false : NSWorkspace.shared.open(url)
        }
        var postTask: @MainActor (URL, TaskNotificationHandler.Action, TaskNotificationModel) -> Void = {
            workspaceURL, action, model in
            TaskNotificationHandler.postTask(toWorkspace: workspaceURL, action: action, model: model)
        }

        static var live: Dependencies {
            Dependencies(
                createServer: { language, binary, workspacePath in
                    try await LanguageServerType.createServer(for: language, with: binary, workspacePath: workspacePath)
                },
                discoverBinary: { language, workspacePath in
                    let registry = RegistryManager.shared
                    let disabledPackages = Set(
                        registry.installedLanguageServers.values.filter { !$0.isEnabled }.map(\.packageName)
                    )
                    return await LanguageServerDiscovery.binary(
                        for: language,
                        workspacePath: workspacePath,
                        registryInstallPath: registry.installPath.path,
                        disabledRegistryPackages: disabledPackages
                    )
                },
                restartBackoff: LSPService.restartBackoff,
                observesDocumentNotifications: true,
                notifications: { NotificationManager.shared },
                openSettings: { (NSApp.delegate as? AppDelegate)?.openWindow(sceneID: .settings) }
            )
        }
    }

    let logger: Logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "LSPService")

    struct ClientKey: Hashable, Equatable {
        let languageId: LSPLanguage
        let workspacePath: String

        init(_ languageId: LSPLanguage, _ workspacePath: String) {
            self.languageId = languageId.serverFamily
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
    var languageClients: [ClientKey: LanguageServerType] = [:]
    var serverStates: [ClientKey: ServerState] = [:]
    /// Holds the language server configurations the user configured explicitly
    var languageConfigs: [LSPLanguage: LanguageServerBinary] = [:]
    /// Holds all the event listeners for each active language client
    @ObservationIgnored
    var eventListeningTasks: [ClientKey: Task<Void, Never>] = [:]

    private(set) var openDocumentURIs: [ClientKey: Set<String>] = [:]

    @ObservationIgnored
    private var startTasks: [ClientKey: Task<LanguageServerType, Error>] = [:]
    @ObservationIgnored
    private var terminationTasks: [ClientKey: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var restartTasks: [ClientKey: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var intentionalStops: Set<ClientKey> = []
    @ObservationIgnored
    private var automaticRestarts: [ClientKey: Int] = [:]
    @ObservationIgnored
    private var documentOperations: [String: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var watchedFilesForwarders: [ClientKey: LSPWatchedFilesForwarder] = [:]
    @ObservationIgnored
    private var notifiedMissingLanguages: Set<LSPLanguage> = []
    @ObservationIgnored
    private var notificationObservers: [any NSObjectProtocol] = []

    @ObservationIgnored
    let dependencies: Dependencies

    private let settings: Settings

    private var lspBinaries: [String: String] {
        settings.preferences.developerSettings.lspBinaries
    }

    init(dependencies: Dependencies = .forHost(), settings: Settings = .shared) {
        self.dependencies = dependencies
        self.settings = settings
        loadConfiguredBinaries()

        guard dependencies.observesDocumentNotifications else { return }
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didOpenNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let document = notification.object as? CodeFileDocument else { return }
            MainActor.assumeIsolated {
                self?.openDocument(document)
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: CodeFileDocument.didCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let url = notification.object as? URL else { return }
            MainActor.assumeIsolated {
                self?.closeDocument(url)
            }
        })
    }

    isolated deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Gets the language server for the specified language and workspace.
    func server(for languageId: LSPLanguage, workspacePath: String) -> InitializingServer? {
        return languageClients[ClientKey(languageId, workspacePath)]?.lspInstance
    }

    private func loadConfiguredBinaries() {
        for (languageKey, path) in lspBinaries {
            let language = LSPLanguage(rawValue: languageKey)
            guard LSPLanguage.known.contains(language) else { continue }
            languageConfigs[language.serverFamily] = configuredBinary(for: path)
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

    private func resolveServerBinary(for languageId: LSPLanguage, workspacePath: String) async -> LanguageServerBinary? {
        if let configured = configuredBinaryFromSettings(for: languageId) {
            languageConfigs[languageId] = configured
            return configured
        }
        if let existing = languageConfigs[languageId] {
            return existing
        }
        guard let discovered = await dependencies.discoverBinary(languageId, workspacePath) else {
            return nil
        }
        logger.info("Discovered language server for \(languageId.rawValue): \(discovered.execPath, privacy: .public)")
        return discovered
    }

    private func configuredBinaryFromSettings(for languageId: LSPLanguage) -> LanguageServerBinary? {
        for candidate in [languageId] + languageId.familyMembers {
            if let path = lspBinaries[candidate.rawValue], !path.isEmpty {
                return configuredBinary(for: path)
            }
        }
        return nil
    }

    /// Gets the language client for the specified language
    func languageClient(for languageId: LSPLanguage, workspacePath: String) -> LanguageServerType? {
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
        for languageId: LSPLanguage,
        workspacePath: String
    ) async throws -> LanguageServerType {
        let key = ClientKey(languageId, workspacePath)
        if let existing = languageClients[key] {
            return existing
        }
        if let pending = startTasks[key] {
            return try await pending.value
        }
        let task = Task { try await self.launchServer(for: key) }
        startTasks[key] = task
        defer { startTasks[key] = nil }
        return try await task.value
    }

    private func launchServer(for key: ClientKey) async throws -> LanguageServerType {
        let languageId = key.languageId
        serverStates[key] = .starting
        guard let serverBinary = await resolveServerBinary(for: languageId, workspacePath: key.workspacePath) else {
            logger.error("Couldn't find language sever binary for \(languageId.rawValue)")
            serverStates[key] = .failed("No language server found for \(languageId.rawValue)")
            notifyToInstallLanguageServer(language: languageId)
            throw LSPError.binaryNotFound
        }

        logger.info("Starting \(languageId.rawValue) language server")
        let server: LanguageServerType
        do {
            server = try await dependencies.createServer(languageId, serverBinary, key.workspacePath)
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
        watchTermination(of: server, key: key)
        return server
    }

    func restartServer(_ key: ClientKey) async throws {
        automaticRestarts[key] = 0
        restartTasks.removeValue(forKey: key)?.cancel()
        let documents = languageClients[key]?.openFiles.documents ?? []
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

    private func watchTermination(of server: LanguageServerType, key: ClientKey) {
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
            notifyServerCrashed(name: name)
        }
    }

    func waitForAutomaticRestarts() async {
        for task in Array(restartTasks.values) {
            await task.value
        }
    }

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

    private func watchFiles(of fileManager: CEWorkspaceFileManager, key: ClientKey, client: LanguageServerType) {
        guard watchedFilesForwarders[key] == nil else { return }
        let forwarder = LSPWatchedFilesForwarder(
            fileManager: fileManager,
            workspacePath: key.workspacePath,
            watchers: { [weak client] in
                client?.dynamicCapabilities
                    .registerOptions(for: Self.watchedFilesMethod, as: DidChangeWatchedFilesRegistrationOptions.self)
                    .flatMap(\.watchers) ?? []
            },
            send: { [weak client] params in
                guard let client else { return }
                try? await client.lspInstance.workspaceDidChangeWatchedFiles(params)
            }
        )
        watchedFilesForwarders[key] = forwarder
        forwarder.start()
    }

    private func stopWatchingFiles(for key: ClientKey) {
        watchedFilesForwarders.removeValue(forKey: key)?.stop()
    }

    func watchedFilesForwarder(for key: ClientKey) -> LSPWatchedFilesForwarder? {
        watchedFilesForwarders[key]
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
        let clientKeys = self.languageClients.filter({ $0.key.workspacePath == workspacePath })
        intentionalStops.formUnion(clientKeys.keys)
        for (key, client) in clientKeys {
            restartTasks.removeValue(forKey: key)?.cancel()
            stopWatchingFiles(for: key)
            discardWorkDoneProgress(of: client, key: key)
        }
        Task {
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
                self.openDocumentURIs.removeValue(forKey: key)
                self.terminationTasks.removeValue(forKey: key)?.cancel()
                self.intentionalStops.remove(key)
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

extension LSPService {
    private func notifyToInstallLanguageServer(language: LSPLanguage) {
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

// MARK: - Errors

enum ServerManagerError: Error {
    case serverNotFound
    case serverStartFailed
    case serverStopFailed
    case languageClientNotFound
}
