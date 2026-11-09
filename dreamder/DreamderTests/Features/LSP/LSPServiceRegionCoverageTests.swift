import AppKit
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

private final class LSPServiceRegionReplies<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

@MainActor
@Suite("LSPService region coverage", .serialized, .uiGate)
struct LSPServiceRegionCoverageTests {
    typealias Created = LSPServiceFixture.CreatedServer

    let fixture = LSPServiceFixture()

    private func running(
        _ files: [String: String],
        _ body: (LSPService, LSPServiceWorkspace, LSPService.ClientKey, Created) async throws -> Void
    ) async throws {
        try await withTempDir { directory in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: directory, files: files)
            defer { workspace.close() }
            _ = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let created = try #require(fixture.created.first)
            try await body(service, workspace, workspace.key(.typescript), created)
        }
    }

    private func diagnostic(_ message: String) -> Diagnostic {
        Diagnostic(
            range: LSPRange(start: Position(line: 0, character: 4), end: Position(line: 0, character: 5)),
            severity: .warning,
            code: nil,
            source: "tsc",
            message: message
        )
    }

    private func workspaceDiagnostic(_ fileURL: URL, _ message: String) -> WorkspaceDiagnostic {
        WorkspaceDiagnostic(
            fileURL: fileURL, startLine: 1, startColumn: 1, endLine: 1, endColumn: 2,
            severity: .error, message: message, source: nil, code: nil
        )
    }

    @Test
    func publishedDiagnosticsLandInTheWorkspaceDiagnosticsStore() async throws {
        try await running(["a.ts": "let a = 1\n"]) { _, workspace, _, created in
            let fileURL = workspace.directory.appending(path: "a.ts")
            let store = workspace.workspace.diagnosticsStore
            let params = PublishDiagnosticsParams(uri: workspace.uri("a.ts"), diagnostics: [diagnostic("unused")])

            created.connection.emit(.notification(.textDocumentPublishDiagnostics(params)))
            try await eventually(timeout: .seconds(30)) { !store.diagnostics(for: fileURL).isEmpty }

            #expect(store.diagnostics(for: fileURL).map(\.message) == ["unused"])
        }
    }

    @Test
    func eventsDeliveredAfterTheListenerWasCancelledAreDropped() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            await lspServiceFlushMainQueue()

            created.connection.emit(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "late"))))
            service.stopListeningToEvents(for: key)
            await lspServiceFlushMainQueue()

            #expect(service.eventListeningTasks[key] == nil)
            #expect(created.server.logContainer.logs.isEmpty)
            #expect(workspace.workspace.diagnosticsStore.diagnostics(for: workspace.directory).isEmpty)
        }
    }

    @Test
    func workspaceFolderRequestsAreAnsweredWithTheServerWorkspace() async throws {
        try await running(["a.ts": "let a = 1\n"]) { _, workspace, _, created in
            let replies = LSPServiceRegionReplies<Result<WorkspaceFoldersResponse, AnyJSONRPCResponseError>>()

            created.connection.emit(.request(id: .numericId(21), request: .workspaceFolders { replies.append($0) }))
            try await eventually(timeout: .seconds(30)) { !replies.values.isEmpty }

            let expected = WorkspaceFolder(
                uri: URL(fileURLWithPath: workspace.path, isDirectory: false).absoluteString,
                name: URL(fileURLWithPath: workspace.path).lastPathComponent
            )
            #expect(replies.values == [.success([expected])])
        }
    }

    @Test
    func configurationRequestsAreAnsweredFromTheWorkspaceConfiguration() async throws {
        try await running(["a.ts": "let a = 1\n"]) { _, _, _, created in
            let replies = LSPServiceRegionReplies<Result<[LSPAny], AnyJSONRPCResponseError>>()
            let params = ConfigurationParams(items: [
                ConfigurationItem(scopeUri: nil, section: "typescript.format"),
                ConfigurationItem(scopeUri: nil, section: nil)
            ])

            created.connection.emit(.request(id: .numericId(22), request: .workspaceConfiguration(params) {
                replies.append($0)
            }))
            try await eventually(timeout: .seconds(30)) { !replies.values.isEmpty }

            let expected: [LSPAny] = [.null, .null]
            #expect(replies.values == [.success(expected)])
        }
    }

    @Test
    func diagnosticsRefreshPullsWhenThePullCapabilityIsRegisteredDynamically() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let client = try #require(service.languageClients[key])
            client.dynamicCapabilities.register([Registration(id: "pull", method: "textDocument/diagnostic")])
            try created.connection.script(
                .textDocumentDiagnostic,
                DocumentDiagnosticReport(kind: .full, items: [diagnostic("dynamic")])
            )

            await service.refresh(.diagnostics, for: key)

            let fileURL = workspace.directory.appending(path: "a.ts")
            #expect(created.connection.requestCount(.textDocumentDiagnostic) == 1)
            #expect(workspace.workspace.diagnosticsStore.diagnostics(for: fileURL).map(\.message) == ["dynamic"])
        }
    }

    @Test
    func diagnosticsRefreshSendsNothingToServersWithoutPullSupport() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()

            await service.refresh(.diagnostics, for: key)

            #expect(created.connection.requestCount(.textDocumentDiagnostic) == 0)
        }
    }

    @Test
    func unchangedPullReportsKeepTheStoredDiagnostics() async throws {
        fixture.capabilities.diagnosticProvider = .optionA(
            DiagnosticOptions(identifier: nil, interFileDependencies: false, workspaceDiagnostics: false)
        )
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            try created.connection.script(
                .textDocumentDiagnostic,
                DocumentDiagnosticReport(kind: .unchanged, resultId: "r1")
            )
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let fileURL = workspace.directory.appending(path: "a.ts")
            let store = workspace.workspace.diagnosticsStore
            store.replace([workspaceDiagnostic(fileURL, "kept")], for: fileURL)
            let pulls = created.connection.requestCount(.textDocumentDiagnostic)

            await service.refresh(.diagnostics, for: key)

            #expect(created.connection.requestCount(.textDocumentDiagnostic) == pulls + 1)
            #expect(store.diagnostics(for: fileURL).map(\.message) == ["kept"])
        }
    }

    @Test
    func workspaceEditsReachDocumentsThatLostTheirFileURLUnderTheRequestedURI() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, _ in
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let client = try #require(service.languageClients[key])
            let uri = workspace.uri("a.ts")
            document.fileURL = nil
            let edit = TextEdit(range: LSPRange(startPair: (0, 4), endPair: (0, 5)), newText: "b")

            let result = await service.applyWorkspaceEdit(
                WorkspaceEdit(changes: [uri: [edit]], documentChanges: nil),
                via: client
            )

            #expect(result.applied)
            #expect(document.content?.string == "let b = 1\n")
        }
    }

    @Test
    func watchedFilesOfAReleasedClientHaveNoWatchersAndSendNothing() async {
        #expect(LSPService.registeredWatchers(of: nil).isEmpty)

        await LSPService.sendWatchedFileChanges(DidChangeWatchedFilesParams(changes: []), to: nil)
    }

    @Test
    func disabledPackagesAreTheInstalledServersThatAreSwitchedOff() {
        let servers = [
            "on": SettingsData.InstalledLanguageServer(packageName: "on", isEnabled: true, version: "1"),
            "off": SettingsData.InstalledLanguageServer(packageName: "off", isEnabled: false, version: "2"),
            "also-off": SettingsData.InstalledLanguageServer(packageName: "also-off", isEnabled: false, version: "3")
        ]

        #expect(LSPService.Dependencies.disabledPackageNames(in: servers) == ["off", "also-off"])
        #expect(LSPService.Dependencies.disabledPackageNames(in: [:]).isEmpty)
    }

    @Test
    func liveDependenciesOpenTheSettingsSceneThroughTheAppDelegate() {
        let delegate = AppDelegate()
        var openedScenes: [SceneID] = []
        delegate.installSceneOpener { openedScenes.append($0) }
        let live = LSPService.Dependencies.live

        withExtendedLifetime(delegate) {
            live.openSettings()
        }

        #expect(openedScenes == [.settings])
    }

    @Test
    func liveDependenciesCreateAServerFromABinary() async throws {
        let language = LSPLanguage(rawValue: "ruby")
        let binary = LanguageServerBinary(
            execPath: "/bin/sh",
            args: ["-c", canonicalInitializeServerScript],
            env: ["PATH": "/usr/bin:/bin"]
        )
        let create = LSPService.Dependencies.live.createServer
        let server = try await withTimeout(duration: .seconds(60)) {
            try await create(language, binary, "/tmp")
        }
        let service = fixture.makeService()
        service.languageClients[LSPService.ClientKey(language, "/tmp")] = server
        let terminations = server.terminationEvents

        #expect(server.pid > 0)
        service.killAllServers()

        let fired = try await withTimeout(duration: .seconds(60)) {
            for await _ in terminations {
                return true
            }
            return false
        }
        #expect(fired)
    }
}
