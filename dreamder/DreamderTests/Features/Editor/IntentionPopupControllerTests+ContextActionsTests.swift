import AppKit
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
extension IntentionPopupControllerTests {
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
            @MainActor
            func panel() -> IntentionPopupPanel? {
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

    @Test
    func showContextActionsBeepsWhenTheChosenActionFails() async throws {
        try await withTempDir { directory in
            let useless = TwoTypeOption<LSPCommand, CodeAction>.optionB(
                CodeAction(title: "Does nothing", kind: CodeActionKind.Refactor)
            )
            let session = try await openSession(in: directory, response: [useless])
            defer { session.close() }
            let client = try #require(session.service.languageClients.values.first)
            let clientKey = LSPService.ClientKey(.swift, session.workspace.path)
            LSPService.shared.languageClients[clientKey] = client
            defer { LSPService.shared.languageClients[clientKey] = nil }
            let workspaceDocument = session.workspace.workspace
            let manager = try #require(workspaceDocument.editorManager)
            let file = try #require(session.workspace.fileManager.getFile(
                directory.appending(path: "main.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            file.fileDocument = session.document
            manager.openTab(item: file)

            session.controller.showContextActions(nil)

            try await eventually(timeout: .seconds(10)) { session.panel() != nil }
            #expect(session.connection.requestCount(.textDocumentCodeAction) == 1)
            let panel = try #require(session.panel())
            panel.sendEvent(try key(36))

            try await eventually(timeout: .seconds(10)) { session.panel() == nil }
            #expect(session.textView.string == Self.source)
        }
    }
}
