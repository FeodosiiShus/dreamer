import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension StructureViewModelCoverageTests {
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

    @Test
    func theFallbackAwaitsTheDiskReadOffTheMainThreadWhileTheTreeStaysResponsive() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let probe = StructureReaderProbe(text: "func fromReader() {}\n")
            let model = StructureViewModel(
                defaults: try IsolatedDefaults.require(),
                readText: { await probe.read($0) }
            )
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }
            #expect(probe.urls.isEmpty)

            document.content = nil
            model.scheduleRefresh(delay: .milliseconds(1))
            try await eventually { probe.urls.count == 1 }

            #expect(probe.readsOnMainThread == [false])
            #expect(probe.urls.map(\.lastPathComponent) == ["Model.swift"])
            #expect(model.nodes.map(\.name) == ["Outer", "topLevel"])

            probe.release()
            try await eventually { model.nodes.map(\.name) == ["fromReader"] }
        }
    }

    @Test
    func aDiskReadStartedForOneFileNeverReplacesTheTreeOfTheNextFile() async throws {
        try await withTempDir { dir in
            let workspace = try makeWorkspace(dir)
            defer { workspace.close() }
            let document = try open("Model.swift", in: workspace, dir: dir)
            let probe = StructureReaderProbe(text: "func stale() {}\n")
            let model = StructureViewModel(
                defaults: try IsolatedDefaults.require(),
                readText: { await probe.read($0) }
            )
            model.start(workspace: workspace, lspService: LSPService())
            try await eventually { model.nodes.map(\.name) == ["Outer", "topLevel"] }

            document.content = nil
            model.scheduleRefresh(delay: .milliseconds(1))
            try await eventually { probe.urls.count == 1 }
            let staleRequest = try #require(model.requestTask)

            _ = try open("Other.swift", in: workspace, dir: dir)
            try await eventually { model.nodes.map(\.name) == ["Other"] }
            #expect(staleRequest.isCancelled)

            probe.release()
            await staleRequest.value

            #expect(model.nodes.map(\.name) == ["Other"])
            #expect(model.fileURL?.lastPathComponent == "Other.swift")
        }
    }
}
