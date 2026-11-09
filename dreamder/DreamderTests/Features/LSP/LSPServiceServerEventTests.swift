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

    @Test
    func listeningForAClientThatIsNotRunningRegistersNoTask() {
        let service = fixture.makeService()
        let key = LSPService.ClientKey(.typescript, "/not-running")

        service.startListeningToEvents(for: key)

        #expect(service.eventListeningTasks[key] == nil)
    }

    @Test
    func eventsForAClientThatWasRemovedAreRejectedOrIgnored() async throws {
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

    @Test
    func serverErrorsAndUnhandledNotificationsDoNotStopTheEventLoop() async throws {
        try await running { _, created in
            created.connection.emit(.error(ScriptedServerConnectionFailure.injected("broken")))
            created.connection.emit(.notification(.telemetryEvent(.string("usage"))))
            created.connection.emit(.notification(.windowLogMessage(LogMessageParams(type: .info, message: "after"))))

            try await eventually(timeout: .seconds(30)) { !created.server.logContainer.logs.isEmpty }

            #expect(created.server.logContainer.logs.map(\.message) == ["after"])
        }
    }

    @Test
    func progressRequestsAndNotificationsFeedTheClientTracker() async throws {
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
