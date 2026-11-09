import AppKit
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

enum LSPServiceFixtureError: Error {
    case workspaceUnavailable
}

enum LSPServiceFixtureFailure: Error, CustomStringConvertible {
    case creation
    case shutdown

    var description: String {
        switch self {
        case .creation:
            return "creation failed"
        case .shutdown:
            return "shutdown failed"
        }
    }
}

final class LSPServiceExitSignalingConnection: ServerConnection, Sendable {
    let scripted: ScriptedServerConnection
    private let onExit: @Sendable () -> Void
    private let shutdownError: (any Error)?
    private let shutdownGate: LSPServiceGate?

    var eventSequence: EventSequence {
        scripted.eventSequence
    }

    init(
        scripted: ScriptedServerConnection,
        shutdownError: (any Error)? = nil,
        shutdownGate: LSPServiceGate? = nil,
        onExit: @escaping @Sendable () -> Void
    ) {
        self.scripted = scripted
        self.shutdownError = shutdownError
        self.shutdownGate = shutdownGate
        self.onExit = onExit
    }

    func sendNotification(_ notif: ClientNotification) async throws {
        try await scripted.sendNotification(notif)
        if notif.method == .exit {
            onExit()
        }
    }

    func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
        if request.method == .shutdown {
            await shutdownGate?.wait()
            if let shutdownError {
                throw shutdownError
            }
        }
        return try await scripted.sendRequest(request)
    }
}

