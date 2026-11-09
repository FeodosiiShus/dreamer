import Foundation
import JSONRPC
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

private final class LSPTestRecorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

private func lspDecode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(json.utf8))
}

private func lspTextEdit(_ start: (Int, Int), _ end: (Int, Int), _ text: String) -> TextEdit {
    TextEdit(range: LSPRange(startPair: start, endPair: end), newText: text)
}

private func lspRegistrations(_ pairs: [(id: String, method: String)]) -> RegistrationParams {
    RegistrationParams(registrations: pairs.map { Registration(id: $0.id, method: $0.method) })
}

private func lspUnregistrations(_ pairs: [(id: String, method: String)]) throws -> UnregistrationParams {
    let items = pairs.map { #"{"id":"\#($0.id)","method":"\#($0.method)"}"# }.joined(separator: ",")
    return try lspDecode(UnregistrationParams.self, #"{"unregistrations":[\#(items)]}"#)
}

@Suite
struct LSPClientRequestHandlerTests {
    private func makeHandler(
        environment: LSPClientRequestEnvironment = LSPClientRequestEnvironment(),
        capabilities: LSPDynamicCapabilityRegistry = LSPDynamicCapabilityRegistry(),
        progress: LSPWorkDoneProgressTracker = LSPWorkDoneProgressTracker(),
        repliesToCapabilityRegistration: Bool = true
    ) -> LSPClientRequestHandler {
        LSPClientRequestHandler(
            environment: environment,
            capabilities: capabilities,
            progress: progress,
            repliesToCapabilityRegistration: repliesToCapabilityRegistration
        )
    }

    private static let everyRequestName: [String] = [
        "configuration", "folders", "applyEdit", "register", "unregister", "codeLensRefresh",
        "semanticTokensRefresh", "showMessage", "showDocument", "progressCreate", "custom"
    ]

    private func everyRequest(_ recorder: LSPTestRecorder<String>) throws -> [ServerRequest] {
        var requests: [ServerRequest] = []
        requests.append(.workspaceConfiguration(
            ConfigurationParams(items: [ConfigurationItem(scopeUri: nil, section: "a")]),
            { _ in recorder.append("configuration") }
        ))
        requests.append(.workspaceFolders({ _ in recorder.append("folders") }))
        requests.append(.workspaceApplyEdit(
            ApplyWorkspaceEditParams(edit: WorkspaceEdit(changes: [:], documentChanges: nil)),
            { _ in recorder.append("applyEdit") }
        ))
        requests.append(.clientRegisterCapability(
            lspRegistrations([("1", "textDocument/hover")]),
            { _ in recorder.append("register") }
        ))
        requests.append(.clientUnregisterCapability(
            try lspUnregistrations([("1", "textDocument/hover")]),
            { _ in recorder.append("unregister") }
        ))
        requests.append(.workspaceCodeLensRefresh({ _ in recorder.append("codeLensRefresh") }))
        requests.append(.workspaceSemanticTokenRefresh({ _ in recorder.append("semanticTokensRefresh") }))
        requests.append(.windowShowMessageRequest(
            ShowMessageRequestParams(type: .info, message: "m", actions: [MessageActionItem(title: "OK")]),
            { _ in recorder.append("showMessage") }
        ))
        requests.append(.windowShowDocument(
            ShowDocumentParams(uri: "file:///tmp/a.swift"),
            { _ in recorder.append("showDocument") }
        ))
        requests.append(.windowWorkDoneProgressCreate(
            WorkDoneProgressCreateParams(token: .optionB("t")),
            { _ in recorder.append("progressCreate") }
        ))
        requests.append(.custom("vendor/unknown", .null, { _ in recorder.append("custom") }))
        return requests
    }

    @Test
    func everyRequestKindIsAnsweredExactlyOnce() async throws {
        let recorder = LSPTestRecorder<String>()
        let handler = makeHandler()
        for request in try everyRequest(recorder) {
            await handler.handle(request)
        }
        #expect(recorder.values == Self.everyRequestName)
    }

    @Test
    func everyRequestKindIsRejectedExactlyOnce() async throws {
        let recorder = LSPTestRecorder<String>()
        for request in try everyRequest(recorder) {
            await LSPClientRequestHandler.reject(request, message: "stopped")
        }
        #expect(recorder.values == Self.everyRequestName)
    }

    @Test
    func rejectRepliesWithTheGivenError() async {
        let replies = LSPTestRecorder<Result<[LSPAny], AnyJSONRPCResponseError>>()
        let errors = LSPTestRecorder<AnyJSONRPCResponseError?>()
        await LSPClientRequestHandler.reject(
            .workspaceConfiguration(ConfigurationParams(items: []), { replies.append($0) }),
            message: "stopped"
        )
        await LSPClientRequestHandler.reject(
            .workspaceCodeLensRefresh({ errors.append($0) }),
            code: LSPClientRequestHandler.methodNotFoundCode,
            message: "gone"
        )
        let expectedFailure = AnyJSONRPCResponseError(
            code: LSPClientRequestHandler.internalErrorCode,
            message: "stopped",
            data: nil
        )
        #expect(replies.values == [.failure(expectedFailure)])
        #expect(errors.values == [AnyJSONRPCResponseError(code: -32601, message: "gone", data: nil)])
    }

    @Test
    func configurationAnswersEachItemInOrderAndUsesNullForUnknownSections() async {
        let configuration = LSPWorkspaceConfiguration(settings: [
            "python": ["analysis": ["typeCheckingMode": "strict"]],
            "editor.tabSize": 4
        ])
        let environment = LSPClientRequestEnvironment(configuration: { configuration.value(for: $0) })
        let replies = LSPTestRecorder<Result<[LSPAny], AnyJSONRPCResponseError>>()
        let params = ConfigurationParams(items: [
            ConfigurationItem(scopeUri: nil, section: "python.analysis.typeCheckingMode"),
            ConfigurationItem(scopeUri: nil, section: "unknown"),
            ConfigurationItem(scopeUri: "file:///project/a.py", section: "editor.tabSize"),
            ConfigurationItem(scopeUri: nil, section: "python.analysis")
        ])
        await makeHandler(environment: environment).handle(.workspaceConfiguration(params, { replies.append($0) }))
        let expected: [LSPAny] = ["strict", .null, 4, ["typeCheckingMode": "strict"]]
        #expect(replies.values == [.success(expected)])
    }

    @Test
    func configurationWithoutItemsRepliesWithAnEmptyArray() async {
        let replies = LSPTestRecorder<Result<[LSPAny], AnyJSONRPCResponseError>>()
        await makeHandler().handle(.workspaceConfiguration(ConfigurationParams(items: []), { replies.append($0) }))
        let expected: [LSPAny] = []
        #expect(replies.values == [.success(expected)])
    }

    @Test
    func defaultEnvironmentAnswersEveryConfigurationItemWithNull() async {
        let replies = LSPTestRecorder<Result<[LSPAny], AnyJSONRPCResponseError>>()
        let params = ConfigurationParams(items: [
            ConfigurationItem(scopeUri: nil, section: "a"),
            ConfigurationItem(scopeUri: nil, section: nil)
        ])
        await makeHandler().handle(.workspaceConfiguration(params, { replies.append($0) }))
        let expected: [LSPAny] = [.null, .null]
        #expect(replies.values == [.success(expected)])
    }

    @Test
    func workspaceFoldersAreReturnedFromTheEnvironment() async {
        let folder = WorkspaceFolder(uri: "file:///project", name: "project")
        let folders = [folder]
        let environment = LSPClientRequestEnvironment(workspaceFolders: { folders })
        let replies = LSPTestRecorder<Result<WorkspaceFoldersResponse, AnyJSONRPCResponseError>>()
        await makeHandler(environment: environment).handle(.workspaceFolders({ replies.append($0) }))
        #expect(replies.values == [.success([folder])])
    }

    @Test
    func applyEditForwardsTheParamsAndRepliesWithTheResult() async {
        let seen = LSPTestRecorder<ApplyWorkspaceEditParams>()
        let environment = LSPClientRequestEnvironment(applyEdit: { params in
            seen.append(params)
            return ApplyWorkspaceEditResult(applied: true)
        })
        let params = ApplyWorkspaceEditParams(
            label: "Rename",
            edit: WorkspaceEdit(changes: ["file:///a": [lspTextEdit((0, 0), (0, 1), "x")]], documentChanges: nil)
        )
        let replies = LSPTestRecorder<Result<ApplyWorkspaceEditResult, AnyJSONRPCResponseError>>()
        await makeHandler(environment: environment).handle(.workspaceApplyEdit(params, { replies.append($0) }))
        #expect(seen.values == [params])
        #expect(replies.values == [.success(ApplyWorkspaceEditResult(applied: true))])
    }

    @Test
    func applyEditFailureReasonAndFailedChangeReachTheServer() async {
        let failure = ApplyWorkspaceEditResult(applied: false, failureReason: "File is read-only", failedChange: 2)
        let environment = LSPClientRequestEnvironment(applyEdit: { _ in failure })
        let replies = LSPTestRecorder<Result<ApplyWorkspaceEditResult, AnyJSONRPCResponseError>>()
        let params = ApplyWorkspaceEditParams(edit: WorkspaceEdit(changes: [:], documentChanges: nil))
        await makeHandler(environment: environment).handle(.workspaceApplyEdit(params, { replies.append($0) }))
        #expect(replies.values == [.success(failure)])
    }

    @Test
    func defaultEnvironmentRefusesToApplyEdits() async throws {
        let replies = LSPTestRecorder<Result<ApplyWorkspaceEditResult, AnyJSONRPCResponseError>>()
        let params = ApplyWorkspaceEditParams(edit: WorkspaceEdit(changes: [:], documentChanges: nil))
        await makeHandler().handle(.workspaceApplyEdit(params, { replies.append($0) }))
        let reply = try #require(replies.values.first)
        let result = try reply.get()
        #expect(result.applied == false)
        #expect(result.failureReason != nil)
        #expect(replies.values.count == 1)
    }

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
        await makeHandler(capabilities: capabilities).handle(.clientUnregisterCapability(params, { replies.append($0) }))
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
        #expect(replies.values == [.success(ShowDocumentResult(success: true)), .success(ShowDocumentResult(success: false))])
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
        let executor = LSPWorkspaceEditExecutor()
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
        let executor = LSPWorkspaceEditExecutor()
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

private struct LSPTestDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LSPClientRequestHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite
struct LSPDynamicCapabilityRegistryTests {
    @Test
    func registerAndUnregisterById() throws {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([
            Registration(id: "1", method: "textDocument/hover"),
            Registration(id: "2", method: "textDocument/hover"),
            Registration(id: "3", method: "textDocument/rename")
        ])
        #expect(registry.hasCapability("textDocument/hover"))
        #expect(registry.registrations(for: "textDocument/hover").map(\.id) == ["1", "2"])

        registry.unregister(try lspUnregistrations([("1", "textDocument/hover")]).unregistrations)
        #expect(registry.registrations(for: "textDocument/hover").map(\.id) == ["2"])
        #expect(registry.hasCapability("textDocument/hover"))

        registry.unregister(try lspUnregistrations([("2", "textDocument/hover")]).unregistrations)
        #expect(!registry.hasCapability("textDocument/hover"))
        #expect(registry.registeredMethods == ["textDocument/rename"])
    }

    @Test
    func unregisterRequiresMatchingMethodAndId() throws {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([Registration(id: "1", method: "textDocument/hover")])
        let unregistrations = try lspUnregistrations([("1", "textDocument/rename"), ("2", "textDocument/hover")])
        registry.unregister(unregistrations.unregistrations)
        #expect(registry.registrations(for: "textDocument/hover").map(\.id) == ["1"])
    }

    @Test
    func registeringTheSameIdTwiceReplacesTheEarlierRegistration() {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([Registration(id: "1", method: "textDocument/completion", registerOptions: ["a": 1])])
        registry.register([Registration(id: "1", method: "textDocument/completion", registerOptions: ["a": 2])])
        let stored = registry.registrations(for: "textDocument/completion")
        #expect(stored.count == 1)
        #expect(stored.first?.registerOptions == ["a": 2])
    }

    @Test
    func unknownMethodHasNoRegistrations() {
        let registry = LSPDynamicCapabilityRegistry()
        #expect(!registry.hasCapability("textDocument/hover"))
        #expect(registry.registrations(for: "textDocument/hover").isEmpty)
        let options = registry.registerOptions(for: "textDocument/hover", as: DidChangeWatchedFilesRegistrationOptions.self)
        #expect(options.isEmpty)
    }

    @Test
    func registerOptionsSkipRegistrationsThatDoNotDecode() {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([
            Registration(id: "1", method: "workspace/didChangeWatchedFiles", registerOptions: ["watchers": "invalid"]),
            Registration(id: "2", method: "workspace/didChangeWatchedFiles", registerOptions: nil),
            Registration(
                id: "3",
                method: "workspace/didChangeWatchedFiles",
                registerOptions: ["watchers": [["globPattern": "*.rs"]]]
            )
        ])
        let options = registry.registerOptions(
            for: "workspace/didChangeWatchedFiles",
            as: DidChangeWatchedFilesRegistrationOptions.self
        )
        #expect(options == [DidChangeWatchedFilesRegistrationOptions(watchers: [FileSystemWatcher(globPattern: "*.rs")])])
    }

    @Test
    func removeAllClearsEverything() {
        let registry = LSPDynamicCapabilityRegistry()
        registry.register([Registration(id: "1", method: "textDocument/hover")])
        registry.removeAll()
        #expect(registry.registeredMethods.isEmpty)
    }

    @Test
    func refreshKindsMapFromMethods() {
        #expect(LSPRefreshKind(refreshMethod: "workspace/semanticTokens/refresh") == .semanticTokens)
        #expect(LSPRefreshKind(refreshMethod: "workspace/inlayHint/refresh") == .inlayHint)
        #expect(LSPRefreshKind(refreshMethod: "workspace/diagnostic/refresh") == .diagnostics)
        #expect(LSPRefreshKind(refreshMethod: "workspace/codeLens/refresh") == nil)
        #expect(LSPRefreshKind(refreshMethod: "workspace/foldingRange/refresh") == nil)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/inlayHint") == .inlayHint)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/diagnostic") == .diagnostics)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/codeLens") == nil)
        #expect(LSPRefreshKind(registrationMethod: "textDocument/hover") == nil)
    }
}

@Suite
struct LSPWorkDoneProgressTrackerTests {
    private func begin(_ title: String, percentage: Double? = nil) -> LSPAny {
        var value: [String: LSPAny] = ["kind": "begin", "title": .string(title)]
        if let percentage {
            value["percentage"] = .number(percentage)
        }
        return .hash(value)
    }

    @Test
    func beginReportEndLifecycle() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionB("t")
        tracker.create(token)
        #expect(tracker.activeProgresses.isEmpty)

        #expect(tracker.apply(ProgressParams(token: token, value: begin("Indexing", percentage: 10))) == .began)
        #expect(tracker.progress(for: token) == LSPWorkDoneProgress(
            token: token, title: "Indexing", message: nil, percentage: 10, hasBegun: true
        ))

        let report: LSPAny = ["kind": "report", "message": "3/10", "percentage": 30]
        #expect(tracker.apply(ProgressParams(token: token, value: report)) == .reported)
        #expect(tracker.progress(for: token)?.message == "3/10")
        #expect(tracker.progress(for: token)?.percentage == 30)
        #expect(tracker.progress(for: token)?.title == "Indexing")

        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "end"])) == .ended)
        #expect(tracker.progress(for: token) == nil)
        #expect(tracker.trackedTokenCount == 0)
    }

    @Test
    func reportKeepsPreviousValuesWhenFieldsAreOmitted() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionA(1)
        tracker.apply(ProgressParams(token: token, value: begin("Build", percentage: 40)))
        tracker.apply(ProgressParams(token: token, value: ["kind": "report", "message": "step"]))
        let progress = tracker.progress(for: token)
        #expect(progress?.percentage == 40)
        #expect(progress?.message == "step")
    }

    @Test
    func percentageIsClamped() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionA(1)
        tracker.apply(ProgressParams(token: token, value: begin("Build", percentage: 250)))
        #expect(tracker.progress(for: token)?.percentage == 100)
        tracker.apply(ProgressParams(token: token, value: ["kind": "report", "percentage": -5]))
        #expect(tracker.progress(for: token)?.percentage == 0)
    }

    @Test
    func reportAndEndForUnknownTokensAreIgnored() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionB("unknown")
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "report", "message": "x"])) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "end"])) == .ignored)
        #expect(tracker.trackedTokenCount == 0)
    }

    @Test
    func reportForATokenThatOnlyWasCreatedIsIgnored() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionB("created")
        tracker.create(token)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "report", "message": "x"])) == .ignored)
        #expect(tracker.progress(for: token)?.message == nil)
    }

    @Test
    func malformedPayloadsAreIgnored() {
        let tracker = LSPWorkDoneProgressTracker()
        let token = ProgressToken.optionA(1)
        #expect(tracker.apply(ProgressParams(token: token, value: nil)) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: "begin")) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "begin"])) == .ignored)
        #expect(tracker.apply(ProgressParams(token: token, value: ["kind": "other", "title": "x"])) == .ignored)
        #expect(tracker.trackedTokenCount == 0)
    }

    @Test
    func integerAndStringTokensAreDistinct() {
        let tracker = LSPWorkDoneProgressTracker()
        tracker.apply(ProgressParams(token: .optionA(1), value: begin("number")))
        tracker.apply(ProgressParams(token: .optionB("1"), value: begin("string")))
        #expect(tracker.activeProgresses.count == 2)
        #expect(tracker.progress(for: .optionA(1))?.title == "number")
        #expect(tracker.progress(for: .optionB("1"))?.title == "string")
    }

    @Test
    func shutDownDropsEverythingAndRejectsLaterBegins() {
        let tracker = LSPWorkDoneProgressTracker()
        tracker.create(.optionA(1))
        tracker.apply(ProgressParams(token: .optionA(2), value: begin("running")))
        tracker.shutDown()
        #expect(tracker.isShutDown)
        #expect(tracker.trackedTokenCount == 0)
        #expect(tracker.apply(ProgressParams(token: .optionA(3), value: begin("late"))) == .ignored)
        #expect(!tracker.create(.optionA(4)))
        #expect(tracker.trackedTokenCount == 0)
    }
}

