import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct StructureViewModelCoverageTests {
    private static let modelSource = "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"

    private func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try Self.modelSource.write(to: dir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        try "enum Other {\n    static let one = 1\n}\n"
            .write(to: dir.appending(path: "Other.swift"), atomically: true, encoding: .utf8)
        return try HostedViewFixture.makeWorkspace(in: dir)
    }

    private func file(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws -> CEWorkspaceFile {
        try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
    }

    private func open(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws -> CodeFileDocument {
        let target = try file(name, in: workspace, dir: dir)
        workspace.editorManager?.openTab(item: target)
        return try #require(target.fileDocument)
    }

    private func range(_ line: Int, _ character: Int) -> LSPRange {
        LSPRange(
            start: Position(line: line, character: character),
            end: Position(line: line, character: character + 1)
        )
    }

    private func documentSymbols(_ names: [String]) throws -> Data {
        let symbols = names.map {
            DocumentSymbol(
                name: $0,
                detail: "remote",
                kind: .class,
                range: range(0, 0),
                selectionRange: range(0, 6),
                children: nil
            )
        }
        return try StructureFakeServerConnection.encode(.some(.optionA(symbols)))
    }

    @Test
    func languageServerDocumentSymbolsReplaceTheFallbackTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let harness = try await StructureLSPHarness.make(root: dir, reply: documentSymbols(["Remote", "Second"]))
            harness.attach(document)
            let model = StructureViewModel()

            model.start(workspace: workspace, lspService: harness.service)
            try await eventually { model.nodes.map(\.name) == ["Remote", "Second"] }

            #expect(model.usesLanguageServer)
            #expect(model.isLoading == false)
            #expect(model.fileURL?.lastPathComponent == "Model.swift")
            #expect(model.nodes.map(\.detail) == ["remote", "remote"])
        }
    }

    @Test
    func languageServerSymbolInformationBuildsAFlatTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let information = SymbolInformation(
                name: "flat",
                kind: .function,
                location: Location(uri: "file:///Model.swift", range: range(2, 4)),
                containerName: "Box"
            )
            let reply = try StructureFakeServerConnection.encode(.some(.optionB([information])))
            let harness = try await StructureLSPHarness.make(root: dir, reply: reply)
            harness.attach(document)
            let model = StructureViewModel()

            model.start(workspace: workspace, lspService: harness.service)
            try await eventually { model.nodes.map(\.name) == ["flat"] }

            #expect(model.nodes.first?.detail == "Box")
            #expect(model.nodes.first?.line == 3)
        }
    }

    @Test
    func nullAndFailingServerRepliesFallBackToTheBuiltInExtractor() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)

            let nullHarness = try await StructureLSPHarness.make(
                root: dir,
                reply: StructureFakeServerConnection.encode(nil)
            )
            nullHarness.attach(document)
            let nullModel = StructureViewModel()
            nullModel.start(workspace: workspace, lspService: nullHarness.service)
            try await eventually { nullModel.nodes.map(\.name) == ["Outer", "topLevel"] }
            #expect(nullModel.usesLanguageServer)
            #expect(nullModel.isLoading == false)

            let failingHarness = try await StructureLSPHarness.make(root: dir, reply: nil)
            failingHarness.attach(document)
            let failingModel = StructureViewModel()
            failingModel.start(workspace: workspace, lspService: failingHarness.service)
            try await eventually { failingModel.nodes.map(\.name) == ["Outer", "topLevel"] }
            #expect(failingModel.usesLanguageServer)
            #expect(failingModel.isLoading == false)
        }
    }

    @Test
    func loadingStateLastsUntilTheServerAnswers() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let harness = try await StructureLSPHarness.make(
                root: dir,
                reply: documentSymbols(["Late"]),
                isGated: true
            )
            harness.attach(document)
            let model = StructureViewModel()

            model.start(workspace: workspace, lspService: harness.service)
            try await eventually { model.isLoading }
            #expect(model.nodes.isEmpty)
            #expect(model.usesLanguageServer)

            harness.connection.release()
            try await eventually { model.nodes.map(\.name) == ["Late"] }
            #expect(model.isLoading == false)
        }
    }

    @Test
    func aStaleServerAnswerNeverReplacesTheTreeOfAnotherFile() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let harness = try await StructureLSPHarness.make(
                root: dir,
                reply: documentSymbols(["Stale"]),
                isGated: true
            )
            harness.attach(document)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: harness.service)
            try await eventually { model.isLoading }

            _ = try open("Other.swift", in: workspace, dir: dir)
            harness.connection.release()
            try await eventually { model.nodes.first?.name == "Other" }
            try await Task.sleep(for: .milliseconds(300))

            #expect(model.nodes.map(\.name) == ["Other"])
            #expect(model.usesLanguageServer == false)
            #expect(model.fileURL?.lastPathComponent == "Other.swift")
        }
    }

    @Test
    func aFileWithoutALoadedDocumentShowsNothingUntilTheDocumentArrives() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let target = try file("Model.swift", in: workspace, dir: dir)
            workspace.editorManager?.openTab(item: target)
            let document = try #require(target.fileDocument)
            target.fileDocument = nil
            let model = StructureViewModel()

            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.fileURL != nil }
            #expect(model.nodes.isEmpty)
            #expect(model.isLoading == false)
            #expect(model.usesLanguageServer == false)

            target.fileDocument = nil
            target.fileDocument = document
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }
        }
    }

    @Test
    func theFallbackReadsTheFileFromDiskWhenTheDocumentHasNoContent() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }

            document.content = nil
            try "func fromDisk() {}\n".write(
                to: dir.appending(path: "Model.swift"),
                atomically: true,
                encoding: .utf8
            )
            model.scheduleRefresh(delay: .milliseconds(1))
            try await eventually { model.nodes.map(\.name) == ["fromDisk"] }

            try FileManager.default.removeItem(at: dir.appending(path: "Model.swift"))
            model.scheduleRefresh(delay: .milliseconds(1))
            try await eventually { model.nodes.isEmpty }
        }
    }

    @Test
    func textChangesInTheDocumentRefreshTheTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let target = try file("Model.swift", in: workspace, dir: dir)
            workspace.editorManager?.openTab(item: target)
            let document = try #require(target.fileDocument)
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }

            let fixture = HostedSourceEditorFixture(document: document, editorInstance: tab)
            let hosted = fixture.host(coordinators: [document.contentCoordinator], size: NSSize(width: 900, height: 600))
            defer { hosted.close() }
            try await eventually { hosted.controller?.textView != nil }
            let controller = try #require(hosted.controller)

            document.content = NSTextStorage(string: "func swapped() {}\n")
            document.contentCoordinator.textViewDidChangeText(controller: controller)
            try await eventually { model.nodes.map(\.name) == ["swapped"] }
        }
    }

    @Test
    func aClosedWorkspaceNeverStartsObserving() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            workspace.close()
            let model = StructureViewModel()

            model.start(workspace: workspace, lspService: LSPService())
            model.scheduleRefresh(delay: .milliseconds(1))
            try await Task.sleep(for: .milliseconds(100))

            #expect(model.nodes.isEmpty)
            #expect(model.fileURL == nil)
        }
    }

    @Test
    func selectingARowOnlySelectsAndActivatingNavigatesTheEditor() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            _ = try open("Model.swift", in: workspace, dir: dir)
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }
            #expect(model.selection == "fallback/0")
            #expect(model.focusRequests == 0)
            #expect(model.rows.map(\.node.name) == ["Outer", "value", "run", "topLevel"])

            let run = try #require(model.nodes.first?.children.last)
            #expect(run.id == "fallback/2")
            model.select(run, workspace: workspace)
            #expect(model.selection == "fallback/2")
            #expect(model.focusRequests == 1)
            let editor = try #require(workspace.editorManager).activeEditor
            let tab = try #require(editor.selectedTab)
            #expect(tab.cursorPositions.first?.start.line == 1)

            model.activate(run, workspace: workspace)
            #expect(model.focusRequests == 2)
            #expect(tab.cursorPositions.first?.start.line == 3)
            #expect(tab.cursorPositions.first?.start.column == 1)

            tab.cursorPositions = [CursorPosition(line: 1, column: 1)]
            #expect(model.activateSelection(workspace: workspace) == .handled)
            #expect(tab.cursorPositions.first?.start.line == 3)

            model.toggleCollapsed("fallback/0")
            #expect(model.collapsed == ["fallback/0"])
            #expect(model.rows.map(\.node.name) == ["Outer", "topLevel"])
            model.toggleCollapsed("fallback/0")
            #expect(model.collapsed.isEmpty)
        }
    }

    @Test
    func returnIgnoresSelectionsThatNoLongerExist() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            _ = try open("Model.swift", in: workspace, dir: dir)
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())
            #expect(model.activateSelection(workspace: workspace) == .handled)
            model.toggleAutoscrollFromSource()

            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }
            let top = try #require(model.nodes.last)
            model.select(top, workspace: workspace)
            #expect(model.selection == "fallback/3")

            _ = try open("Other.swift", in: workspace, dir: dir)
            try await eventually { model.nodes.first?.name == "Other" }
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            tab.cursorPositions = [CursorPosition(line: 2, column: 2)]

            #expect(model.activateSelection(workspace: workspace) == .handled)
            #expect(tab.cursorPositions.first?.start.line == 2)
            #expect(tab.cursorPositions.first?.start.column == 2)
        }
    }

    @Test
    func selectingWithoutAFileDoesNotOpenAnything() async throws {
        try withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = StructureViewModel()
            let node = StructureNode(
                id: "x",
                name: "x",
                detail: nil,
                kind: .function,
                line: 4,
                column: 2,
                children: []
            )

            model.select(node, workspace: workspace)

            #expect(model.selection == "x")
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)
            #expect(model.activateSelection(workspace: workspace) == .handled)
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)
        }
    }
}
