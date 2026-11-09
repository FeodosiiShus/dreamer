import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct ShowUsagesFlowCoverageTests {
    @Test
    func resolverBuildsTheContextFromTheSelectedTabAndTheOwningServer() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }

            let context = try harness.readyContext(line: 1, column: 11)

            #expect(context.fileURL.lastPathComponent == "main.py")
            #expect(context.documentURI == context.fileURL.lspURI)
            #expect(context.position == Position(line: 0, character: 10))
            #expect(context.documentText == UsagesFlowHarness.mainText)
            #expect(context.lineText == "value = helper()")
            #expect(context.symbol == "helper")
            #expect(context.client === harness.service.languageClient(forDocument: harness.url("main.py")))
        }
    }

    @Test
    func resolverClampsTheCaretAndYieldsAnEmptySymbolOnBlankLines() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }

            let blank = try harness.readyContext(line: 2, column: 1)
            let beyondEnd = try harness.readyContext(line: 99, column: 1)

            #expect(blank.lineText.isEmpty)
            #expect(blank.symbol.isEmpty)
            #expect(beyondEnd.position == Position(line: 98, character: 0))
            #expect(beyondEnd.lineText.isEmpty)
        }
    }

    @Test
    func resolverReportsMissingServerWhenNoServiceOwnsTheFile() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("notes.txt")
            let idleService = LSPServiceFixture().makeService()

            let withoutService = LSPEditorContextResolver.resolve(workspace: harness.workspace, lspService: nil)
            let withIdleService = LSPEditorContextResolver.resolve(workspace: harness.workspace, lspService: idleService)
            let notesWithServer = LSPEditorContextResolver.resolve(workspace: harness.workspace, lspService: harness.service)

            guard case .missingServer = withoutService, case .missingServer = withIdleService,
                  case .missingServer = notesWithServer else {
                Issue.record("expected a missing server for every service without the file")
                return
            }
        }
    }

    @Test
    func resolverIsUnavailableWithoutAWorkspaceOrSelectedTab() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let emptyDirectory = directory.appending(path: "empty", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
            let emptyWorkspace = try LSPServiceWorkspace(directory: emptyDirectory, files: [:])
            defer { emptyWorkspace.close() }
            #expect(emptyWorkspace.workspace.editorManager?.activeEditor.selectedTab == nil)

            let withoutWorkspace = LSPEditorContextResolver.resolve(workspace: nil, lspService: harness.service)
            let withoutTab = LSPEditorContextResolver.resolve(
                workspace: emptyWorkspace.workspace,
                lspService: harness.service
            )

            guard case .unavailable = withoutWorkspace, case .unavailable = withoutTab else {
                Issue.record("expected unavailable without a workspace or a selected tab")
                return
            }
        }
    }

    @Test
    func documentTextPrefersTheOpenDocumentAndFallsBackToTheFileOnDisk() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py")
            let tab = try #require(harness.tab("main.py"))
            #expect(LSPEditorContextResolver.documentText(for: tab) == UsagesFlowHarness.mainText)

            tab.file.fileDocument = harness.mainDocument
            harness.files.setText("main.py", "edited = 1\n")
            #expect(LSPEditorContextResolver.documentText(for: tab) == "edited = 1\n")

            let ghost = EditorInstance(
                workspace: nil,
                file: CEWorkspaceFile(url: harness.url("ghost.py"))
            )
            #expect(LSPEditorContextResolver.documentText(for: ghost) == nil)
        }
    }

    @Test
    func loaderWithoutReferencesYieldsNoRows() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            let context = try harness.readyContext(line: 1, column: 11)

            let rows = await LSPUsagesLoader.rows(for: context)

            #expect(rows.isEmpty)
            #expect(harness.connection.requestCount(.textDocumentReferences) == 1)
        }
    }

    @Test
    func loaderReadsTextFromTheContextOpenTabsAndDiskAndSkipsForeignUris() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("other.py")
            harness.open("notes.txt")
            let otherTab = try #require(harness.tab("other.py"))
            let otherDocument = try harness.files.document("other.py")
            harness.files.setText("other.py", "changed()\n")
            otherTab.file.fileDocument = otherDocument
            harness.open("helper.py")
            let context = try harness.readyContext(line: 1, column: 11)
            try harness.connection.script(
                .textDocumentReferences,
                [
                    harness.location("main.py", 0, 8, 14),
                    harness.location("helper.py", 0, 4, 10),
                    harness.location("other.py", 0, 0, 7),
                    harness.location("ghost.py", 0, 0, 3),
                    harness.location("closed.py", 0, 0, 6),
                    Location(
                        uri: "untitled:Scratch",
                        range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1))
                    )
                ]
            )

            let rows = await LSPUsagesLoader.rows(for: context)

            #expect(rows.map(\.fileName) == ["closed.py", "ghost.py", "helper.py", "main.py", "other.py"])
            #expect(rows.map(\.lineText) == ["closed()", "", "def helper():", "value = helper()", "changed()"])
            #expect(rows.map(\.matchRange) == [
                NSRange(location: 0, length: 6),
                nil,
                NSRange(location: 4, length: 6),
                NSRange(location: 8, length: 6),
                NSRange(location: 0, length: 7)
            ])
            #expect(rows.map(\.displayLine) == [1, 1, 1, 1, 1])
            withExtendedLifetime(otherDocument) {}
        }
    }

    @Test
    func presentingUsagesShowsThePopulatedPanel() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py", line: 1, column: 11)
            try harness.connection.script(
                .textDocumentReferences,
                [harness.location("main.py", 0, 8, 14), harness.location("main.py", 2, 8, 13)]
            )

            let task = ShowUsagesController.present(in: harness.controller, lspService: harness.service)
            await task?.value

            let model = try #require(harness.panelModel)
            #expect(task != nil)
            #expect(model.headerTitle == "Usages of helper")
            #expect(model.rows.map(\.lineText) == ["value = helper()", "other = value"])
            #expect(harness.panels.count == 1)
        }
    }

    @Test
    func presentingUsagesWithoutResultsNamesTheSymbolInTheMessage() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py", line: 1, column: 11)

            await ShowUsagesController.present(in: harness.controller, lspService: harness.service)?.value

            let model = try #require(harness.panelModel)
            #expect(model.message == "No usages found for 'helper'")
        }
    }

    @Test
    func presentingUsagesWithoutResultsOnABlankLineUsesTheGenericMessage() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("main.py", line: 2, column: 1)

            await ShowUsagesController.present(in: harness.controller, lspService: harness.service)?.value

            #expect(harness.panelModel?.message == "No usages found")
        }
    }

    @Test
    func presentingUsagesWithoutAServerExplainsWhatIsNeeded() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.open("notes.txt")

            let task = ShowUsagesController.present(in: harness.controller, lspService: nil)

            #expect(task == nil)
            #expect(harness.panelModel?.message == "Show Usages needs a language server for this file")
        }
    }

    @Test
    func presentingUsagesWithoutAnEditorDoesNothing() async throws {
        try await withTempDir { directory in
            let harness = try await UsagesFlowHarness.make(in: directory)
            defer { harness.close() }
            harness.controller.workspace = nil

            let task = ShowUsagesController.present(in: harness.controller, lspService: harness.service)

            #expect(task == nil)
            #expect(harness.panels.isEmpty)
            harness.controller.workspace = harness.workspace
        }
    }
}