@Suite
struct LSPWorkspaceConfigurationTests {
    private let configuration = LSPWorkspaceConfiguration(settings: [
        "python": ["analysis": ["mode": "strict", "paths": ["src"]], "flag": true],
        "typescript.format.semicolons": "insert",
        "typescript": ["format": ["indent": 2]],
        "scalar": 1
    ])

    private func value(_ section: String?) -> LSPAny? {
        configuration.value(for: ConfigurationItem(scopeUri: nil, section: section))
    }

    @Test
    func exactAndNestedSectionsResolve() {
        #expect(value("scalar") == 1)
        #expect(value("python.flag") == true)
        #expect(value("python.analysis.mode") == "strict")
        #expect(value("python.analysis") == ["mode": "strict", "paths": ["src"]])
    }

    @Test
    func flatDottedKeysTakePartInResolution() {
        #expect(value("typescript.format.semicolons") == "insert")
        #expect(value("typescript.format.indent") == 2)
    }

    @Test
    func unknownSectionsAreNil() {
        #expect(value("rust") == nil)
        #expect(value("python.analysis.unknown") == nil)
        #expect(value("scalar.nested") == nil)
        #expect(value("python..flag") == nil)
    }

    @Test
    func missingSectionReturnsAllSettingsOrNil() {
        #expect(value(nil) == .hash(configuration.settings))
        #expect(value("") == .hash(configuration.settings))
        #expect(LSPWorkspaceConfiguration().value(for: ConfigurationItem(scopeUri: nil, section: nil)) == nil)
    }

