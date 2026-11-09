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

final class LSPServiceReplyRecorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

let canonicalInitializeServerScript = """
IFS= read -r header
length=$(printf '%s' "$header" | tr -dc '0-9')
IFS= read -r blank
body=$(dd bs=1 count="$length" 2>/dev/null)
id=$(printf '%s' "$body" | sed 's/.*"id":\\([^,}]*\\).*/\\1/')
response="{\\"jsonrpc\\":\\"2.0\\",\\"id\\":$id,\\"result\\":{\\"capabilities\\":{}}}"
printf 'Content-Length: %d\\r\\n\\r\\n%s' "${#response}" "$response"
cat > /dev/null
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

    func running(
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

    func standaloneClient() async throws -> Client {
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

    func caret(_ workspace: LSPServiceWorkspace) -> CursorPosition? {
        workspace.workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first
    }

    func openedFileName(_ workspace: LSPServiceWorkspace) -> String? {
        workspace.workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent
    }

    func replaceEdit(_ uri: String, from: Int, to end: Int, with text: String) -> WorkspaceEdit {
        let edit = TextEdit(range: LSPRange(startPair: (0, from), endPair: (0, end)), newText: text)
        return WorkspaceEdit(changes: [uri: [edit]], documentChanges: nil)
    }

    func messageParams(_ type: MessageType, _ message: String, _ titles: [String]?) -> ShowMessageRequestParams {
        let actions = titles.map { $0.map { MessageActionItem(title: $0) } }
        return ShowMessageRequestParams(type: type, message: message, actions: actions)
    }

    @Test
    func serverApplyEditRequestsEditFilesAndReplyWithTheOutcome() async throws {
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

    @Test
    func aReleasedServiceAnswersEveryDelegatedRequestWithoutActing() async throws {
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

    @Test
    func serverMessageRequestsAreLoggedAndTheChosenActionIsReturned() async throws {
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

    @Test
    func messageRequestAlertStyleFollowsTheMessageType() async throws {
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

    @Test
    func messageRequestsMapTheModalResponseToAnAction() async throws {
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

    @Test
    func messageRequestsWithoutActionsAreOnlyLogged() async throws {
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
}
