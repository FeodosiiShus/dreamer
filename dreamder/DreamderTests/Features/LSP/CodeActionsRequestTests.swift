import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension ScriptedServerConnection {
    var codeActionParams: [CodeActionParams] {
        requests.compactMap { request in
            guard case let .codeAction(params, _) = request else { return nil }
            return params
        }
    }

    var codeActionResolveParams: [CodeAction] {
        requests.compactMap { request in
            guard case let .codeActionResolve(action, _) = request else { return nil }
            return action
        }
    }

    var executeCommandParams: [ExecuteCommandParams] {
        requests.compactMap { request in
            guard case let .workspaceExecuteCommand(params, _) = request else { return nil }
            return params
        }
    }
}

@MainActor
struct CodeActionsHarness {
    typealias Response = [TwoTypeOption<LSPCommand, CodeAction>]

    let fixture: LSPServiceFixture
    let service: LSPService
    let workspace: LSPServiceWorkspace
    let document: CodeFileDocument
    let client: LSPService.LanguageServerType
    let connection: ScriptedServerConnection

    var uri: String { workspace.uri("main.swift") }

    static func capabilities(resolve: Bool, supported: Bool = true) -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        if supported {
            capabilities.codeActionProvider = .optionB(
                CodeActionOptions(workDoneProgress: nil, codeActionKinds: nil, resolveProvider: resolve)
            )
        }
        return capabilities
    }

    static func make(
        in directory: URL,
        text: String = "let a = 1\nlet b = 2\n",
        extraFiles: [String: String] = [:],
        capabilities: ServerCapabilities = CodeActionsHarness.capabilities(resolve: true)
    ) async throws -> CodeActionsHarness {
        let fixture = LSPServiceFixture()
        fixture.capabilities = capabilities
        let service = fixture.makeService()
        var files = extraFiles
        files["main.swift"] = text
        let workspace = try LSPServiceWorkspace(directory: directory, files: files)
        let document = try workspace.document("main.swift")
        service.openDocument(document)
        await service.waitForDocumentOperations()
        let created = try #require(fixture.created.first)
        let documentURL = try #require(document.fileURL)
        let client = try #require(service.languageClient(forDocument: documentURL))
        return CodeActionsHarness(
            fixture: fixture,
            service: service,
            workspace: workspace,
            document: document,
            client: client,
            connection: created.connection
        )
    }

    func request(
        range: LSPRange = LSPRange(startPair: (0, 4), endPair: (0, 5)),
        diagnostics: [Diagnostic] = []
    ) -> CodeActionRequest {
        CodeActionRequest(client: client, documentURI: uri, range: range, diagnostics: diagnostics)
    }

    func script(_ response: Response) throws {
        try connection.script(.textDocumentCodeAction, response)
    }

    func intention(_ action: CodeAction) -> IntentionAction {
        IntentionAction(
            id: action.title,
            title: action.title,
            category: .quickFix,
            isPreferred: false,
            payload: .codeAction(action)
        )
    }

    func replaceFirstLineEdit(_ text: String) -> WorkspaceEdit {
        WorkspaceEdit(
            changes: [uri: [TextEdit(range: LSPRange(startPair: (0, 4), endPair: (0, 5)), newText: text)]],
            documentChanges: nil
        )
    }
}

@MainActor
@Suite("CodeActionsRequest", .uiGate)
struct CodeActionsRequestTests {
    private let problem = Diagnostic(
        range: LSPRange(startPair: (0, 4), endPair: (0, 5)),
        severity: .error,
        code: .optionB("E1"),
        source: "swift",
        message: "unused variable"
    )

    @Test
    func requestCarriesTheRangeTheDiagnosticsAndTheKindFilter() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            try harness.script([])
            let range = LSPRange(startPair: (0, 4), endPair: (0, 9))

            let groups = await harness.request(range: range, diagnostics: [problem])
                .fetch(only: [CodeActionKind.Quickfix, CodeActionKind.SourceOrganizeImports], triggerKind: .automatic)