    @Test
    func workspaceFolderUsesTheRootUriFormat() {
        #expect(LSPWorkspaceFolders.folder(forWorkspacePath: "/Users/me/project")
            == WorkspaceFolder(uri: "file:///Users/me/project", name: "project"))
    }
}

@Suite
struct LSPTextEditApplierTests {
    private func apply(_ text: String, _ edits: [TextEdit]) throws -> String {
        try LSPTextEditApplier.apply(edits, to: text)
    }

    @Test
    func editsUseCoordinatesOfTheOriginalText() throws {
        let result = try apply("hello world", [
            lspTextEdit((0, 6), (0, 11), "there"),
            lspTextEdit((0, 0), (0, 5), "goodbye")
        ])
        #expect(result == "goodbye there")
    }

    @Test
    func insertionsAtTheSamePositionKeepArrayOrder() throws {
        let result = try apply("ab", [
            lspTextEdit((0, 1), (0, 1), "X"),
            lspTextEdit((0, 1), (0, 1), "Y")
        ])
        #expect(result == "aXYb")
    }

    @Test
    func insertionAtTheStartOfAReplacementComesFirstWhateverTheOrder() throws {
        let result = try apply("abc", [
            lspTextEdit((0, 0), (0, 1), "X"),
            lspTextEdit((0, 0), (0, 0), "Y")
        ])
        #expect(result == "YXbc")
    }

