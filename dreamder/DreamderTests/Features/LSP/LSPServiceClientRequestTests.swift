import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import JSONRPC
import LanguageClient
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

private final class LSPServiceReplyRecorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

private let canonicalInitializeServerScript = """
IFS= read -r header
length=$(printf '%s' "$header" | tr -dc '0-9')
IFS= read -r blank
body=$(dd bs=1 count="$length" 2>/dev/null)
id=$(printf '%s' "$body" | sed 's/.*"id":\\([^,}]*\\).*/\\1/')
response="{\\"jsonrpc\\":\\"2.0\\",\\"id\\":$id,\\"result\\":{\\"capabilities\\":{}}}"
printf 'Content-Length: %d\\r\\n\\r\\n%s' "${#response}" "$response"
exec cat > /dev/null
"""

@MainActor
@Suite("LSPService client requests", .uiGate)
struct LSPServiceClientRequestTests {
    typealias Client = LSPService.LanguageServerType
    typealias Created = LSPServiceFixture.CreatedServer
    typealias EditReply = Result<ApplyWorkspaceEditResult, AnyJSONRPCResponseError>
    typealias MessageReply = Result<ShowMessageRequestResponse, AnyJSONRPCResponseError>
    typealias DocumentReply = Result<ShowDocumentResult, AnyJSONRPCResponseError>

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

    private func standaloneClient() async throws -> Client {
        let capabilities = ScriptedServerConnection.incrementalCapabilities()
        let client = Client(
            languageId: .typescript,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: ScriptedServerConnection(capabilities: capabilities),
                initializeParamsProvider: Client.getInitParams(workspacePath: "/")
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: URL(fileURLWithPath: "/"),
            logContainer: LanguageServerLogContainer(languageID: "typescript")
        )
        _ = try await client.lspInstance.initializeIfNeeded()
        return client
    }

    private func caret(_ workspace: LSPServiceWorkspace) -> CursorPosition? {
        workspace.workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first
    }

    private func openedFileName(_ workspace: LSPServiceWorkspace) -> String? {
        workspace.workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent
    }

    private func replaceEdit(_ uri: String, from: Int, to: Int, with text: String) -> WorkspaceEdit {
        let edit = TextEdit(range: LSPRange(startPair: (0, from), endPair: (0, to)), newText: text)
        return WorkspaceEdit(changes: [uri: [edit]], documentChanges: nil)
    }

    private func messageParams(_ type: MessageType, _ message: String, _ titles: [String]?) -> ShowMessageRequestParams {
        let actions = titles.map { $0.map { MessageActionItem(title: $0) } }
        return ShowMessageRequestParams(type: type, message: message, actions: actions)
    }

    @Test func serverApplyEditRequestsEditFilesAndReplyWithTheOutcome() async throws {
        try await running(["a.ts": "let a = 1\n"]) { _, workspace, _, created in
            let replies = LSPServiceReplyRecorder<EditReply>()
            let edit = replaceEdit(workspace.uri("a.ts"), from: 4, to: 5, with: "b")
            let request = ServerRequest.workspaceApplyEdit(ApplyWorkspaceEditParams(label: nil, edit: edit)) {
                replies.append($0)
            }

            created.connection.emit(.request(id: .numericId(1), request: request))
            try await eventually(timeout: .seconds(30)) { !replies.values.isEmpty }

            #expect(replies.values == [.success(ApplyWorkspaceEditResult(applied: true))])
            let text = try String(contentsOf: workspace.directory.appending(path: "a.ts"), encoding: .utf8)
            #expect(text == "let b = 1\n")
        }
    }