@MainActor
final class LSPServiceGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isOpen = false

    var waiterCount: Int {
        waiters.count
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

@MainActor
func lspServiceFlushMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

extension ScriptedServerConnection {
    var lspServiceOpens: [TextDocumentItem] {
        notifications.compactMap { notification in
            guard case let .textDocumentDidOpen(params) = notification else { return nil }
            return params.textDocument
        }
    }

    var lspServiceChanges: [DidChangeTextDocumentParams] {
        notifications.compactMap { notification in
            guard case let .textDocumentDidChange(params) = notification else { return nil }
            return params
        }
    }

    var lspServiceWatchedChanges: [DidChangeWatchedFilesParams] {
        notifications.compactMap { notification in
            guard case let .workspaceDidChangeWatchedFiles(params) = notification else { return nil }
            return params
        }
    }

    var lspServiceDocumentLog: [String] {
        log.filter { $0.hasPrefix("textDocument/did") }
    }
}

@MainActor
final class LSPServiceFixture {
    typealias Server = LanguageServer<CodeFileDocument>
    typealias Key = LSPService.ClientKey

    struct CreatedServer {
        let language: LSPLanguage
        let workspacePath: String
        let binary: LanguageServerBinary
        let connection: ScriptedServerConnection
        let server: Server
        let terminations: AsyncStream<Void>.Continuation

        func terminate() {
            terminations.yield()
            terminations.finish()
        }
    }

    struct DiscoveryCall: Equatable {
        let language: LSPLanguage
        let workspacePath: String
    }

    struct PostedTask: Equatable {
        let workspaceURL: URL
        let action: TaskNotificationHandler.Action
        let model: TaskNotificationModel
    }

    private(set) var created: [CreatedServer] = []
    private(set) var discoveries: [DiscoveryCall] = []
    private(set) var openSettingsCount = 0
    private(set) var presentedAlerts: [NSAlert] = []
    private(set) var externallyOpenedURLs: [URL] = []
    private(set) var postedTasks: [PostedTask] = []

    var binary: LanguageServerBinary? = LanguageServerBinary(execPath: "/fake/language-server", args: ["--stdio"], env: nil)
    var createFailure: (any Error)?
    var shutdownFailure: (any Error)?
    var shutdownGate: LSPServiceGate?
    var discoveryGate: LSPServiceGate?
    var createGate: LSPServiceGate?
    var terminatesOnExit = true
    var capabilities = ScriptedServerConnection.incrementalCapabilities()
    var restartBackoff: Duration = .milliseconds(20)
    var alertResponse: NSApplication.ModalResponse = .abort
    var opensExternalURLs = false

    let notificationManager = NotificationManager(center: NotificationsFakeCenter(), notificationCenter: NotificationCenter())

    func makeService(
        observesDocumentNotifications: Bool = false,
        settings: Dreamder.Settings = .shared
    ) -> LSPService {
        LSPService(dependencies: LSPService.Dependencies(
            createServer: { [self] language, binary, workspacePath in
                try await createServer(language: language, binary: binary, workspacePath: workspacePath)
            },
            discoverBinary: { [self] language, workspacePath in
                await discoverBinary(language: language, workspacePath: workspacePath)
            },
            restartBackoff: restartBackoff,
            observesDocumentNotifications: observesDocumentNotifications,
            notifications: { [self] in notificationManager },
            openSettings: { [self] in openSettingsCount += 1 },
            runAlert: { [self] alert in
                presentedAlerts.append(alert)
                return alertResponse
            },
            openExternalURL: { [self] url in
                externallyOpenedURLs.append(url)
                return opensExternalURLs
            },
            postTask: { [self] workspaceURL, action, model in
                postedTasks.append(PostedTask(workspaceURL: workspaceURL, action: action, model: model))
            }
        ), settings: settings)
    }

    func notificationCount(titled title: String) -> Int {
        notificationManager.notifications.filter { $0.title == title }.count
    }

    private func discoverBinary(language: LSPLanguage, workspacePath: String) async -> LanguageServerBinary? {
        discoveries.append(DiscoveryCall(language: language, workspacePath: workspacePath))
        if let discoveryGate {
            await discoveryGate.wait()
        }
        return binary
    }

    private func createServer(
        language: LSPLanguage,
        binary: LanguageServerBinary,
        workspacePath: String
    ) async throws -> Server {
        if let createGate {
            await createGate.wait()
        }
        if let createFailure {
            throw createFailure
        }
        let (terminations, continuation) = AsyncStream<Void>.makeStream()
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let signalsExit = terminatesOnExit
        let connection = LSPServiceExitSignalingConnection(
            scripted: scripted,
            shutdownError: shutdownFailure,
            shutdownGate: shutdownGate
        ) {
            if signalsExit {
                continuation.yield()
                continuation.finish()
            }
        }
        let initializing = InitializingServer(
            server: connection,
            initializeParamsProvider: Server.getInitParams(workspacePath: workspacePath)
        )
        _ = try await initializing.initializeIfNeeded()
        let server = Server(
            languageId: language,
            binary: binary,
            lspInstance: initializing,
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: URL(fileURLWithPath: workspacePath),
            logContainer: LanguageServerLogContainer(languageID: language.rawValue),
            terminationEvents: terminations
        )
        created.append(CreatedServer(
            language: language,
            workspacePath: workspacePath,
            binary: binary,
            connection: scripted,
            server: server,
            terminations: continuation
        ))
        return server
    }
}

@MainActor
final class LSPServiceWorkspace {
    let directory: URL
    let workspace: WorkspaceDocument
    let fileManager: CEWorkspaceFileManager
    let path: String
    private(set) var documents: [String: CodeFileDocument] = [:]

    init(directory: URL, files: [String: String]) throws {
        for (name, text) in files {
            try text.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        guard let fileManager = workspace.workspaceFileManager, let path = workspace.fileURL?.absolutePath else {
            throw LSPServiceFixtureError.workspaceUnavailable
        }
        fileManager.fsEventStream = nil
        fileManager.eventBatcher = nil
        DreamderDocumentController.shared.addDocument(workspace)
        self.directory = directory
        self.workspace = workspace
        self.fileManager = fileManager
        self.path = path
    }

    func key(_ language: LSPLanguage) -> LSPService.ClientKey {
        LSPService.ClientKey(language, path)
    }

    func document(_ name: String) throws -> CodeFileDocument {
        let url = directory.appending(path: name)
        let document = try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
        documents[name] = document
        return document
    }

    func uri(_ name: String) -> String {
        directory.appending(path: name).lspURI
    }

    func setText(_ name: String, _ text: String) {
        guard let content = documents[name]?.content else { return }
        content.replaceCharacters(in: NSRange(location: 0, length: content.length), with: text)
    }

    func close() {
        workspace.close()
    }
}