    @Test
    func overlappingEditsAreRejected() {
        #expect(throws: LSPWorkspaceEditError.overlappingEdits) {
            try apply("abcdef", [lspTextEdit((0, 0), (0, 4), "x"), lspTextEdit((0, 2), (0, 5), "y")])
        }
        #expect(throws: LSPWorkspaceEditError.overlappingEdits) {
            try apply("abcdef", [lspTextEdit((0, 0), (0, 4), "x"), lspTextEdit((0, 2), (0, 2), "y")])
        }
    }

    @Test
    func adjacentEditsAreAllowed() throws {
        #expect(try apply("abcd", [lspTextEdit((0, 0), (0, 2), "X"), lspTextEdit((0, 2), (0, 4), "Y")]) == "XY")
    }

    @Test
    func rangesThatEndBeforeTheyStartAreRejected() {
        let range = LSPRange(startPair: (0, 3), endPair: (0, 1))
        #expect(throws: LSPWorkspaceEditError.invalidRange(range)) {
            try apply("abcd", [TextEdit(range: range, newText: "x")])
        }
    }

    @Test
    func linesOutsideTheDocumentAreRejectedButTheLineAfterATrailingNewlineIsValid() throws {
        #expect(try apply("a\n", [lspTextEdit((1, 0), (1, 0), "b")]) == "a\nb")
        #expect(throws: LSPWorkspaceEditError.lineOutOfRange(line: 2, lineCount: 2)) {
            try apply("a\n", [lspTextEdit((2, 0), (2, 0), "b")])
        }
        #expect(throws: LSPWorkspaceEditError.lineOutOfRange(line: -1, lineCount: 1)) {
            try apply("a", [lspTextEdit((-1, 0), (0, 0), "b")])
        }
    }

    @Test
    func charactersBeyondTheLineEndClampToTheLineEnd() throws {
        #expect(try apply("ab\ncd", [lspTextEdit((0, 99), (0, 99), "!")]) == "ab!\ncd")
    }

    @Test
    func lineTerminatorsOfAllKindsStartNewLines() throws {
        #expect(try apply("a\r\nb", [lspTextEdit((1, 0), (1, 0), "X")]) == "a\r\nXb")
        #expect(try apply("a\rb", [lspTextEdit((1, 0), (1, 0), "X")]) == "a\rXb")
        #expect(try apply("a\nb", [lspTextEdit((1, 1), (1, 1), "X")]) == "a\nbX")
        #expect(try apply("a\r\n\r\nb", [lspTextEdit((2, 0), (2, 1), "X")]) == "a\r\n\r\nX")
    }

    @Test
    func positionsCountUTF16CodeUnits() throws {
        #expect(try apply("😀x", [lspTextEdit((0, 2), (0, 3), "y")]) == "😀y")
        #expect(try apply("é😀", [lspTextEdit((0, 1), (0, 3), "")]) == "é")
    }

    @Test
    func noEditsLeaveTheTextUntouched() throws {
        #expect(try apply("same\ntext", []) == "same\ntext")
    }

    @Test
    func resolvedEditsAreSortedAndCarryTheirNSRanges() throws {
        let first = lspTextEdit((1, 0), (1, 1), "B")
        let second = lspTextEdit((0, 0), (0, 1), "A")
        let resolved = try LSPTextEditApplier.resolve([first, second], in: "xx\nyy")
        #expect(resolved == [
            LSPResolvedTextEdit(edit: second, range: NSRange(location: 0, length: 1)),
            LSPResolvedTextEdit(edit: first, range: NSRange(location: 3, length: 1))
        ])
    }
}

