import AppKit
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct IntentionPopupControllerTests {
    private static let source = "let x = 1\n"

    @MainActor
    private struct Session {
        let workspace: LSPServiceWorkspace
        let service: LSPService
        let document: CodeFileDocument
        let hosted: HostedSourceEditor
        let textView: TextView
        let controller: DreamderWindowController
        let connection: ScriptedServerConnection

        var window: NSWindow? { controller.window }

        var request: IntentionPopupController.RequestFactory {
            { [service] codeFile, diagnostics in
                CodeActionRequest.make(codeFile: codeFile, diagnostics: diagnostics, lspService: service)
            }
        }

        func panel() -> IntentionPopupPanel? {
            window?.childWindows?.compactMap { $0 as? IntentionPopupPanel }.first
        }

        func model() -> IntentionPopupModel? {
            (panel()?.contentView as? NSHostingView<IntentionPopupView>)?.rootView.model
        }

        func close() {
            for child in window?.childWindows ?? [] {
                child.close()
            }
            hosted.close()
            window?.close()
            workspace.close()
        }
    }

    private func openSession(in directory: URL, response: CodeActionResponse?) async throws -> Session {
        let fixture = LSPServiceFixture()
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.codeActionProvider = .optionA(true)
        fixture.capabilities = capabilities
        let service = fixture.makeService()
        let workspace = try LSPServiceWorkspace(directory: directory, files: ["main.swift": Self.source])
        let document = try workspace.document("main.swift")
        let editorInstance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: directory.appending(path: "main.swift")))
        let hosted = HostedSourceEditorFixture(document: document, editorInstance: editorInstance).host(
            coordinators: [document.contentCoordinator, document.textViewBinder],
            size: NSSize(width: 900, height: 600)
        )
        try await eventually { hosted.controller?.textView?.window === hosted.window }
        let textView = try #require(hosted.controller?.textView)
        service.openDocument(document)
        await service.waitForDocumentOperations()
        let connection = try #require(fixture.created.first?.connection)
        if let response {
            try connection.script(.textDocumentCodeAction, response)
        }
        workspace.workspace.makeWindowControllers()
        let controller = try #require(workspace.workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        controller.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return Session(
            workspace: workspace,
            service: service,
            document: document,
            hosted: hosted,
            textView: textView,
            controller: controller,
            connection: connection
        )
    }

    private func replaceXEdit(title: String, preferred: Bool, uri: String) -> TwoTypeOption<LSPCommand, CodeAction> {
        let edit = TextEdit(
            range: LSPRange(start: Position(line: 0, character: 4), end: Position(line: 0, character: 5)),
            newText: "y"
        )
        return .optionB(CodeAction(
            title: title,
            kind: CodeActionKind.Refactor,
            isPreferred: preferred,
            edit: WorkspaceEdit(changes: [uri: [edit]], documentChanges: nil)
        ))
    }

    private func key(_ code: UInt16) throws -> NSEvent {
        try IntentionPopupFixtures.keyEvent(code)
    }

    @Test
    func fetchedGroupsFillThePopupAndApplyingTheSelectedActionEditsTheDocument() async throws {
        try await withTempDir { directory in
            let uri = directory.appending(path: "main.swift").lspURI
            let session = try await openSession(
                in: directory,
                response: [
                    replaceXEdit(title: "Other fix", preferred: false, uri: uri),
                    replaceXEdit(title: "Rename x to y", preferred: true, uri: uri)
                ]
            )
            defer { session.close() }
            var failures = 0

            await IntentionPopupController.present(
                in: session.controller,
                codeFile: session.document,
                makeRequest: session.request,
                failureHandler: { failures += 1 }
            )

            let model = try #require(session.model())
            #expect(model.rows.compactMap(\.intention).map(\.title) == ["Rename x to y", "Other fix"])
            #expect(model.selectedAction?.title == "Rename x to y")
            #expect(session.connection.requestCount(.textDocumentCodeAction) == 1)

            let panel = try #require(session.panel())
            panel.sendEvent(try key(36))

            try await eventually { session.textView.string == "let y = 1\n" }
            #expect(session.document.content?.string == "let y = 1\n")
            #expect(session.panel() == nil)
            #expect(failures == 0)
        }
    }

    @Test
    func actionsThatCannotBePerformedReportTheFailure() async throws {
        try await withTempDir { directory in
            let useless = TwoTypeOption<LSPCommand, CodeAction>.optionB(CodeAction(title: "Does nothing", kind: CodeActionKind.Refactor))
            let session = try await openSession(in: directory, response: [useless])
            defer { session.close() }
            var failures = 0

            await IntentionPopupController.present(
                in: session.controller,
                codeFile: session.document,
                makeRequest: session.request,
                failureHandler: { failures += 1 }
            )
            let panel = try #require(session.panel())
            panel.sendEvent(try key(36))

            try await eventually { failures == 1 }
            #expect(session.textView.string == Self.source)
        }
    }

    @Test
    func performReportsFailureOnlyWhenTheRequestFails() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, response: nil)
            defer { session.close() }
            let request = try #require(session.request(session.document, []))
            let working = IntentionAction(
                id: "ok",
                title: "Run",
                category: .refactoring,
                isPreferred: false,
                payload: .command(Command(title: "Run", command: "noop"))
            )
            var failures = 0

            await IntentionPopupController.perform(working, request: request) { failures += 1 }
            #expect(failures == 0)
            #expect(session.connection.requestCount(.workspaceExecuteCommand) == 1)

            let unresolved = IntentionAction(
                id: "none",
                title: "Nothing",
                category: .refactoring,
                isPreferred: false,
                payload: .codeAction(CodeAction(title: "Nothing"))
            )
            await IntentionPopupController.perform(unresolved, request: request) { failures += 1 }
            #expect(failures == 1)
            #expect(session.textView.string == Self.source)
        }
    }

    @Test
    func emptyResponsesShowTheNoActionsMessage() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, response: nil)
            defer { session.close() }

            await IntentionPopupController.present(
                in: session.controller,
                codeFile: session.document,
                makeRequest: session.request,
                failureHandler: {}
            )

            let model = try #require(session.model())
            #expect(model.message == IntentionPopupController.noActionsMessage)
        }
    }

    @Test
    func missingRequestsShowTheLanguageServerMessage() async throws {
        try await withTempDir { directory in
            let session = try await openSession(in: directory, response: nil)
            defer { session.close() }

            await IntentionPopupController.present(
                in: session.controller,
                codeFile: session.document,
                makeRequest: { _, _ in nil },
                failureHandler: {}
            )

            let model = try #require(session.model())
            #expect(model.message == IntentionPopupController.missingServerMessage)
        }
    }

    @Test
    func defaultRequestFactoryNeedsAnAttachedServerDocument() async throws {
        try withTempDir { directory in
            let workspace = try LSPServiceWorkspace(directory: directory, files: ["plain.txt": "text\n"])
            defer { workspace.close() }
            let document = try workspace.document("plain.txt")

            #expect(IntentionPopupController.defaultRequest(codeFile: document, diagnostics: []) == nil)
            IntentionPopupController.reportFailure()
        }
    }

    @Test
    func showContextActionsIgnoresWindowsWithoutAnActiveDocumentAndPresentsForOpenTabs() async throws {
        try await withTempDir { directory in
            try "let one = 1\n".write(to: directory.appending(path: "One.swift"), atomically: true, encoding: .utf8)
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            DreamderDocumentController.shared.addDocument(workspace)
            workspace.makeWindowControllers()
            let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
            let window = try #require(controller.window)
            window.isReleasedWhenClosed = false
            defer {
                for child in window.childWindows ?? [] {
                    child.close()
                }
                window.close()
                workspace.close()
            }
            @MainActor func panel() -> IntentionPopupPanel? {
                window.childWindows?.compactMap { $0 as? IntentionPopupPanel }.first
            }

            controller.showContextActions(nil)
            #expect(panel() == nil)

            let manager = try #require(workspace.editorManager)
            let file = try #require(workspace.workspaceFileManager?.getFile(
                directory.appending(path: "One.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            manager.openTab(item: file)
            controller.showContextActions(nil)

            try await eventually(timeout: .seconds(10)) { panel() != nil }
            let model = try #require(
                (panel()?.contentView as? NSHostingView<IntentionPopupView>)?.rootView.model
            )
            #expect(model.message == IntentionPopupController.missingServerMessage)
        }
    }
}
