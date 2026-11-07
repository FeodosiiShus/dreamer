import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct StructureViewModelTests {
    private func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"
            .write(to: dir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        try "enum Other {\n    static let one = 1\n}\n"
            .write(to: dir.appending(path: "Other.swift"), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: dir, ofType: "")
        return workspace
    }

    private func open(_ name: String, in workspace: WorkspaceDocument, dir: URL) throws {
        let file = try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: name).path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
    }

    @Test
    func emptyEditorHasNoStructure() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            try await Task.sleep(for: .milliseconds(250))

            #expect(model.nodes.isEmpty)
            #expect(model.fileURL == nil)
            #expect(model.usesLanguageServer == false)
        }
    }

    @Test
    func withoutLanguageServerFallsBackToTheBuiltInExtractor() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            try open("Model.swift", in: workspace, dir: dir)
            try await eventually { !model.nodes.isEmpty }

            #expect(model.fileURL?.lastPathComponent == "Model.swift")
            #expect(model.usesLanguageServer == false)
            #expect(model.isLoading == false)
            #expect(model.nodes.map(\.name) == ["Outer", "topLevel"])
            #expect(model.nodes.first?.children.map(\.name) == ["value", "run"])
        }
    }

    @Test
    func switchingTabsRebuildsTheTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            try open("Model.swift", in: workspace, dir: dir)
            try await eventually { model.nodes.first?.name == "Outer" }

            try open("Other.swift", in: workspace, dir: dir)
            try await eventually { model.nodes.first?.name == "Other" }

            #expect(model.fileURL?.lastPathComponent == "Other.swift")
            #expect(model.nodes.first?.children.map(\.name) == ["one"])
        }
    }

    @Test
    func selectingAnotherOpenTabRebuildsTheTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            try open("Model.swift", in: workspace, dir: dir)
            try open("Other.swift", in: workspace, dir: dir)
            try await eventually { model.nodes.first?.name == "Other" }

            let first = try #require(workspace.workspaceFileManager?.getFile(
                dir.appending(path: "Model.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            workspace.editorManager?.activeEditor.setSelectedTab(first)
            try await eventually { model.nodes.first?.name == "Outer" }

            #expect(model.fileURL?.lastPathComponent == "Model.swift")
        }
    }

    @Test
    func clearingTheSelectedTabClearsTheTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            try open("Model.swift", in: workspace, dir: dir)
            try await eventually { !model.nodes.isEmpty }

            workspace.editorManager?.activeEditor.setSelectedTab(nil)
            try await eventually { model.nodes.isEmpty }

            #expect(model.fileURL == nil)
        }
    }

    @Test
    func startingTwiceKeepsTheFirstWorkspace() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            let model = StructureViewModel()
            model.start(workspace: workspace, lspService: LSPService())
            model.start(workspace: WorkspaceDocument(), lspService: LSPService())
            try open("Other.swift", in: workspace, dir: dir)
            try await eventually { model.nodes.first?.name == "Other" }
        }
    }
}