            #expect(groups.isEmpty)
            let params = try #require(harness.connection.codeActionParams.first)
            #expect(harness.connection.codeActionParams.count == 1)
            #expect(params.textDocument.uri == harness.uri)
            #expect(params.range == range)
            #expect(params.context.diagnostics == [problem])
            #expect(params.context.only == ["quickfix", "source.organizeImports"])
            #expect(params.context.triggerKind == .automatic)
        }
    }

    @Test
    func requestsWithoutAnExplicitServiceUseTheSharedOneAndNeedAServerForTheDocument() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let url = try #require(harness.document.fileURL)
            let diagnostic = WorkspaceDiagnostic(
                fileURL: url, startLine: 0, startColumn: 0, endLine: 0, endColumn: 3,
                severity: .error, message: "x", source: nil, code: nil
            )

            #expect(CodeActionRequest.make(codeFile: harness.document, diagnostics: [diagnostic]) == nil)
            #expect(CodeActionRequest.makeForLine(0, codeFile: harness.document, diagnostics: [diagnostic]) == nil)
        }
    }

    @Test
    func fetchMapsTheResponseIntoGroups() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            try harness.script([
                .optionB(CodeAction(title: "Rename", kind: "refactor.rewrite", edit: harness.replaceFirstLineEdit("x"))),
                .optionB(CodeAction(title: "Prefix", kind: "quickfix", diagnostics: [problem])),
                .optionA(LSPCommand(title: "Legacy", command: "legacy", arguments: nil))
            ])

            let groups = await harness.request(diagnostics: [problem]).fetch()

            #expect(groups.map(\.category) == [.quickFix, .refactoring])
            #expect(groups[0].title == "unused variable")
            #expect(groups[0].actions.map(\.title) == ["Prefix", "Legacy"])
            #expect(groups[1].actions.map(\.title) == ["Rename"])
            let params = try #require(harness.connection.codeActionParams.first)
            #expect(params.context.only == nil)
            #expect(params.context.triggerKind == .invoked)
        }
    }

    @Test
    func serverWithoutCodeActionSupportIsNeverAsked() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(
                in: directory,
                capabilities: CodeActionsHarness.capabilities(resolve: false, supported: false)
            )
            defer { harness.workspace.close() }

            let groups = await harness.request().fetch()

            #expect(groups.isEmpty)
            #expect(!harness.client.supportsCodeActions)
            #expect(harness.connection.codeActionParams.isEmpty)
        }
    }

    @Test
    func capabilitySwitchesFollowTheServerOptions() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }

            #expect(harness.client.supportsCodeActions)
            #expect(harness.client.resolvesCodeActionEdits)
            harness.client.serverCapabilities.codeActionProvider = .optionA(true)
            #expect(harness.client.supportsCodeActions)
            #expect(!harness.client.resolvesCodeActionEdits)
            harness.client.serverCapabilities.codeActionProvider = .optionA(false)
            #expect(!harness.client.supportsCodeActions)
            harness.client.serverCapabilities.codeActionProvider = .optionB(
                CodeActionOptions(workDoneProgress: nil, codeActionKinds: nil, resolveProvider: false)
            )
            #expect(!harness.client.resolvesCodeActionEdits)
            harness.client.serverCapabilities.codeActionProvider = nil
            #expect(!harness.client.supportsCodeActions)
            harness.client.dynamicCapabilities.register(
                [Registration(id: "1", method: "textDocument/codeAction")]
            )
            #expect(harness.client.supportsCodeActions)
        }
    }

    @Test
    func codeActionListsThatCannotBeDecodedYieldNoGroups() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            try harness.connection.script(.textDocumentCodeAction, "not a code action list")

            let groups = await harness.request().fetch()

            #expect(groups.isEmpty)
            #expect(harness.connection.codeActionParams.count == 1)
        }
    }

    @Test
    func actionWithAnEditIsAppliedWithoutResolving() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let action = CodeAction(
                title: "Rename",
                kind: "quickfix",
                edit: harness.replaceFirstLineEdit("alpha"),
                data: .string("token")
            )

            let applied = await harness.request().perform(harness.intention(action))

            #expect(applied)
            #expect(harness.connection.codeActionResolveParams.isEmpty)
            #expect(harness.document.content?.string == "let alpha = 1\nlet b = 2\n")
            #expect(harness.connection.executeCommandParams.isEmpty)
        }
    }

    @Test
    func actionWithoutAnEditIsResolvedFirstWhenTheServerResolves() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let lazy = CodeAction(title: "Rename", kind: "quickfix", data: .string("token"))
            let resolved = CodeAction(
                title: "Rename",
                kind: "quickfix",
                edit: harness.replaceFirstLineEdit("beta"),
                data: .string("token")
            )
            try harness.connection.script(.codeActionResolve, resolved)

            let applied = await harness.request().perform(harness.intention(lazy))

            #expect(applied)
            #expect(harness.connection.codeActionResolveParams == [lazy])
            #expect(harness.document.content?.string == "let beta = 1\nlet b = 2\n")
        }
    }

    @Test
    func actionWithOnlyDataIsResolvedEvenWhenTheServerDoesNotAdvertiseResolve() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(
                in: directory,
                capabilities: CodeActionsHarness.capabilities(resolve: false)
            )
            defer { harness.workspace.close() }
            let lazy = CodeAction(title: "Lazy", kind: "quickfix", data: .number(7))
            try harness.connection.script(
                .codeActionResolve,
                CodeAction(title: "Lazy", kind: "quickfix", edit: harness.replaceFirstLineEdit("gamma"))
            )

            #expect(await harness.request().perform(harness.intention(lazy)))
            #expect(harness.connection.codeActionResolveParams.count == 1)
            #expect(harness.document.content?.string == "let gamma = 1\nlet b = 2\n")
        }
    }

    @Test
    func commandOnlyActionWithoutResolveSupportRunsTheCommandDirectly() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(
                in: directory,
                capabilities: CodeActionsHarness.capabilities(resolve: false)
            )
            defer { harness.workspace.close() }
            let command = LSPCommand(title: "Fix", command: "swift.fix", arguments: [.string("a"), .number(2)])
            let action = CodeAction(title: "Fix", kind: "quickfix", command: command)

            #expect(await harness.request().perform(harness.intention(action)))

            #expect(harness.connection.codeActionResolveParams.isEmpty)
            let params = try #require(harness.connection.executeCommandParams.first)
            #expect(params.command == "swift.fix")
            #expect(params.arguments == [.string("a"), .number(2)])
        }
    }

    @Test
    func bareCommandsAreExecutedThroughWorkspaceExecuteCommand() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let command = LSPCommand(title: "Legacy", command: "legacy.run", arguments: nil)
            let intention = IntentionAction(
                id: "legacy",
                title: "Legacy",
                category: .refactoring,
                isPreferred: false,
                payload: .command(command)
            )

            #expect(await harness.request().perform(intention))

            #expect(harness.connection.executeCommandParams.map(\.command) == ["legacy.run"])
            #expect(harness.connection.executeCommandParams.first?.arguments == nil)
            #expect(harness.connection.codeActionResolveParams.isEmpty)
        }
    }

    @Test
    func editIsAppliedBeforeTheCommandRuns() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let action = CodeAction(
                title: "Both",
                kind: "quickfix",
                edit: harness.replaceFirstLineEdit("both"),
                command: LSPCommand(title: "Both", command: "after.edit", arguments: nil)
            )

            #expect(await harness.request().perform(harness.intention(action)))

            let log = harness.connection.log
            let change = try #require(log.firstIndex(of: "textDocument/didChange"))
            let execute = try #require(log.firstIndex(of: "workspace/executeCommand"))
            #expect(change < execute)
            #expect(harness.document.content?.string == "let both = 1\nlet b = 2\n")
        }
    }

    @Test
    func failuresAreReported() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let empty = CodeAction(title: "Nothing", kind: "quickfix")
            try harness.connection.script(.codeActionResolve, empty)
            let overlapping = WorkspaceEdit(
                changes: [harness.uri: [
                    TextEdit(range: LSPRange(startPair: (0, 0), endPair: (0, 5)), newText: "x"),
                    TextEdit(range: LSPRange(startPair: (0, 3), endPair: (0, 8)), newText: "y")
                ]],
                documentChanges: nil
            )
            let broken = CodeAction(title: "Broken", kind: "quickfix", edit: overlapping)

            #expect(await harness.request().perform(harness.intention(empty)) == false)
            #expect(await harness.request().perform(harness.intention(broken)) == false)
            #expect(harness.document.content?.string == "let a = 1\nlet b = 2\n")
        }
    }

    @Test
    func serverFaultsAreReportedAsFailuresEverywhere() async throws {
        var capabilities = CodeActionsHarness.capabilities(resolve: true)
        capabilities.executeCommandProvider = ExecuteCommandOptions(commands: ["bad"])
        let scripted = ScriptedServerConnection(capabilities: capabilities)
        let connection = FaultInjectingConnection(
            inner: scripted,
            failingRequests: [.textDocumentCodeAction, .codeActionResolve, .workspaceExecuteCommand]
        )
        let client = LanguageServer<CodeFileDocument>(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LanguageServer<CodeFileDocument>.getInitParams(workspacePath: "/")
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: URL(fileURLWithPath: "/"),
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await client.lspInstance.initializeIfNeeded()
        let request = CodeActionRequest(
            client: client,
            documentURI: "file:///x.swift",
            range: LSPRange(startPair: (0, 0), endPair: (0, 0)),
            diagnostics: []
        )
        let command = LSPCommand(title: "Bad", command: "bad", arguments: nil)
        let bare = IntentionAction(
            id: "bad",
            title: "Bad",
            category: .refactoring,
            isPreferred: false,
            payload: .command(command)
        )
        let lazy = CodeAction(title: "Lazy", kind: "quickfix", command: command, data: .number(1))
        let lazyIntention = IntentionAction(
            id: "lazy",
            title: "Lazy",
            category: .quickFix,
            isPreferred: false,
            payload: .codeAction(lazy)
        )

        #expect(await request.fetch().isEmpty)
        #expect(await request.perform(bare) == false)
        #expect(await request.perform(lazyIntention) == false)
        #expect(scripted.codeActionParams.isEmpty)
        #expect(scripted.executeCommandParams.isEmpty)
    }

    @Test
    func workspaceEditsReachFilesThatAreNotOpenOnDisk() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory, extraFiles: ["other.swift": "old\ntext\n"])
            defer { harness.workspace.close() }
            let otherURL = directory.appending(path: "other.swift")
            let edit = WorkspaceEdit(
                changes: [
                    otherURL.lspURI: [TextEdit(range: LSPRange(startPair: (1, 0), endPair: (1, 4)), newText: "line")],
                    harness.uri: [TextEdit(range: LSPRange(startPair: (0, 4), endPair: (0, 5)), newText: "open")]
                ],
                documentChanges: nil
            )

            let result = await harness.service.applyWorkspaceEdit(edit, via: harness.client)

            #expect(result.applied)
            #expect(try String(contentsOf: otherURL, encoding: .utf8) == "old\nline\n")
            #expect(harness.document.content?.string == "let open = 1\nlet b = 2\n")
        }
    }

    @Test
    func serverRequestsApplyEditsThroughTheSameApplier() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let key = harness.workspace.key(.swift)
            let edit = harness.replaceFirstLineEdit("server")

            let result = await harness.service.applyWorkspaceEdit(ApplyWorkspaceEditParams(label: nil, edit: edit), for: key)
            let unknown = await harness.service.applyWorkspaceEdit(
                ApplyWorkspaceEditParams(label: nil, edit: edit),
                for: harness.workspace.key(.python)
            )

            #expect(result.applied)
            #expect(unknown.applied == false)
            #expect(harness.document.content?.string == "let server = 1\nlet b = 2\n")
        }
    }
}

