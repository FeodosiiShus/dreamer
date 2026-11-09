import Foundation
import JSONRPC
import LanguageServerProtocol
import Synchronization
import Testing
@testable import Dreamder

@Suite
struct LSPClientRequestHandlerTests {
    func makeHandler(
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
}