@Suite
struct LSPWorkspaceEditPlanTests {
    @Test
    func changesAreOrderedByUri() {
        let edit = WorkspaceEdit(
            changes: [
                "file:///b": [lspTextEdit((0, 0), (0, 0), "b")],
                "file:///a": [lspTextEdit((0, 0), (0, 0), "a")]
            ],
            documentChanges: nil
        )
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .editText(uri: "file:///a", edits: [lspTextEdit((0, 0), (0, 0), "a")]),
            .editText(uri: "file:///b", edits: [lspTextEdit((0, 0), (0, 0), "b")])
        ])
    }

    @Test
    func documentChangesTakePrecedenceOverChanges() throws {
        let edit = try lspDecode(WorkspaceEdit.self, """
        {
          "changes": {"file:///ignored": []},
          "documentChanges": [
            {"textDocument": {"uri": "file:///a", "version": 3},
             "edits": [{"range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 1}}, "newText": "x"}]},
            {"kind": "create", "uri": "file:///new", "options": {"overwrite": true}},
            {"kind": "rename", "oldUri": "file:///old", "newUri": "file:///renamed", "options": {"ignoreIfExists": true}}
          ]
        }
        """)
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .editText(uri: "file:///a", edits: [lspTextEdit((0, 0), (0, 1), "x")]),
            .createFile(uri: "file:///new", overwrite: true, ignoreIfExists: false),
            .renameFile(oldURI: "file:///old", newURI: "file:///renamed", overwrite: false, ignoreIfExists: true)
        ])
    }

    @Test
    func deleteDecodedAsCreateFileByThePackageBecomesADelete() throws {
        let edit = try lspDecode(WorkspaceEdit.self, """
        {"documentChanges": [{"kind": "delete", "uri": "file:///gone"}]}
        """)
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .deleteFile(uri: "file:///gone", recursive: false, ignoreIfNotExists: false)
        ])
    }

    @Test
    func deleteOptionsAreCarriedOver() {
        let delete = DeleteFile(
            kind: "delete",
            uri: "file:///dir",
            options: DeleteFileOptions(recursive: true, ignoreIfNotExists: true)
        )
        let edit = WorkspaceEdit(changes: nil, documentChanges: [.deleteFile(delete)])
        #expect(LSPWorkspaceEditPlan.operations(for: edit) == [
            .deleteFile(uri: "file:///dir", recursive: true, ignoreIfNotExists: true)
        ])
    }

    @Test
    func emptyEditHasNoOperations() {
        #expect(LSPWorkspaceEditPlan.operations(for: WorkspaceEdit(changes: nil, documentChanges: nil)).isEmpty)
    }
}