@MainActor
@Suite("CodeActionsHostedEditor", .uiGate)
struct CodeActionsHostedEditorTests {
    private func host(_ harness: CodeActionsHarness) -> HostedSourceEditor {
        let url = harness.workspace.directory.appending(path: "main.swift")
        let fixture = HostedSourceEditorFixture(
            document: harness.document,
            editorInstance: EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        )
        return fixture.host(
            coordinators: [
                harness.document.contentCoordinator,
                harness.document.textViewBinder,
                harness.document.languageServerObjects.textCoordinator
            ],
            size: NSSize(width: 900, height: 600)
        )
    }

    @Test
    func editsToAnOpenEditorAreOneUndoStepAndSyncTheServer() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let hosted = host(harness)
            defer { hosted.close() }
            try await eventually { harness.document.attachedTextView != nil }
            let textView = try #require(harness.document.attachedTextView)
            let edit = WorkspaceEdit(
                changes: [harness.uri: [
                    TextEdit(range: LSPRange(startPair: (0, 4), endPair: (0, 5)), newText: "alpha"),
                    TextEdit(range: LSPRange(startPair: (1, 4), endPair: (1, 5)), newText: "beta")
                ]],
                documentChanges: nil
            )

            let result = await harness.service.applyWorkspaceEdit(edit, via: harness.client)

