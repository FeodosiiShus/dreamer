import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct RenameControllerTests {
    private func makeClient(
        root: URL,
        connection: ScriptedServerConnection,
        capabilities: ServerCapabilities
    ) async throws -> LSPService.LanguageServerType {
        let client = LSPService.LanguageServerType(
            languageId: .swift,
            binary: LanguageServerBinary(execPath: "", args: [], env: nil),
            lspInstance: InitializingServer(
                server: connection,
                initializeParamsProvider: LSPService.LanguageServerType.getInitParams(workspacePath: root.path())
            ),
            lspPid: -1,
            serverCapabilities: capabilities,
            rootPath: root,
            logContainer: LanguageServerLogContainer(languageID: "swift")
        )
        _ = try await client.lspInstance.initializeIfNeeded()
        return client
    }

    private func renameCapabilities() -> ServerCapabilities {
        var capabilities = ScriptedServerConnection.incrementalCapabilities()
        capabilities.renameProvider = .optionB(RenameOptions(prepareProvider: true))
        return capabilities
    }

    private func openNotes(in harness: RenameWindowHarness, directory: URL) throws -> (tab: EditorInstance, url: URL) {
        let url = directory.appending(path: "Notes.txt")
        try "hello world\n".write(to: url, atomically: true, encoding: .utf8)
        EditorLocationNavigation.open(fileURL: url, line: 1, column: 3, workspace: harness.workspace)
        let tab = try #require(harness.workspace.editorManager?.activeEditor.selectedTab)
        return (tab, tab.file.url)
    }

    private func renameParams(_ connection: ScriptedServerConnection) -> [RenameParams] {
        connection.requests.compactMap { request in
            if case let .rename(params, _) = request {
                return params
            }
            return nil
        }
    }

    @Test
    func withoutAnActiveEditorNothingHappens() throws {
        try withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }

            #expect(RenameController.present(in: harness.controller) == nil)
            harness.controller.renameSymbol(nil)

            #expect(harness.panels.isEmpty)
        }
    }

    @Test
    func withoutALanguageServerTheMissingServerMessageIsShown() throws {
        try withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            _ = try openNotes(in: harness, directory: directory)

            #expect(RenameController.present(in: harness.controller) == nil)

            #expect(harness.messagePanels.count == 1)
            #expect(harness.renamePanels.isEmpty)
        }
    }

    @Test
    func theFullFlowPromptsPrefilledAndAppliesTheServersEditToTheOpenDocument() async throws {
        let service = LSPService.shared
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let (tab, url) = try openNotes(in: harness, directory: directory)
            let document = try #require(tab.file.fileDocument)
            let connection = ScriptedServerConnection(capabilities: renameCapabilities())
            let client = try await makeClient(
                root: directory,
                connection: connection,
                capabilities: renameCapabilities()
            )
            try await client.openDocument(document)
            let key = LSPService.ClientKey(.swift, directory.path() + "/")
            service.languageClients[key] = client
            defer { service.languageClients[key] = nil }
            try connection.script(
                .textDocumentPrepareRename,
                RangeWithPlaceholder(range: SyncTestServer.range(0, 0, 5), placeholder: "hello")
            )
            try connection.script(
                .textDocumentRename,
                SyncTestServer.decode(
                    WorkspaceEdit.self,
                    #"""
                    {"changes":{"\#(url.lspURI)":[{"range":{"start":{"line":0,"character":0},\#
                    "end":{"line":0,"character":5}},"newText":"greetings"}]}}
                    """#
                )
            )

            let task = try #require(RenameController.present(in: harness.controller))
            try await eventually { harness.renameModel != nil }
            let model = try #require(harness.renameModel)
            #expect(model.name == "hello")
            model.name = "greetings"
            model.confirm()
            await task.value

            #expect(renameParams(connection).map(\.newName) == ["greetings"])
            #expect(renameParams(connection).map(\.textDocument.uri) == [url.lspURI])
            #expect(renameParams(connection).map(\.position) == [Position(line: 0, character: 2)])
            #expect(document.content?.string == "greetings world\n")
            #expect(harness.messagePanels.isEmpty)
        }
    }

    @Test
    func aNullPrepareResponseShowsTheNotRenameableMessageAndNoPrompt() async throws {
        let service = LSPService.shared
        try await withTempDir { directory in
            let harness = try RenameWindowHarness.make(in: directory)
            defer { harness.close() }
            let (tab, _) = try openNotes(in: harness, directory: directory)
            let document = try #require(tab.file.fileDocument)
            let connection = ScriptedServerConnection(capabilities: renameCapabilities())
            let client = try await makeClient(
                root: directory,
                connection: connection,
                capabilities: renameCapabilities()
            )
            try await client.openDocument(document)
            let key = LSPService.ClientKey(.swift, directory.path() + "/")
            service.languageClients[key] = client
            defer { service.languageClients[key] = nil }

            let task = try #require(RenameController.present(in: harness.controller))
            await task.value

            #expect(harness.renamePanels.isEmpty)
            #expect(harness.messagePanels.count == 1)
            #expect(renameParams(connection).isEmpty)
        }
    }
}