@Suite
struct LSPWorkspaceEditExecutorTests {
    private func edit(_ json: String) throws -> WorkspaceEdit {
        try lspDecode(WorkspaceEdit.self, json)
    }

    private func createEdit(_ uri: String, options: String? = nil) throws -> WorkspaceEdit {
        let options = options.map { #","options":\#($0)"# } ?? ""
        return try edit(#"{"documentChanges":[{"kind":"create","uri":"\#(uri)"\#(options)}]}"#)
    }

    private func renameEdit(_ source: URL, _ target: URL, options: String = "{}") throws -> WorkspaceEdit {
        try edit("""
        {"documentChanges":[{"kind":"rename",
          "oldUri":"\(source.absoluteString)",
          "newUri":"\(target.absoluteString)",
          "options":\(options)}]}
        """)
    }

    @Test
    func textEditsAreWrittenToFilesThatAreNotOpen() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("a.txt")
        try "one\ntwo".write(to: file, atomically: true, encoding: .utf8)
        let workspaceEdit = WorkspaceEdit(
            changes: [file.absoluteString: [lspTextEdit((1, 0), (1, 3), "2"), lspTextEdit((0, 0), (0, 3), "1")]],
            documentChanges: nil
        )
        let result = await LSPWorkspaceEditExecutor().apply(workspaceEdit)
        #expect(result == ApplyWorkspaceEditResult(applied: true))
        #expect(try String(contentsOf: file, encoding: .utf8) == "1\n2")
    }

    @Test
    func openDocumentsAreEditedThroughTheInjectedEditorOnly() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("open.txt")
        try "disk".write(to: file, atomically: true, encoding: .utf8)
        let seen = LSPTestRecorder<String>()
        let executor = LSPWorkspaceEditExecutor(editOpenDocument: { uri, edits in
            seen.append("\(uri)#\(edits.count)")
            return true
        })
        let workspaceEdit = WorkspaceEdit(
            changes: [file.absoluteString: [lspTextEdit((0, 0), (0, 4), "memory")]],
            documentChanges: nil
        )
        let result = await executor.apply(workspaceEdit)
        #expect(result.applied)
        #expect(seen.values == ["\(file.absoluteString)#1"])
        #expect(try String(contentsOf: file, encoding: .utf8) == "disk")
    }

    @Test
    func openDocumentEditorFailuresAreReportedWithTheChangeIndex() async throws {
        struct EditorFailure: LocalizedError {
            var errorDescription: String? { "editor refused" }
        }
        let executor = LSPWorkspaceEditExecutor(editOpenDocument: { _, _ in throw EditorFailure() })
        let workspaceEdit = WorkspaceEdit(
            changes: ["file:///nowhere": [lspTextEdit((0, 0), (0, 0), "x")]],
            documentChanges: nil
        )
        let result = await executor.apply(workspaceEdit)
        #expect(result == ApplyWorkspaceEditResult(applied: false, failureReason: "editor refused", failedChange: 0))
    }

