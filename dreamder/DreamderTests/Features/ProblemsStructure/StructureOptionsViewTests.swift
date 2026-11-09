import AppKit
import CodeEditSourceEditor
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct StructureOptionsViewTests {
    private func makeWorkspace(_ dir: URL) throws -> WorkspaceDocument {
        try "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"
            .write(to: dir.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        return try HostedViewFixture.makeWorkspace(in: dir)
    }

    private func loadedModel(_ workspace: WorkspaceDocument, dir: URL) async throws -> StructureViewModel {
        let file = try #require(workspace.workspaceFileManager?.getFile(
            dir.appending(path: "Model.swift").path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
        let model = StructureViewModel(defaults: try IsolatedDefaults.require())
        model.start(workspace: workspace, lspService: LSPService())
        try await eventually { model.rows.count == 4 }
        return model
    }

    private func host(_ workspace: WorkspaceDocument, model: StructureViewModel) throws -> HostedView {
        return try HostedViewFixture.hostInWorkspace(workspace) { StructureToolWindow(model: model) }
    }

    @Test
    func headerTogglesRepaintTheTool() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            let hosted = try host(workspace, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            var previous = hosted.snapshot()
            #expect(hosted.renders())

            let toggles: [() -> Void] = [
                model.toggleSortsAlphabetically,
                model.toggleGroupsByKind,
                model.toggleAutoscrollToSource,
                model.toggleAutoscrollFromSource
            ]
            for toggle in toggles {
                toggle()
                try await hosted.settle()
                let current = hosted.snapshot()
                #expect(HostedView.pixelsDiffer(previous, current))
                previous = current
            }
            #expect(model.options.sortsAlphabetically)
            #expect(model.options.groupsByKind)
            #expect(model.options.autoscrollsToSource)
            #expect(model.options.autoscrollsFromSource == false)
        }
    }

    @Test
    func filterNarrowsTheTreeAndShowsTheNoMatchState() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            let hosted = try host(workspace, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            let full = hosted.snapshot()

            model.filterText = "run"
            try await hosted.settle()
            let narrowed = hosted.snapshot()
            #expect(model.rows.map(\.node.name) == ["Outer", "run"])
            #expect(HostedView.pixelsDiffer(full, narrowed))

            model.filterText = "zzzz"
            try await hosted.settle()
            #expect(model.rows.isEmpty)
            #expect(HostedView.pixelsDiffer(narrowed, hosted.snapshot()))
            #expect(hosted.renders())
        }
    }

    @Test
    func caretMovesScrollTheGroupedTreeToTheEnclosingSymbol() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            model.toggleGroupsByKind()
            let hosted = try host(workspace, model: model)
            defer { hosted.close() }
            try await hosted.settle()
            let before = hosted.snapshot()
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            let scrolls = model.scrollRequests

            tab.cursorPositions = [CursorPosition(line: 6, column: 1)]

            try await eventually { model.selection == "fallback/3" }
            try await hosted.settle()
            #expect(model.scrollRequests > scrolls)
            #expect(HostedView.pixelsDiffer(before, hosted.snapshot()))
        }
    }

    @Test
    func clickingSelectsWhileDoubleClickingAndReturnNavigate() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            var activations = 0
            let tree = StructureTreeView(model: model, workspace: workspace) { activations += 1 }
            let run = try #require(model.nodes.first?.children.last)

            tree.clicked(run)
            #expect(model.selection == "fallback/2")
            #expect(tab.cursorPositions.first?.start.line == 1)
            #expect(activations == 0)

            tree.doubleClicked(run)
            #expect(tab.cursorPositions.first?.start.line == 3)
            #expect(activations == 1)

            tab.cursorPositions = [CursorPosition(line: 1, column: 1)]
            #expect(tree.returnPressed() == .handled)
            #expect(tab.cursorPositions.first?.start.line == 3)
            #expect(activations == 2)

            #expect(tree.move(-1) == .handled)
            #expect(model.selection == "fallback/1")
        }
    }

    @Test
    func popupStyleTreesActivateOnASingleClickExceptOnGroups() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            model.toggleGroupsByKind()
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            var activations = 0
            let tree = StructureTreeView(model: model, workspace: workspace, activatesOnClick: true) {
                activations += 1
            }
            let group = try #require(model.rows.first?.node)
            let top = try #require(model.rows.last?.node)

            tree.clicked(group)
            #expect(activations == 0)
            #expect(model.collapsed == ["group/Classes"])

            tree.clicked(top)
            #expect(activations == 1)
            #expect(tab.cursorPositions.first?.start.line == 6)

            tree.doubleClicked(group)
            #expect(activations == 1)
            #expect(model.collapsed.isEmpty)
        }
    }

    @Test
    func filterFieldArrowsMoveTheTreeSelection() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let model = try await loadedModel(workspace, dir: dir)
            let field = StructureFilterField(model: model, workspace: workspace) {}
            #expect(model.selection == "fallback/0")

            #expect(field.move(1) == .handled)
            #expect(model.selection == "fallback/1")
            #expect(field.move(-1) == .handled)
            #expect(model.selection == "fallback/0")
        }
    }

    @Test
    func togglesRenderInEveryState() async throws {
        let off = HostedViewFixture.host(size: NSSize(width: 60, height: 40)) {
            StructureToggleButton(icon: "general/sortBy", help: "Sort", isOn: false) {}
        }
        defer { off.close() }
        let on = HostedViewFixture.host(size: NSSize(width: 60, height: 40)) {
            StructureToggleButton(icon: "general/sortBy", help: "Sort", isOn: true) {}
        }
        defer { on.close() }
        try await off.settle()
        try await on.settle()
        #expect(off.renders())
        #expect(HostedView.pixelsDiffer(off.snapshot(), on.snapshot()))
    }
}