            #expect(result.applied)
            #expect(textView.string == "let alpha = 1\nlet beta = 2\n")
            await harness.document.languageServerObjects.textCoordinator.flushPendingChanges()
            let synced = harness.connection.lspServiceChanges.flatMap(\.contentChanges)
            #expect(synced.count == 2)
            #expect(Set(synced.map(\.text)) == ["alpha", "beta"])

            textView.undoManager?.undo()

            #expect(textView.string == "let a = 1\nlet b = 2\n")
            #expect(harness.document.content?.string == "let a = 1\nlet b = 2\n")
        }
    }

    @Test
    func requestsBuiltFromTheCaretUseTheSelectionAndTheDiagnosticsAtIt() async throws {
        try await withTempDir { directory in
            let harness = try await CodeActionsHarness.make(in: directory)
            defer { harness.workspace.close() }
            let hosted = host(harness)
            defer { hosted.close() }
            try await eventually { harness.document.attachedTextView != nil }
            let textView = try #require(harness.document.attachedTextView)
            let url = try #require(harness.document.fileURL)
            let here = WorkspaceDiagnostic(
                fileURL: url, startLine: 1, startColumn: 4, endLine: 1, endColumn: 5,
                severity: .warning, message: "here", source: "swift", code: "W1"
            )
            let elsewhere = WorkspaceDiagnostic(
                fileURL: url, startLine: 0, startColumn: 0, endLine: 0, endColumn: 3,
                severity: .error, message: "elsewhere", source: nil, code: nil
            )
            let secondLine = try #require(textView.layoutManager.textLineForIndex(1)).range.location
            textView.selectionManager.setSelectedRange(NSRange(location: secondLine + 4, length: 1))

            let request = try #require(
                CodeActionRequest.make(
                    codeFile: harness.document,
                    diagnostics: [here, elsewhere],
                    lspService: harness.service
                )
            )
            let lineRequest = try #require(
                CodeActionRequest.makeForLine(
                    0,
                    codeFile: harness.document,
                    diagnostics: [here, elsewhere],
                    lspService: harness.service
                )
            )

            #expect(request.range == LSPRange(startPair: (1, 4), endPair: (1, 5)))
            #expect(request.documentURI == harness.uri)
            #expect(request.diagnostics.map(\.message) == ["here"])
            #expect(request.diagnostics.first?.code == .optionB("W1"))
            #expect(lineRequest.range == LSPRange(startPair: (0, 0), endPair: (0, 3)))
            #expect(lineRequest.diagnostics.map(\.message) == ["elsewhere"])
            #expect(
                CodeActionRequest.makeForLine(
                    5,
                    codeFile: harness.document,
                    diagnostics: [here],
                    lspService: harness.service
                ) == nil
            )
            #expect(
                CodeActionRequest.make(codeFile: harness.document, diagnostics: [], lspService: nil) == nil
            )
            #expect(
                CodeActionRequest.makeForLine(0, codeFile: harness.document, diagnostics: [elsewhere], lspService: nil)
                    == nil
            )
        }
    }
}