    @Test
    func theFirstFailureStopsTheEditAndNamesTheFailedChange() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let first = directory.url.appendingPathComponent("first.txt")
        let third = directory.url.appendingPathComponent("third.txt")
        try "a".write(to: first, atomically: true, encoding: .utf8)
        try "c".write(to: third, atomically: true, encoding: .utf8)
        let missing = directory.url.appendingPathComponent("missing.txt")
        let insert = [lspTextEdit((0, 1), (0, 1), "!")]
        let workspaceEdit = WorkspaceEdit(changes: nil, documentChanges: [
            .textDocumentEdit(TextDocumentEdit(
                textDocument: VersionedTextDocumentIdentifier(uri: first.absoluteString, version: nil),
                edits: insert
            )),
            .textDocumentEdit(TextDocumentEdit(
                textDocument: VersionedTextDocumentIdentifier(uri: missing.absoluteString, version: nil),
                edits: insert
            )),
            .textDocumentEdit(TextDocumentEdit(
                textDocument: VersionedTextDocumentIdentifier(uri: third.absoluteString, version: nil),
                edits: insert
            ))
        ])
        let result = await LSPWorkspaceEditExecutor().apply(workspaceEdit)
        #expect(result.applied == false)
        #expect(result.failedChange == 1)
        #expect(result.failureReason == "The file does not exist: \(missing.absoluteString)")
        #expect(try String(contentsOf: first, encoding: .utf8) == "a!")
        #expect(try String(contentsOf: third, encoding: .utf8) == "c")
    }

    @Test
    func overlappingTextEditsFailWithoutTouchingTheFile() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("a.txt")
        try "abcdef".write(to: file, atomically: true, encoding: .utf8)
        let workspaceEdit = WorkspaceEdit(
            changes: [file.absoluteString: [lspTextEdit((0, 0), (0, 4), "x"), lspTextEdit((0, 2), (0, 5), "y")]],
            documentChanges: nil
        )
        let result = await LSPWorkspaceEditExecutor().apply(workspaceEdit)
        #expect(result == ApplyWorkspaceEditResult(applied: false, failureReason: "Text edits overlap", failedChange: 0))
        #expect(try String(contentsOf: file, encoding: .utf8) == "abcdef")
    }

    @Test
    func nonFileUrisAreRejected() async {
        let workspaceEdit = WorkspaceEdit(
            changes: ["untitled:Untitled-1": [lspTextEdit((0, 0), (0, 0), "x")]],
            documentChanges: nil
        )
        let result = await LSPWorkspaceEditExecutor().apply(workspaceEdit)
        #expect(result.applied == false)
        #expect(result.failureReason == "Unsupported document URI: untitled:Untitled-1")
    }

    @Test
    func editsOutsideTheDocumentOrWithReversedRangesReportTheirReason() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("a.txt")
        try "one".write(to: file, atomically: true, encoding: .utf8)
        let uri = file.absoluteString
        let reversedRange = LSPRange(startPair: (0, 3), endPair: (0, 1))
        let outside = WorkspaceEdit(changes: [uri: [lspTextEdit((5, 0), (5, 0), "x")]], documentChanges: nil)
        let reversed = WorkspaceEdit(changes: [uri: [TextEdit(range: reversedRange, newText: "x")]], documentChanges: nil)
        let executor = LSPWorkspaceEditExecutor()

        #expect(await executor.apply(outside) == ApplyWorkspaceEditResult(
            applied: false,
            failureReason: "Line 5 is outside the document (1 lines)",
            failedChange: 0
        ))
        #expect(await executor.apply(reversed) == ApplyWorkspaceEditResult(
            applied: false,
            failureReason: "Range \(reversedRange) ends before it starts",
            failedChange: 0
        ))
        #expect(try String(contentsOf: file, encoding: .utf8) == "one")
    }

    @Test
    func filesThatAreNotUTF8CannotBeEdited() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("binary.dat")
        let bytes = Data([0xFF, 0xFE, 0xFD])
        try bytes.write(to: file)
        let workspaceEdit = WorkspaceEdit(
            changes: [file.absoluteString: [lspTextEdit((0, 0), (0, 0), "x")]],
            documentChanges: nil
        )

        let result = await LSPWorkspaceEditExecutor().apply(workspaceEdit)

        #expect(result == ApplyWorkspaceEditResult(
            applied: false,
            failureReason: "The file cannot be decoded as UTF-8: \(file.absoluteString)",
            failedChange: 0
        ))
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test
    func createFileReportsAFileSystemThatRefusesTheNewFile() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let locked = directory.url.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let target = locked.appendingPathComponent("new.txt")
        let creation = try createEdit(target.absoluteString)

        let result = await LSPWorkspaceEditExecutor().apply(creation)

        #expect(result == ApplyWorkspaceEditResult(
            applied: false,
            failureReason: "The file could not be created: \(target.absoluteString)",
            failedChange: 0
        ))
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func createFileHonoursOverwriteAndIgnoreIfExists() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("nested/dir/new.txt")
        let uri = file.absoluteString
        let plain = try createEdit(uri)
        let ignoring = try createEdit(uri, options: #"{"ignoreIfExists":true}"#)
        let overwriting = try createEdit(uri, options: #"{"overwrite":true}"#)
        let executor = LSPWorkspaceEditExecutor()

        #expect(await executor.apply(plain).applied)
        #expect(try String(contentsOf: file, encoding: .utf8) == "")

        try "keep".write(to: file, atomically: true, encoding: .utf8)
        let duplicate = await executor.apply(plain)
        #expect(duplicate == ApplyWorkspaceEditResult(
            applied: false,
            failureReason: "The file already exists: \(uri)",
            failedChange: 0
        ))
        #expect(await executor.apply(ignoring).applied)
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep")

        #expect(await executor.apply(overwriting).applied)
        #expect(try String(contentsOf: file, encoding: .utf8) == "")
    }

    @Test
    func renameFileMovesTheFileAndHonoursExistingTargets() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appendingPathComponent("a.txt")
        let target = directory.url.appendingPathComponent("sub/b.txt")
        try "a".write(to: source, atomically: true, encoding: .utf8)
        let rename = try renameEdit(source, target)
        let executor = LSPWorkspaceEditExecutor()
        #expect(await executor.apply(rename).applied)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: target, encoding: .utf8) == "a")

        try "again".write(to: source, atomically: true, encoding: .utf8)
        let blocked = await executor.apply(rename)
        #expect(blocked.applied == false)
        #expect(blocked.failureReason == "The file already exists: \(target.absoluteString)")

        let ignoring = try renameEdit(source, target, options: #"{"ignoreIfExists":true}"#)
        #expect(await executor.apply(ignoring).applied)
        #expect(try String(contentsOf: target, encoding: .utf8) == "a")
        #expect(FileManager.default.fileExists(atPath: source.path))

        let overwriting = try renameEdit(source, target, options: #"{"overwrite":true}"#)
        #expect(await executor.apply(overwriting).applied)
        #expect(try String(contentsOf: target, encoding: .utf8) == "again")
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func renameOfAMissingSourceFails() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let source = directory.url.appendingPathComponent("missing.txt")
        let target = directory.url.appendingPathComponent("b.txt")
        let rename = try renameEdit(source, target)
        let result = await LSPWorkspaceEditExecutor().apply(rename)
        #expect(result.applied == false)
        #expect(result.failureReason == "The file does not exist: \(source.absoluteString)")
    }

    @Test
    func deleteFileRespectsRecursiveAndIgnoreIfNotExists() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let folder = directory.url.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        let missing = directory.url.appendingPathComponent("missing.txt")
        let executor = LSPWorkspaceEditExecutor()

        func deletion(_ url: URL, recursive: Bool?, ignoreIfNotExists: Bool?) -> WorkspaceEdit {
            WorkspaceEdit(changes: nil, documentChanges: [.deleteFile(DeleteFile(
                kind: "delete",
                uri: url.absoluteString,
                options: DeleteFileOptions(recursive: recursive, ignoreIfNotExists: ignoreIfNotExists)
            ))])
        }

        let nonEmpty = await executor.apply(deletion(folder, recursive: false, ignoreIfNotExists: nil))
        #expect(nonEmpty.applied == false)
        #expect(nonEmpty.failureReason == "The directory is not empty: \(folder.absoluteString)")
        #expect(FileManager.default.fileExists(atPath: folder.path))

        let absent = await executor.apply(deletion(missing, recursive: nil, ignoreIfNotExists: nil))
        #expect(absent.applied == false)
        #expect(absent.failureReason == "The file does not exist: \(missing.absoluteString)")
        #expect(await executor.apply(deletion(missing, recursive: nil, ignoreIfNotExists: true)).applied)

        #expect(await executor.apply(deletion(folder, recursive: true, ignoreIfNotExists: nil)).applied)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test
    func createThenEditInOneWorkspaceEditSeesTheNewFile() async throws {
        let directory = try LSPTestDirectory()
        defer { directory.remove() }
        let file = directory.url.appendingPathComponent("created.txt")
        let uri = file.absoluteString
        let workspaceEdit = try edit("""
        {"documentChanges": [
          {"kind": "create", "uri": "\(uri)"},
          {"textDocument": {"uri": "\(uri)", "version": null},
           "edits": [{"range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}}, "newText": "hi"}]}
        ]}
        """)
        let result = await LSPWorkspaceEditExecutor().apply(workspaceEdit)
        #expect(result.applied)
        #expect(try String(contentsOf: file, encoding: .utf8) == "hi")
    }
}

