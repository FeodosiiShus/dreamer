import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct StructureViewModelCoverageTests {
    static let modelSource = "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"

    func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try Self.modelSource.write(to: dir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        try "enum Other {\n    static let one = 1\n}\n"
            .write(to: dir.appending(path: "Other.swift"), atomically: true, encoding: .utf8)
        return try HostedViewFixture.makeWorkspace(in: dir)
    }

    func file(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws -> CEWorkspaceFile {
        try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
    }

    func open(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws -> CodeFileDocument {
        let target = try file(name, in: workspace, dir: dir)
        workspace.editorManager?.openTab(item: target)
        return try #require(target.fileDocument)
    }

    func range(_ line: Int, _ character: Int) -> LSPRange {
        LSPRange(
            start: Position(line: line, character: character),
            end: Position(line: line, character: character + 1)
        )
    }

    func documentSymbols(_ names: [String]) throws -> Data {
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
    func theDefaultReaderReadsTheFileFromDiskAndYieldsNothingWhenItIsGone() async throws {
        try await withTempDir { dir in
            let url = dir.appending(path: "Model.swift")
            try "func fromDisk() {}\n".write(to: url, atomically: true, encoding: .utf8)
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())

            #expect(await model.readText(url) == "func fromDisk() {}\n")

            try FileManager.default.removeItem(at: url)
            #expect(await model.readText(url) == nil)
        }
    }

    @Test
    func theFallbackReadsTheFileFromDiskWhenTheDocumentHasNoContent() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())
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
        }
    }

    @Test
    func aFileThatCannotBeReadShowsAnEmptyTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let model = StructureViewModel(defaults: try IsolatedDefaults.require(), readText: { _ in nil })
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }

            document.content = nil
            model.scheduleRefresh(delay: .milliseconds(1))
            try await eventually { model.nodes.isEmpty }
            #expect(model.fileURL?.lastPathComponent == "Model.swift")
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
}
