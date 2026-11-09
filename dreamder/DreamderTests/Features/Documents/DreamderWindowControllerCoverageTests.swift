import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerCoverageTests {
    @MainActor
    struct Harness {
        let directory: URL
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        var manager: EditorManager? { workspace.editorManager }

        var openTabNames: [String] {
            manager?.activeEditor.tabs.map(\.file.name) ?? []
        }

        func openTab(_ name: String) throws {
            let path = directory.appending(path: name).path(percentEncoded: false)
            let file = try #require(workspace.workspaceFileManager?.getFile(path, createIfNotFound: true))
            manager?.openTab(item: file)
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }
    }

    func makeHarness(in directory: URL, files: [String] = ["One.swift"]) throws -> Harness {
        for name in files {
            try "let value = 1\n".write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        window.orderFront(nil)
        return Harness(directory: directory, workspace: workspace, controller: controller, window: window)
    }

    @Test
    func aControllerWithoutAWindowKeepsTheWorkspaceButHostsNothing() {
        let workspace = WorkspaceDocument()

        let controller = DreamderWindowController(window: nil, workspace: workspace)

        #expect(controller.workspace === workspace)
        #expect(controller.workspaceHostingController == nil)
        #expect(controller.documentEditedObservation != nil)
    }

    @Test
    func aWorkspaceWithoutItsManagersLeavesTheWindowWithoutContent() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let controller = DreamderWindowController(window: window, workspace: WorkspaceDocument())

        #expect(controller.workspaceHostingController == nil)
        #expect(window.contentViewController == nil)
        #expect(window.delegate === controller)
        #expect(window.toolbar == nil)
    }

    @Test
    func aWorkspaceWindowIsTitledTabbedHostedAndGivenAToolbar() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            #expect(harness.window.title == directory.lastPathComponent)
            #expect(harness.window.tabbingIdentifier == "dreamder.workspace")
            #expect(harness.window.tabbingMode == .preferred)
            #expect(harness.controller.workspaceHostingController != nil)
            #expect(harness.window.toolbar?.identifier == "DreamderMainToolbar")
            #expect(!harness.controller.toolbarCollapsed)
        }
    }

    @Test
    func aWorkspaceWithAStoredCollapsedToolbarOpensWithoutOne() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            workspace.addToWorkspaceState(key: .toolbarCollapsed, value: true)
            workspace.makeWindowControllers()
            let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
            let window = try #require(controller.window)
            window.isReleasedWhenClosed = false
            defer {
                window.close()
                workspace.close()
            }

            #expect(controller.toolbarCollapsed)
            #expect(window.toolbar == nil)
            #expect(window.titleVisibility == .visible)
        }
    }

    @Test
    func searchNavigatorShowsTheFindToolWindowAndFocusesItsField() async throws {
        try await withTempDir { directory in
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            defer { workspace.close() }
            let controller = DreamderWindowController(window: nil, workspace: workspace)
            workspace.toolWindowManager.hideAll()

            controller.openSearchNavigator()

            #expect(workspace.toolWindowManager.isVisible(.find))
            try await eventually(timeout: .seconds(30)) {
                workspace.searchState?.shouldFocusSearchField == true
            }
        }
    }

    @Test
    func searchNavigatorNeedsAWorkspace() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.openSearchNavigator(nil)

        #expect(controller.workspace == nil)
    }

    @Test
    func theSelectedCodeFileIsTheActiveEditorsDocument() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            #expect(harness.controller.getSelectedCodeFile() == nil)

            try harness.openTab("One.swift")

            let codeFile = try #require(harness.controller.getSelectedCodeFile())
            #expect(codeFile.fileURL?.lastPathComponent == "One.swift")
        }
    }

    @Test
    func theMarkdownClipboardReadsTheInjectedPasteboardUnlessOverridden() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let pasteboard = InMemoryPasteboard()
            harness.controller.markdownPasteboard = pasteboard

            #expect(harness.controller.markdownClipboard() == nil)

            pasteboard.replaceContents(withText: "https://example.com")
            #expect(harness.controller.markdownClipboard() == "https://example.com")

            harness.controller.markdownClipboard = { "override" }
            #expect(harness.controller.markdownClipboard() == "override")
        }
    }
}
