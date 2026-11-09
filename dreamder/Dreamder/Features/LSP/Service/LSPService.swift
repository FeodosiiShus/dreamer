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

    let logger: Logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "LSPService")

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
    @ObservationIgnored var eventListeningTasks: [ClientKey: Task<Void, Never>] = [:]

    var openDocumentURIs: [ClientKey: Set<String>] = [:]

    @ObservationIgnored var startTasks: [ClientKey: Task<LanguageServerType, Error>] = [:]
    @ObservationIgnored var terminationTasks: [ClientKey: Task<Void, Never>] = [:]
    @ObservationIgnored var restartTasks: [ClientKey: Task<Void, Never>] = [:]
    @ObservationIgnored var intentionalStops: Set<ClientKey> = []
    @ObservationIgnored var automaticRestarts: [ClientKey: Int] = [:]
    @ObservationIgnored var lostDocuments: [ClientKey: [CodeFileDocument]] = [:]
    @ObservationIgnored var documentOperations: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var watchedFilesForwarders: [ClientKey: LSPWatchedFilesForwarder] = [:]
    @ObservationIgnored var notifiedMissingLanguages: Set<LSPLanguage> = []
    @ObservationIgnored private var notificationObservers: [any NSObjectProtocol] = []

    @ObservationIgnored let dependencies: Dependencies

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

    private func resolveServerBinary(
        for languageId: LSPLanguage,
        workspacePath: String
    ) async -> LanguageServerBinary? {
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
        lostDocuments.removeValue(forKey: key)
        serverStates[key] = .running
        logger.info("Successfully started \(languageId.rawValue) language server")

        self.startListeningToEvents(for: key)
        watchTermination(of: server, key: key)
        return server
    }
}

// MARK: - Errors

enum ServerManagerError: Error {
    case serverNotFound
    case serverStartFailed
    case serverStopFailed
    case languageClientNotFound
}
