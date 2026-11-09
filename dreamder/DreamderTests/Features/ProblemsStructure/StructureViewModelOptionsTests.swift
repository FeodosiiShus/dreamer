import AppKit
import CodeEditSourceEditor
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct StructureViewModelOptionsTests {
    private func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"
            .write(to: dir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        try "// header\nfunc lead() {}\n".write(to: dir.appending(path: "Lead.swift"), atomically: true, encoding: .utf8)
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

    private func loadedModel(
        _ workspace: WorkspaceDocument,
        dir: URL,
        file: String = "Model.swift"
    ) async throws -> StructureViewModel {
        try open(file, in: workspace, dir: dir)
        let model = StructureViewModel(defaults: try IsolatedDefaults.require())
        model.start(workspace: workspace, lspService: LSPService())
        try await eventually { !model.nodes.isEmpty }
        return model
    }

    private func activeTab(_ workspace: WorkspaceDocument) throws -> EditorInstance {
        try #require(workspace.editorManager?.activeEditor.selectedTab)
    }

    @Test
    func togglesFlipTheOptionsAndPersistThemForTheNextModel() throws {
        let defaults = try IsolatedDefaults.require()
        let model = StructureViewModel(defaults: defaults)
        #expect(model.options == StructureViewOptions())

        model.toggleSortsAlphabetically()
        model.toggleGroupsByKind()
        model.toggleAutoscrollFromSource()
        model.toggleAutoscrollToSource()

        #expect(model.options.sortsAlphabetically)
        #expect(model.options.groupsByKind)
        #expect(model.options.autoscrollsFromSource == false)
        #expect(model.options.autoscrollsToSource)
        #expect(StructureViewModel(defaults: defaults).options == model.options)
    }

    @Test
    func sortingReordersSiblingsAndSourceOrderReturnsWhenOff() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            #expect(model.rows.map(\.node.name) == ["Outer", "value", "run", "topLevel"])

            model.toggleSortsAlphabetically()
            #expect(model.rows.map(\.node.name) == ["Outer", "run", "value", "topLevel"])

            model.toggleSortsAlphabetically()
            #expect(model.rows.map(\.node.name) == ["Outer", "value", "run", "topLevel"])
        }
    }

    @Test
    func filterShowsMatchesWithAncestorsExpandedEvenWhenCollapsed() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            model.toggleCollapsed("fallback/0")
            #expect(model.rows.map(\.node.name) == ["Outer", "topLevel"])
            #expect(model.isFiltering == false)

            model.filterText = "run"
            #expect(model.isFiltering)
            #expect(model.rows.map(\.node.name) == ["Outer", "run"])

            model.filterText = "zzzz"
            #expect(model.rows.isEmpty)

            model.filterText = ""
            #expect(model.rows.map(\.node.name) == ["Outer", "topLevel"])
        }
    }

    @Test
    func groupingAddsKindGroupsWithCountsAboveTheHierarchy() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)

            model.toggleGroupsByKind()

            #expect(model.rows.map(\.node.name) == ["Classes", "Outer", "value", "run", "Functions", "topLevel"])
            #expect(model.rows.map(\.depth) == [0, 1, 2, 2, 0, 1])
            let classes = try #require(model.rows.first?.node)
            #expect(classes.isGroup)
            #expect(classes.detail == "1")

            model.activate(classes, workspace: workspace)
            #expect(model.selection == "group/Classes")
            #expect(model.collapsed == ["group/Classes"])
            #expect(model.rows.map(\.node.name) == ["Classes", "Functions", "topLevel"])
            let tab = try activeTab(workspace)
            #expect(tab.cursorPositions.first?.start.line == 1)

            model.activate(classes, workspace: workspace)
            #expect(model.collapsed.isEmpty)
        }
    }

    @Test
    func autoscrollFromSourceSelectsTheInnermostSymbolAndExpandsItsAncestors() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            #expect(model.selection == "fallback/0")
            let scrollsBefore = model.scrollRequests
            model.toggleCollapsed("fallback/0")
            let tab = try activeTab(workspace)

            tab.cursorPositions = [CursorPosition(line: 3, column: 1)]

            try await eventually { model.selection == "fallback/2" }
            #expect(model.collapsed.isEmpty)
            #expect(model.scrollTarget == "fallback/2")
            #expect(model.scrollRequests > scrollsBefore)
            #expect(model.rows.map(\.node.name) == ["Outer", "value", "run", "topLevel"])
        }
    }

    @Test
    func autoscrollFromSourceExpandsTheKindGroupAndReadsOffsetsWithoutLines() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            model.toggleGroupsByKind()
            model.toggleCollapsed("group/Classes")
            model.toggleCollapsed("fallback/0")
            let tab = try activeTab(workspace)

            tab.cursorPositions = [CursorPosition(range: NSRange(location: 20, length: 0))]

            try await eventually { model.selection == "fallback/1" }
            #expect(model.collapsed.isEmpty)
            #expect(model.rows.map(\.node.name) == ["Classes", "Outer", "value", "run", "Functions", "topLevel"])
        }
    }

    @Test
    func autoscrollFromSourceIgnoresLinesOutsideSymbolsAndKeepsASelectionOnTheCaretLine() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir, file: "Lead.swift")
            #expect(model.selection == nil)
            let scrolls = model.scrollRequests
            let tab = try activeTab(workspace)

            tab.cursorPositions = [CursorPosition(line: 2, column: 3)]
            try await eventually { model.selection == "fallback/0" }
            let scrollsAfterSelect = model.scrollRequests
            #expect(scrollsAfterSelect == scrolls + 1)

            tab.cursorPositions = [CursorPosition(line: 2, column: 9)]
            try await Task.sleep(for: .milliseconds(150))
            #expect(model.scrollRequests == scrollsAfterSelect)
        }
    }

    @Test
    func disablingAutoscrollFromSourceFreezesTheSelectionAndReenablingResyncs() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            model.toggleAutoscrollFromSource()
            #expect(model.options.autoscrollsFromSource == false)
            let tab = try activeTab(workspace)

            tab.cursorPositions = [CursorPosition(line: 6, column: 1)]
            try await Task.sleep(for: .milliseconds(150))
            #expect(model.selection == "fallback/0")

            model.toggleAutoscrollFromSource()
            #expect(model.selection == "fallback/3")
        }
    }

    @Test
    func autoscrollToSourceMovesTheCaretOnSelectionWithoutLeavingTheTree() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            let tab = try activeTab(workspace)
            let run = try #require(model.nodes.first?.children.last)

            model.select(run, workspace: workspace)
            #expect(tab.cursorPositions.first?.start.line == 1)

            model.toggleAutoscrollToSource()
            model.select(run, workspace: workspace)
            #expect(tab.cursorPositions.first?.start.line == 3)

            let top = try #require(model.nodes.last)
            model.activate(top, workspace: workspace)
            #expect(tab.cursorPositions.first?.start.line == 6)
        }
    }

    @Test
    func keyboardSelectionMovesThroughVisibleRowsAndClamps() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = StructureViewModel(defaults: try IsolatedDefaults.require())
            model.moveSelection(by: 1, workspace: workspace)
            #expect(model.selection == nil)

            try open("Model.swift", in: workspace, dir: dir)
            model.toggleAutoscrollFromSource()
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { !model.nodes.isEmpty }
            #expect(model.selection == nil)

            model.moveSelection(by: -1, workspace: workspace)
            #expect(model.selection == "fallback/3")
            model.moveSelection(by: 1, workspace: workspace)
            #expect(model.selection == "fallback/3")
            model.moveSelection(by: -1, workspace: workspace)
            #expect(model.selection == "fallback/2")
            #expect(model.scrollTarget == "fallback/2")

            model.select(try #require(model.nodes.first), workspace: workspace)
            model.moveSelection(by: -1, workspace: workspace)
            #expect(model.selection == "fallback/0")
            model.moveSelection(by: 1, workspace: workspace)
            #expect(model.selection == "fallback/1")
        }
    }

    @Test
    func returnWithAFilterOpensTheFirstMatchWhenNothingVisibleIsSelected() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            let tab = try activeTab(workspace)

            model.filterText = "top"
            #expect(model.selection == "fallback/0")
            #expect(model.activateSelection(workspace: workspace) == .handled)

            #expect(model.selection == "fallback/3")
            #expect(tab.cursorPositions.first?.start.line == 6)
        }
    }

    @Test
    func returnWithAGroupFilterSkipsGroupRows() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            model.toggleGroupsByKind()
            model.filterText = "top"
            #expect(model.rows.map(\.node.name) == ["Functions", "topLevel"])

            _ = model.activateSelection(workspace: workspace)

            #expect(model.selection == "fallback/3")
        }
    }
}
