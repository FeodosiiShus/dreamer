import AppKit
import CodeEditSourceEditor
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct IslandsViewHandlersTests {
    private static let source = "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"

    private func makeWorkspace(_ directory: URL) throws -> WorkspaceDocument {
        try Self.source.write(to: directory.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        return try HostedViewFixture.makeWorkspace(in: directory)
    }

    private func openModel(in workspace: WorkspaceDocument, directory: URL) throws -> CEWorkspaceFile {
        let file = try #require(workspace.workspaceFileManager?.getFile(
            directory.appending(path: "Model.swift").path(percentEncoded: false),
            createIfNotFound: true
        ))
        workspace.editorManager?.openTab(item: file)
        return file
    }

    private func loadedModel(
        _ workspace: WorkspaceDocument,
        autoscrollsFromSource: Bool
    ) async throws -> StructureViewModel {
        let model = StructureViewModel(defaults: try IsolatedDefaults.require())
        if model.options.autoscrollsFromSource != autoscrollsFromSource {
            model.toggleAutoscrollFromSource()
        }
        model.start(workspace: workspace, lspService: LSPService())
        try await eventually { !model.nodes.isEmpty }
        return model
    }

    @Test
    func submissionActivatesTheSelectionAndThenRunsTheCompletion() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(directory)
            defer { workspace.close() }
            _ = try openModel(in: workspace, directory: directory)
            let model = try await loadedModel(workspace, autoscrollsFromSource: true)
            let node = try #require(model.rows.first?.node)
            model.select(node, workspace: workspace)
            var completions = 0

            model.submission(workspace: workspace, then: { completions += 1 })()
            model.submission(workspace: workspace)()

            #expect(completions == 1)
            #expect(model.selection == node.id)
        }
    }

    @Test
    func movingWithoutASelectionStartsAtTheFirstOrLastRow() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(directory)
            defer { workspace.close() }
            _ = try openModel(in: workspace, directory: directory)
            let down = try await loadedModel(workspace, autoscrollsFromSource: false)
            let up = try await loadedModel(workspace, autoscrollsFromSource: false)
            #expect(down.selection == nil)

            down.moveSelection(by: 1, workspace: workspace)
            up.moveSelection(by: -1, workspace: workspace)

            #expect(down.selection == down.rows.first?.id)
            #expect(up.selection == up.rows.last?.id)
        }
    }

    @Test
    func aDocumentThatDisappearsClearsTheTree() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(directory)
            defer { workspace.close() }
            let file = try openModel(in: workspace, directory: directory)
            let model = try await loadedModel(workspace, autoscrollsFromSource: true)

            file.fileDocument = nil
            model.scheduleRefresh(delay: .milliseconds(1))

            try await eventually { model.nodes.isEmpty }
        }
    }

    @Test
    func caretsWithoutLineNumbersFallBackToTheDocumentText() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(directory)
            defer { workspace.close() }
            let file = try openModel(in: workspace, directory: directory)
            let tab = try #require(workspace.editorManager?.activeEditor.selectedTab)
            let model = try await loadedModel(workspace, autoscrollsFromSource: false)
            #expect(model.selection == nil)
            file.fileDocument?.content = nil
            tab.cursorPositions = [CursorPosition(range: NSRange(location: 3, length: 0))]

            model.toggleAutoscrollFromSource()

            #expect(model.selection == model.rows.first?.id)
        }
    }

    @Test
    func structureKeyHandlersMoveTheSelectionAndHandleTheKey() async throws {
        try await withTempDir { directory in
            let workspace = try makeWorkspace(directory)
            defer { workspace.close() }
            _ = try openModel(in: workspace, directory: directory)
            let model = try await loadedModel(workspace, autoscrollsFromSource: false)
            let field = StructureFilterField(model: model, workspace: workspace, onSubmit: {})
            let tree = StructureTreeView(model: model, workspace: workspace)

            #expect(field.moveDown() == .handled)
            #expect(model.selection == model.rows.first?.id)
            #expect(tree.moveDown() == .handled)
            #expect(model.selection == model.rows.dropFirst().first?.id)
            #expect(field.moveUp() == .handled)
            #expect(tree.moveUp() == .handled)
            #expect(model.selection == model.rows.first?.id)
        }
    }

    @Test
    func toggleButtonsAndStripeButtonsTrackHover() {
        let toggle = StructureToggleButton(icon: "general/sortBy", help: "Sort", isOn: false, action: {})

        toggle.setHovering(true)
        toggle.setHovering(false)
    }

    @Test
    func toolWindowHeaderControlsTrackHover() {
        let tab = ToolWindowTab(title: "Tab", isSelected: false, action: {})
        let button = ToolWindowActionButton(icon: "general/hide", help: "Hide", action: {})

        tab.setHovering(true)
        tab.setHovering(false)
        button.setHovering(true)
        button.setHovering(false)
    }

    @Test
    func problemsNavigationWithoutAProjectFindsNothing() {
        let workspace = WorkspaceDocument()

        #expect(ProblemsNavigator.navigate(.next, workspace: workspace) == nil)
        #expect(ProblemsNavigator.navigate(.previous, workspace: nil) == nil)
    }

    @Test
    func runConfigurationsToggleIsCallable() {
        RunToolWindow().toggleConfigurations()
    }
}