    @Test func aReleasedServiceAnswersEveryDelegatedRequestWithoutActing() async throws {
        let client = try await standaloneClient()
        let key = LSPService.ClientKey(.typescript, "/released")
        var service: LSPService? = fixture.makeService()
        let handler = try #require(service).makeClientRequestHandler(for: key, client: client)
        service = nil
        let edits = LSPServiceReplyRecorder<EditReply>()
        let messages = LSPServiceReplyRecorder<MessageReply>()
        let documents = LSPServiceReplyRecorder<DocumentReply>()
        let refreshes = LSPServiceReplyRecorder<AnyJSONRPCResponseError?>()
        let emptyEdit = WorkspaceEdit(changes: [:], documentChanges: nil)

        await handler.handle(.workspaceApplyEdit(ApplyWorkspaceEditParams(label: nil, edit: emptyEdit)) {
            edits.append($0)
        })
        await handler.handle(.windowShowMessageRequest(messageParams(.info, "m", ["OK"])) { messages.append($0) })
        await handler.handle(.windowShowDocument(ShowDocumentParams(uri: "https://example.com")) {
            documents.append($0)
        })
        await handler.handle(.workspaceSemanticTokenRefresh { refreshes.append($0) })

        #expect(edits.values == [.success(ApplyWorkspaceEditResult(
            applied: false,
            failureReason: "The language service is gone"
        ))])
        #expect(messages.values == [.success(nil)])
        #expect(documents.values == [.success(ShowDocumentResult(success: false))])
        #expect(refreshes.values == [nil])
        #expect(fixture.presentedAlerts.isEmpty)
        #expect(fixture.externallyOpenedURLs.isEmpty)
    }

    @Test func serverMessageRequestsAreLoggedAndTheChosenActionIsReturned() async throws {
        try await running(["a.ts": "let a = 1\n"]) { _, _, _, created in
            let first = NSApplication.ModalResponse.alertFirstButtonReturn
            fixture.alertResponse = NSApplication.ModalResponse(rawValue: first.rawValue + 1)
            let replies = LSPServiceReplyRecorder<MessageReply>()
            let request = ServerRequest.windowShowMessageRequest(
                messageParams(.warning, "Pick one", ["First", "Second"])
            ) { replies.append($0) }

            created.connection.emit(.request(id: .numericId(2), request: request))
            try await eventually(timeout: .seconds(30)) { !replies.values.isEmpty }

            #expect(replies.values == [.success(MessageActionItem(title: "Second"))])
            let alert = try #require(fixture.presentedAlerts.first)
            #expect(alert.alertStyle == .warning)
            #expect(alert.messageText == "Typescript language server")
            #expect(alert.informativeText == "Pick one")
            #expect(alert.buttons.map(\.title) == ["First", "Second"])
            #expect(created.server.logContainer.logs.map(\.message) == ["Pick one"])
        }
    }

    @Test func messageRequestAlertStyleFollowsTheMessageType() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, _, key, _ in
            let cases: [(MessageType, NSAlert.Style)] = [
                (.error, .critical), (.warning, .warning), (.info, .informational), (.log, .informational)
            ]
            for (type, style) in cases {
                _ = service.presentMessageRequest(messageParams(type, "m", ["OK"]), for: key)
                #expect(fixture.presentedAlerts.last?.alertStyle == style)
            }
            #expect(fixture.presentedAlerts.count == cases.count)
        }
    }

    @Test func messageRequestsMapTheModalResponseToAnAction() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, _, key, _ in
            let firstAction = MessageActionItem(title: "First")
            let secondAction = MessageActionItem(title: "Second")
            let params = ShowMessageRequestParams(type: .info, message: "m", actions: [firstAction, secondAction])
            let firstButton = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            let responses: [(NSApplication.ModalResponse, MessageActionItem?)] = [
                (NSApplication.ModalResponse(rawValue: firstButton), firstAction),
                (NSApplication.ModalResponse(rawValue: firstButton + 1), secondAction),
                (NSApplication.ModalResponse(rawValue: firstButton + 2), nil),
                (.abort, nil)
            ]
            for (response, expected) in responses {
                fixture.alertResponse = response
                #expect(service.presentMessageRequest(params, for: key) == expected)
            }
        }
    }

    @Test func messageRequestsWithoutActionsAreOnlyLogged() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, _, key, created in
            let notRunning = LSPService.ClientKey(.typescript, "/not-running")
            let withoutActions = messageParams(.info, "no actions", nil)
            let emptyActions = messageParams(.error, "empty", [])
            let unknownServer = messageParams(.info, "ignored", nil)

            #expect(service.presentMessageRequest(withoutActions, for: key) == nil)
            #expect(service.presentMessageRequest(emptyActions, for: key) == nil)
            #expect(service.presentMessageRequest(unknownServer, for: notRunning) == nil)

            #expect(fixture.presentedAlerts.isEmpty)
            #expect(created.server.logContainer.logs.map(\.message) == ["no actions", "empty"])
        }
    }

    @Test func externalDocumentsAreHandedToTheSystemOpener() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, _, key, _ in
            fixture.opensExternalURLs = true
            let web = try #require(URL(string: "https://example.com/docs"))

            #expect(service.showDocument(ShowDocumentParams(uri: web.absoluteString), for: key))
            #expect(service.showDocument(ShowDocumentParams(uri: "file:///tmp/report.pdf", external: true), for: key))
            fixture.opensExternalURLs = false
            #expect(!service.showDocument(ShowDocumentParams(uri: web.absoluteString), for: key))

            #expect(fixture.externallyOpenedURLs == [web, URL(fileURLWithPath: "/tmp/report.pdf"), web])
        }
    }

    @Test func fileDocumentsOpenInTheEditorAtTheRequestedSelection() async throws {
        try await running(["a.ts": "line one\nline two\nline three\n"]) { service, workspace, key, _ in
            let uri = workspace.uri("a.ts")

            #expect(service.showDocument(ShowDocumentParams(uri: uri), for: key))
            #expect(openedFileName(workspace) == "a.ts")
            #expect(caret(workspace)?.start.line == 1)
            #expect(caret(workspace)?.start.column == 1)
            #expect(caret(workspace)?.end == nil)

            let range = LSPRange(startPair: (1, 2), endPair: (1, 5))
            #expect(service.showDocument(ShowDocumentParams(uri: uri, selection: range), for: key))
            #expect(caret(workspace)?.start.line == 2)
            #expect(caret(workspace)?.start.column == 3)
            #expect(caret(workspace)?.end?.line == 2)
            #expect(caret(workspace)?.end?.column == 6)

            let collapsed = LSPRange(startPair: (2, 1), endPair: (2, 1))
            #expect(service.showDocument(ShowDocumentParams(uri: uri, selection: collapsed), for: key))
            #expect(caret(workspace)?.start.line == 3)
            #expect(caret(workspace)?.start.column == 2)
            #expect(caret(workspace)?.end == nil)
            #expect(fixture.externallyOpenedURLs.isEmpty)
        }
    }

    @Test func documentsThatCannotBeShownAreReportedAsFailures() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, _ in
            #expect(!service.showDocument(ShowDocumentParams(uri: workspace.uri("missing.ts")), for: key))
            #expect(!service.showDocument(ShowDocumentParams(uri: "untitled:Untitled-1"), for: key))

            #expect(openedFileName(workspace) == nil)

            workspace.workspace.editorManager = nil
            #expect(!service.showDocument(ShowDocumentParams(uri: workspace.uri("a.ts")), for: key))
        }
    }

    @Test func filesOutsideTheWorkspaceOpenInTheWorkspaceOfTheRequestingServer() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, _ in
            try withTempDir { elsewhere in
                let outside = elsewhere.appending(path: "outside.ts")
                try "let o = 1\n".write(to: outside, atomically: true, encoding: .utf8)

                #expect(service.showDocument(ShowDocumentParams(uri: outside.lspURI), for: key))

                #expect(openedFileName(workspace) == "outside.ts")
            }
        }
    }

    @Test func liveDependenciesNeverShowModalsOrOpenExternalURLsInHeadlessMode() throws {
        try #require(DreamderHeadless.isEnabled)
        let live = LSPService.Dependencies.live
        let web = try #require(URL(string: "https://example.com"))

        #expect(live.runAlert(NSAlert()) == .abort)
        #expect(live.openExternalURL(web) == false)
    }

    @Test func semanticTokenRefreshRequestsTokensAndSurvivesServerFailures() async throws {
        fixture.capabilities.semanticTokensProvider = .optionA(.init(legend: .init(tokenTypes: [], tokenModifiers: [])))
        try await running(["a.ts": "let a = 1\n", "b.ts": "let b = 2\n"]) { service, workspace, key, created in
            let attached = try workspace.document("a.ts")
            let detached = try workspace.document("b.ts")
            service.openDocument(attached)
            service.openDocument(detached)
            await service.waitForDocumentOperations()
            let textView = TextView(string: "let a = 1\n")
            attached.languageServerObjects.highlightProvider.setUp(textView: textView, codeLanguage: .swift)
            try await eventually(timeout: .seconds(30)) {
                created.connection.requestCount(.textDocumentSemanticTokensFull) >= 1
            }
            let initial = created.connection.requestCount(.textDocumentSemanticTokensFull)

            await service.refresh(.semanticTokens, for: key)
            #expect(created.connection.requestCount(.textDocumentSemanticTokensFull) == initial + 1)

            created.connection.failRequests([.textDocumentSemanticTokensFull])
            await service.refresh(.semanticTokens, for: key)
            #expect(created.connection.requestCount(.textDocumentSemanticTokensFull) == initial + 2)
            withExtendedLifetime(textView) {}
        }
    }

    @Test func inlayHintRefreshPostsANotificationForTheWorkspace() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, _ in
            let posted = LSPServiceReplyRecorder<String>()
            let kindKey = LSPService.refreshKindUserInfoKey
            let pathKey = LSPService.refreshWorkspacePathUserInfoKey
            let observer = NotificationCenter.default.addObserver(
                forName: LSPService.refreshRequestedNotification,
                object: service,
                queue: nil
            ) { notification in
                let kind = notification.userInfo?[kindKey] as? String ?? ""
                let path = notification.userInfo?[pathKey] as? String ?? ""
                posted.append("\(kind)|\(path)")
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            await service.refresh(.inlayHint, for: key)
            await service.refresh(.inlayHint, for: LSPService.ClientKey(.typescript, "/not-running"))

            #expect(posted.values == ["inlayHint|\(workspace.path)"])
        }
    }

    @Test func diagnosticsRefreshSurvivesAFailingPullRequest() async throws {
        fixture.capabilities.diagnosticProvider = .optionA(
            DiagnosticOptions(identifier: nil, interFileDependencies: false, workspaceDiagnostics: false)
        )
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            try created.connection.script(.textDocumentDiagnostic, DocumentDiagnosticReport(kind: .full, items: []))
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let opened = created.connection.requestCount(.textDocumentDiagnostic)
            #expect(opened >= 1)

            created.connection.failRequests([.textDocumentDiagnostic])
            await service.refresh(.diagnostics, for: key)

            #expect(created.connection.requestCount(.textDocumentDiagnostic) == opened + 1)
        }
    }

    @Test func aFailingServerSyncStillAppliesTheEditToTheOpenDocument() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, key, created in
            let document = try workspace.document("a.ts")
            service.openDocument(document)
            await service.waitForDocumentOperations()
            let client = try #require(service.languageClients[key])
            created.connection.failNotifications([.textDocumentDidChange])

            let result = await service.applyWorkspaceEdit(
                replaceEdit(workspace.uri("a.ts"), from: 4, to: 5, with: "b"),
                via: client
            )

            #expect(result.applied)
            #expect(document.content?.string == "let b = 1\n")
            #expect(created.connection.notificationCount(.textDocumentDidChange) >= 1)
        }
    }

    @Test func aFailingCloseNotificationDoesNotBlockTheNextOpen() async throws {
        try await running(["a.ts": "let a = 1\n"]) { service, workspace, _, created in
            let document = try workspace.document("a.ts")
            let url = try #require(document.fileURL)
            service.openDocument(document)
            await service.waitForDocumentOperations()
            created.connection.failNotifications([.textDocumentDidClose])

            service.closeDocument(url)
            await service.waitForDocumentOperations()

            #expect(created.connection.notificationCount(.textDocumentDidClose) == 1)
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) == nil)

            created.connection.failNotifications([])
            service.openDocument(document)
            await service.waitForDocumentOperations()

            #expect(created.connection.notificationCount(.textDocumentDidOpen) == 2)
            #expect(created.server.openFiles.document(for: workspace.uri("a.ts")) != nil)
        }
    }

    @Test func aFailingOpenNotificationIsLoggedAndLaterOpensStillWork() async throws {
        try await running(["a.ts": "let a = 1\n", "b.ts": "let b = 2\n"]) { service, workspace, _, created in
            created.connection.failNotifications([.textDocumentDidOpen])
            service.openDocument(try workspace.document("a.ts"))
            await service.waitForDocumentOperations()
            #expect(created.connection.notificationCount(.textDocumentDidOpen) == 1)

            created.connection.failNotifications([])
            service.openDocument(try workspace.document("b.ts"))
            await service.waitForDocumentOperations()

            #expect(created.connection.notificationCount(.textDocumentDidOpen) == 2)
            #expect(created.server.openFiles.document(for: workspace.uri("b.ts")) != nil)
        }
    }

    @Test func killingAllServersTerminatesTheirProcesses() async throws {
        let language = LSPLanguage(rawValue: "ruby")
        let binary = LanguageServerBinary(
            execPath: "/bin/sh",
            args: ["-c", canonicalInitializeServerScript],
            env: ["PATH": "/usr/bin:/bin"]
        )
        let server = try await withTimeout(duration: .seconds(60)) {
            try await Client.createServer(for: language, with: binary, workspacePath: "/tmp")
        }
        _ = try #require(server.pid > 0 ? server.pid : nil)
        let service = fixture.makeService()
        service.languageClients[LSPService.ClientKey(language, "/tmp")] = server
        let terminations = server.terminationEvents

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

@MainActor
@Suite("LSPService server events", .uiGate)
struct LSPServiceServerEventTests {
    let fixture = LSPServiceFixture()

    private func running(_ body: (LSPService, LSPServiceFixture.CreatedServer) async throws -> Void) async throws {
        try await withTempDir { directory in
            let service = fixture.makeService()
            let workspace = try LSPServiceWorkspace(directory: directory, files: ["a.ts": "let a = 1\n"])
            defer { workspace.close() }
            _ = try await service.startServer(for: .typescript, workspacePath: workspace.path)
            let created = try #require(fixture.created.first)
            try await body(service, created)
        }
    }

    @Test func listeningForAClientThatIsNotRunningRegistersNoTask() {
        let service = fixture.makeService()
        let key = LSPService.ClientKey(.typescript, "/not-running")

        service.startListeningToEvents(for: key)

        #expect(service.eventListeningTasks[key] == nil)
    }

    @Test func eventsForAClientThatWasRemovedAreRejectedOrIgnored() async throws {
        try await running { service, created in
            let key = LSPService.ClientKey(created.language, created.workspacePath)
            service.languageClients.removeValue(forKey: key)
            let replies = LSPServiceReplyRecorder<Result<ApplyWorkspaceEditResult, AnyJSONRPCResponseError>>()
            let emptyEdit = WorkspaceEdit(changes: [:], documentChanges: nil)
            let request = ServerRequest.workspaceApplyEdit(ApplyWorkspaceEditParams(label: nil, edit: emptyEdit)) {
                replies.append($0)
            }

            created.connection.emit(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "ignored"))))
            created.connection.emit(.request(id: .numericId(9), request: request))
            try await eventually(timeout: .seconds(30)) { !replies.values.isEmpty }

            let rejection = AnyJSONRPCResponseError(
                code: LSPClientRequestHandler.internalErrorCode,
                message: "The typescript language client is not running",
                data: nil
            )
            #expect(replies.values == [.failure(rejection)])
            #expect(created.server.logContainer.logs.isEmpty)
        }
    }

    @Test func serverErrorsAndUnhandledNotificationsDoNotStopTheEventLoop() async throws {
        try await running { _, created in
            created.connection.emit(.error(ScriptedServerConnectionFailure.injected("broken")))
            created.connection.emit(.notification(.telemetryEvent(.string("usage"))))
            created.connection.emit(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "after"))))

            try await eventually(timeout: .seconds(30)) { !created.server.logContainer.logs.isEmpty }

            #expect(created.server.logContainer.logs.map(\.message) == ["after"])
        }
    }

    @Test func progressRequestsAndNotificationsFeedTheClientTracker() async throws {
        try await running { _, created in
            let token = ProgressToken.optionB("indexing")
            let createReplies = LSPServiceReplyRecorder<AnyJSONRPCResponseError?>()
            let create = ServerRequest.windowWorkDoneProgressCreate(WorkDoneProgressCreateParams(token: token)) {
                createReplies.append($0)
            }
            let begin = ProgressParams(token: token, value: ["kind": "begin", "title": "Indexing", "percentage": 10])

            created.connection.emit(.request(id: .numericId(7), request: create))
            created.connection.emit(.notification(.protocolProgress(begin)))
            try await eventually(timeout: .seconds(30)) {
                created.server.workDoneProgress.progress(for: token)?.hasBegun == true
            }

            #expect(createReplies.values == [nil])
            #expect(created.server.workDoneProgress.progress(for: token)?.title == "Indexing")
            #expect(created.server.workDoneProgress.progress(for: token)?.percentage == 10)
        }
    }
}
