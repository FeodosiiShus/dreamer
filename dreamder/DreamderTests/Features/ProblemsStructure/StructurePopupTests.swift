import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct StructurePopupTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        try "struct Outer {\n    let value: Int\n    func run() {}\n}\n\nfunc topLevel() {}\n"
            .write(to: directory.appending(path: "Model.swift"), atomically: true, encoding: .utf8)
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return Harness(workspace: workspace, controller: controller, window: window)
    }

    private func popups(in window: NSWindow) -> [ShowUsagesPanel] {
        (window.childWindows ?? []).compactMap { $0 as? ShowUsagesPanel }
    }

    private func keyEvent(_ code: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: code
        ))
    }

    @Test
    func theActionPresentsAFixedSizePopupAndReplacesThePreviousOne() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.showFileStructure(nil)
            let first = try #require(popups(in: harness.window).first)
            let hosting = try #require(first.contentView as? NSHostingView<StructurePopupView>)
            #expect(hosting.sizingOptions == [])
            #expect(first.frame.size == StructurePopupView.size)

            harness.controller.showFileStructure(nil)
            let current = popups(in: harness.window)
            #expect(current.count == 1)
            #expect(current.first !== first)
        }
    }

    @Test
    func aControllerWithoutAWorkspaceShowsNothing() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.controller.workspace = nil

            StructurePopupHost.shared.show(in: harness.controller)

            #expect(popups(in: harness.window).isEmpty)
        }
    }

    @Test
    func keysDriveTheSelectionAndEscapeClosesThePopup() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let file = try #require(harness.workspace.workspaceFileManager?.getFile(
                directory.appending(path: "Model.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            harness.workspace.editorManager?.openTab(item: file)

            StructurePopupHost.shared.show(in: harness.controller)
            let panel = try #require(popups(in: harness.window).first)
            let hosting = try #require(panel.contentView as? NSHostingView<StructurePopupView>)
            let model = hosting.rootView.model
            model.start(workspace: harness.workspace, lspService: LSPService())
            try await eventually { model.rows.count == 4 }
            #expect(model.selection == "fallback/0")

            let handleKey = try #require(panel.onKeyEvent)
            #expect(handleKey(try keyEvent(125)))
            #expect(model.selection == "fallback/1")
            #expect(handleKey(try keyEvent(126)))
            #expect(model.selection == "fallback/0")
            #expect(handleKey(try keyEvent(36)) == false)

            #expect(handleKey(try keyEvent(53)))
            #expect(popups(in: harness.window).isEmpty)
        }
    }

    @Test
    func activatingFromThePopupNavigatesAndDismisses() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let file = try #require(harness.workspace.workspaceFileManager?.getFile(
                directory.appending(path: "Model.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            harness.workspace.editorManager?.openTab(item: file)

            StructurePopupHost.shared.show(in: harness.controller)
            let panel = try #require(popups(in: harness.window).first)
            let hosting = try #require(panel.contentView as? NSHostingView<StructurePopupView>)
            let model = hosting.rootView.model
            model.start(workspace: harness.workspace, lspService: LSPService())
            try await eventually { model.rows.count == 4 }
            let tab = try #require(harness.workspace.editorManager?.activeEditor.selectedTab)
            let top = try #require(model.nodes.last)

            let tree = StructureTreeView(
                model: model,
                workspace: harness.workspace,
                activatesOnClick: true,
                onActivate: hosting.rootView.dismiss
            )
            tree.clicked(top)

            #expect(tab.cursorPositions.first?.start.line == 6)
            #expect(popups(in: harness.window).isEmpty)
        }
    }

    @Test
    func popupRendersTheTreeAndTheEmptyAndLoadingStates() async throws {
        try await withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let empty = StructureViewModel(defaults: try IsolatedDefaults.require())
            let emptyHosted = HostedViewFixture.host(size: StructurePopupView.size) {
                StructurePopupView(model: empty, workspace: harness.workspace)
            }
            defer { emptyHosted.close() }
            try await emptyHosted.settle()
            #expect(emptyHosted.renders())
            let emptySnapshot = emptyHosted.snapshot()
            let file = try #require(harness.workspace.workspaceFileManager?.getFile(
                directory.appending(path: "Model.swift").path(percentEncoded: false),
                createIfNotFound: true
            ))
            harness.workspace.editorManager?.openTab(item: file)
            let filled = StructureViewModel(defaults: try IsolatedDefaults.require())
            let filledHosted = HostedViewFixture.host(size: StructurePopupView.size) {
                StructurePopupView(model: filled, workspace: harness.workspace)
            }
            defer { filledHosted.close() }
            try await eventually(timeout: .seconds(30)) { filled.rows.count == 4 }
            try await filledHosted.settle()
            try await eventually(timeout: .seconds(30)) {
                filledHosted.layout()
                return HostedView.pixelsDiffer(emptySnapshot, filledHosted.snapshot())
            }
        }
    }
}
