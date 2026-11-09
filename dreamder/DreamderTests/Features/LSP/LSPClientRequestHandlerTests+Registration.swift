import Foundation
import JSONRPC
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

extension LSPClientRequestHandlerTests {
    @Test
    func registerCapabilityStoresRegistrationsAndRepliesOnce() async {
        let capabilities = LSPDynamicCapabilityRegistry()
        let replies = LSPTestRecorder<AnyJSONRPCResponseError?>()
        let params = RegistrationParams(registrations: [
            Registration(id: "1", method: "textDocument/hover"),
            Registration(
                id: "2",
                method: "workspace/didChangeWatchedFiles",
                registerOptions: ["watchers": [["globPattern": "**/*.swift"]]]
            )
        ])
        await makeHandler(capabilities: capabilities).handle(.clientRegisterCapability(params, { replies.append($0) }))
        #expect(replies.values == [nil])
        #expect(capabilities.registeredMethods == ["textDocument/hover", "workspace/didChangeWatchedFiles"])
        #expect(capabilities.registerOptions(
            for: "workspace/didChangeWatchedFiles",
            as: DidChangeWatchedFilesRegistrationOptions.self
        ) == [DidChangeWatchedFilesRegistrationOptions(watchers: [FileSystemWatcher(globPattern: "**/*.swift")])])
    }

    @Test
    func registerCapabilityDoesNotReplyWhenTheTransportLayerAlreadyDoes() async throws {
        let capabilities = LSPDynamicCapabilityRegistry()
        let replies = LSPTestRecorder<AnyJSONRPCResponseError?>()
        let handler = makeHandler(capabilities: capabilities, repliesToCapabilityRegistration: false)
        await handler.handle(.clientRegisterCapability(
            lspRegistrations([("1", "textDocument/hover")]),
            { replies.append($0) }
        ))
        #expect(capabilities.registeredMethods == ["textDocument/hover"])
        await handler.handle(.clientUnregisterCapability(
            try lspUnregistrations([("1", "textDocument/hover")]),
            { replies.append($0) }
        ))
        #expect(replies.values.isEmpty)
        #expect(capabilities.registeredMethods.isEmpty)
    }

    @Test
    func registeringRefreshableFeaturesTriggersOneRefreshPerKind() async {
        let refreshes = LSPTestRecorder<LSPRefreshKind>()
        let environment = LSPClientRequestEnvironment(refresh: { refreshes.append($0) })
        let params = lspRegistrations([
            ("1", "textDocument/inlayHint"),
            ("2", "textDocument/completion"),
            ("3", "textDocument/diagnostic"),
            ("4", "textDocument/inlayHint"),
            ("5", "textDocument/codeLens")
        ])
        await makeHandler(environment: environment).handle(.clientRegisterCapability(params, { _ in }))
        #expect(refreshes.values == [.inlayHint, .diagnostics])
    }

    @Test
    func unregisterRemovesOnlyTheMatchingIdAndRepliesOnce() async throws {
        let capabilities = LSPDynamicCapabilityRegistry()
        capabilities.register([
            Registration(id: "a", method: "textDocument/hover"),
            Registration(id: "b", method: "textDocument/hover"),
            Registration(id: "a", method: "textDocument/definition")
        ])
        let replies = LSPTestRecorder<AnyJSONRPCResponseError?>()
        let params = try lspUnregistrations([("a", "textDocument/hover"), ("zzz", "textDocument/definition")])
        let handler = makeHandler(capabilities: capabilities)
        await handler.handle(.clientUnregisterCapability(params, { replies.append($0) }))
        #expect(replies.values == [nil])
        #expect(capabilities.registrations(for: "textDocument/hover").map(\.id) == ["b"])
        #expect(capabilities.registrations(for: "textDocument/definition").map(\.id) == ["a"])
    }

    @Test
    func codeLensRefreshIsAcknowledgedWithoutARefreshAndSemanticTokenRefreshRepliesBeforeRefreshing() async {
        let order = LSPTestRecorder<String>()
        let environment = LSPClientRequestEnvironment(refresh: { order.append("refresh:\($0.rawValue)") })
        let handler = makeHandler(environment: environment)
        await handler.handle(.workspaceCodeLensRefresh({ _ in order.append("reply:codeLens") }))
        await handler.handle(.workspaceSemanticTokenRefresh({ _ in order.append("reply:semanticTokens") }))
        #expect(order.values == ["reply:codeLens", "reply:semanticTokens", "refresh:semanticTokens"])
    }

    @Test
    func customRefreshRequestsReplyWithNullAndTriggerTheRefresh() async {
        let refreshes = LSPTestRecorder<LSPRefreshKind>()
        let replies = LSPTestRecorder<Result<LSPAny, AnyJSONRPCResponseError>>()
        let environment = LSPClientRequestEnvironment(refresh: { refreshes.append($0) })
        let handler = makeHandler(environment: environment)
        await handler.handle(.custom("workspace/inlayHint/refresh", .null, { replies.append($0) }))
        await handler.handle(.custom("workspace/diagnostic/refresh", .null, { replies.append($0) }))
        #expect(replies.values == [.success(.null), .success(.null)])
        #expect(refreshes.values == [.inlayHint, .diagnostics])
    }

    @Test
    func unknownRequestsFailWithMethodNotFound() async throws {
        let refreshes = LSPTestRecorder<LSPRefreshKind>()
        let replies = LSPTestRecorder<Result<LSPAny, AnyJSONRPCResponseError>>()
        let environment = LSPClientRequestEnvironment(refresh: { refreshes.append($0) })
        await makeHandler(environment: environment).handle(.custom("vendor/doThing", ["a": 1], { replies.append($0) }))
        #expect(replies.values.count == 1)
        let reply = try #require(replies.values.first)
        guard case let .failure(error) = reply else {
            Issue.record("Expected a failure reply")
            return
        }
        #expect(error.code == -32601)
        #expect(error.message == "Method not found: vendor/doThing")
        #expect(refreshes.values.isEmpty)
    }

    @Test
    func showMessageRequestReturnsTheChosenAction() async {
        let seen = LSPTestRecorder<ShowMessageRequestParams>()
        let retry = MessageActionItem(title: "Retry")
        let environment = LSPClientRequestEnvironment(showMessage: { params in
            seen.append(params)
            return params.actions?.first { $0 == retry }
        })
        let params = ShowMessageRequestParams(
            type: .warning,
            message: "Failed",
            actions: [MessageActionItem(title: "Ignore"), retry]
        )
        let replies = LSPTestRecorder<Result<ShowMessageRequestResponse, AnyJSONRPCResponseError>>()
        await makeHandler(environment: environment).handle(.windowShowMessageRequest(params, { replies.append($0) }))
        #expect(seen.values == [params])
        #expect(replies.values == [.success(retry)])
    }

    @Test
    func showMessageRequestWithoutPresenterRepliesWithNull() async {
        let replies = LSPTestRecorder<Result<ShowMessageRequestResponse, AnyJSONRPCResponseError>>()
        let params = ShowMessageRequestParams(
            type: .info,
            message: "Hello",
            actions: [MessageActionItem(title: "OK")]
        )
        await makeHandler().handle(.windowShowMessageRequest(params, { replies.append($0) }))
        let expected: Result<ShowMessageRequestResponse, AnyJSONRPCResponseError> = .success(nil)
        #expect(replies.values == [expected])
    }

    @Test
    func showMessageRequestDismissedByTheUserRepliesWithNull() async {
        let environment = LSPClientRequestEnvironment(showMessage: { _ in nil })
        let replies = LSPTestRecorder<Result<ShowMessageRequestResponse, AnyJSONRPCResponseError>>()
        let params = ShowMessageRequestParams(type: .info, message: "Hello", actions: [MessageActionItem(title: "OK")])
        await makeHandler(environment: environment).handle(.windowShowMessageRequest(params, { replies.append($0) }))
        let expected: Result<ShowMessageRequestResponse, AnyJSONRPCResponseError> = .success(nil)
        #expect(replies.values == [expected])
    }

    @Test
    func showDocumentReportsWhetherTheDocumentWasShown() async {
        let seen = LSPTestRecorder<ShowDocumentParams>()
        let environment = LSPClientRequestEnvironment(showDocument: { params in
            seen.append(params)
            return params.uri.hasSuffix("known.swift")
        })
        let handler = makeHandler(environment: environment)
        let replies = LSPTestRecorder<Result<ShowDocumentResult, AnyJSONRPCResponseError>>()
        let known = ShowDocumentParams(uri: "file:///p/known.swift", takeFocus: true)
        let missing = ShowDocumentParams(uri: "file:///p/missing.swift")
        await handler.handle(.windowShowDocument(known, { replies.append($0) }))
        await handler.handle(.windowShowDocument(missing, { replies.append($0) }))
        #expect(seen.values == [known, missing])
        let shown = ShowDocumentResult(success: true)
        let hidden = ShowDocumentResult(success: false)
        #expect(replies.values == [.success(shown), .success(hidden)])
    }

    @Test
    func workDoneProgressCreateTracksTheTokenAndRepliesOnce() async {
        let progress = LSPWorkDoneProgressTracker()
        let replies = LSPTestRecorder<AnyJSONRPCResponseError?>()
        let token = ProgressToken.optionB("indexing")
        await makeHandler(progress: progress).handle(
            .windowWorkDoneProgressCreate(WorkDoneProgressCreateParams(token: token), { replies.append($0) })
        )
        #expect(replies.values == [nil])
        #expect(progress.trackedTokenCount == 1)
        #expect(progress.progress(for: token)?.hasBegun == false)
        #expect(progress.activeProgresses.isEmpty)
    }

    @Test
    func workDoneProgressCreateAfterShutdownStillReplies() async {
        let progress = LSPWorkDoneProgressTracker()
        progress.shutDown()
        let replies = LSPTestRecorder<AnyJSONRPCResponseError?>()
        await makeHandler(progress: progress).handle(
            .windowWorkDoneProgressCreate(WorkDoneProgressCreateParams(token: .optionA(7)), { replies.append($0) })
        )
        #expect(replies.values == [nil])
        #expect(progress.trackedTokenCount == 0)
    }

    @Test
    func applyEditThroughTheExecutorWritesTheFileAndReportsSuccess() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("a.txt")
        try "hello world".write(to: file, atomically: true, encoding: .utf8)
        let executor = LSPWorkspaceEditExecutor(workspaceRoot: directory.url)
        let environment = LSPClientRequestEnvironment(applyEdit: { await executor.apply($0.edit) })
        let edit = WorkspaceEdit(
            changes: [file.absoluteString: [lspTextEdit((0, 0), (0, 5), "goodbye")]],
            documentChanges: nil
        )
        let replies = LSPTestRecorder<Result<ApplyWorkspaceEditResult, AnyJSONRPCResponseError>>()
        await makeHandler(environment: environment).handle(
            .workspaceApplyEdit(ApplyWorkspaceEditParams(edit: edit), { replies.append($0) })
        )
        #expect(replies.values == [.success(ApplyWorkspaceEditResult(applied: true))])
        #expect(try String(contentsOf: file, encoding: .utf8) == "goodbye world")
    }

    @Test
    func applyEditThroughTheExecutorReportsTheFailureReason() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let missing = directory.url.appendingPathComponent("missing.txt")
        let executor = LSPWorkspaceEditExecutor(workspaceRoot: directory.url)
        let environment = LSPClientRequestEnvironment(applyEdit: { await executor.apply($0.edit) })
        let edit = WorkspaceEdit(
            changes: [missing.absoluteString: [lspTextEdit((0, 0), (0, 0), "x")]],
            documentChanges: nil
        )
        let replies = LSPTestRecorder<Result<ApplyWorkspaceEditResult, AnyJSONRPCResponseError>>()
        await makeHandler(environment: environment).handle(
            .workspaceApplyEdit(ApplyWorkspaceEditParams(edit: edit), { replies.append($0) })
        )
        let reply = try #require(replies.values.first)
        let result = try reply.get()
        #expect(replies.values.count == 1)
        #expect(result.applied == false)
        #expect(result.failedChange == 0)
        #expect(result.failureReason == "The file does not exist: \(missing.absoluteString)")
    }
}