@Suite
struct LSPShowDocumentPlanTests {
    @Test
    func webAndMailUrisOpenExternally() throws {
        let docs = try #require(URL(string: "https://example.com/docs"))
        let plain = try #require(URL(string: "http://example.com"))
        let mail = try #require(URL(string: "mailto:a@example.com"))
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: docs.absoluteString)) == .external(docs))
        #expect(LSPShowDocumentPlan.make(
            for: ShowDocumentParams(uri: plain.absoluteString, takeFocus: false)
        ) == .external(plain))
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: mail.absoluteString)) == .external(mail))
    }

    @Test
    func fileUrisOpenInTheEditorWithTheSelectionAndFocusPreference() {
        let selection = LSPRange(startPair: (2, 1), endPair: (2, 5))
        let plan = LSPShowDocumentPlan.make(
            for: ShowDocumentParams(uri: "file:///project/a.swift", takeFocus: false, selection: selection)
        )
        #expect(plan == .editor(URL(fileURLWithPath: "/project/a.swift"), selection: selection, takeFocus: false))
    }

    @Test
    func takeFocusDefaultsToTrue() {
        let plan = LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "file:///project/a.swift"))
        #expect(plan == .editor(URL(fileURLWithPath: "/project/a.swift"), selection: nil, takeFocus: true))
    }

    @Test
    func externalFlagSendsFilesToTheSystem() {
        let plan = LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "file:///project/a.pdf", external: true))
        #expect(plan == .external(URL(fileURLWithPath: "/project/a.pdf")))
    }

    @Test
    func unsupportedSchemesAreInvalid() {
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "untitled:Untitled-1")) == .invalid)
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "jar:file:///a.jar!/B.class")) == .invalid)
        #expect(LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "")) == .invalid)
    }

    @Test
    func fileUriWithUnencodedSpacesResolvesToThePath() {
        let plan = LSPShowDocumentPlan.make(for: ShowDocumentParams(uri: "file:///tmp/a b.swift"))
        guard case let .editor(url, _, _) = plan else {
            Issue.record("Expected an editor plan")
            return
        }
        #expect(url.path == "/tmp/a b.swift")
    }
}

@Suite
struct LSPFileURITests {
    @Test
    func wellFormedFileUrisParseDirectly() {
        #expect(LSPFileURI.fileURL(from: "file:///tmp/a.swift")?.path == "/tmp/a.swift")
    }

    @Test
    func fileUrisWithMalformedAuthoritiesFallBackToThePathAfterThePrefix() throws {
        let url = try #require(LSPFileURI.fileURL(from: "file://localhost:abc/tmp/a.swift"))
        #expect(url.isFileURL)
        #expect(url.lastPathComponent == "a.swift")
    }

    @Test
    func otherSchemesAreRejected() {
        #expect(LSPFileURI.fileURL(from: "untitled:Untitled-1") == nil)
        #expect(LSPFileURI.fileURL(from: "https://example.com/a.swift") == nil)
        #expect(LSPFileURI.fileURL(from: "") == nil)
    }
}
