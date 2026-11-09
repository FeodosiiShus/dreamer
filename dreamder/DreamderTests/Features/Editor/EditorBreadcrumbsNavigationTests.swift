import AppKit
import CodeEditSourceEditor
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private struct NavigationSession {
    static let nested = "# Alpha\n\n## Beta\n\ntext\n"

    let document: CodeFileDocument
    let instance: EditorInstance

    static func make(in directory: URL, name: String = "Doc.md") throws -> Self {
        let url = directory.appending(path: name).standardizedFileURL
        let document = try TabBarCoverageLanguageServer.makeDocument(
            at: url,
            contents: nested,
            typeIdentifier: "public.source-code"
        )
        let instance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        return Self(document: document, instance: instance)
    }

    func content(
        model: EditorBreadcrumbsModel = EditorBreadcrumbsModel(),
        workspace: WorkspaceDocument? = nil
    ) -> EditorBreadcrumbsBarContent {
        EditorBreadcrumbsBarContent(
            editorInstance: instance,
            codeFile: document,
            lspService: LSPService(),
            toolWindowManager: ToolWindowManager(),
            workspace: workspace,
            model: model
        )
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorBreadcrumbsNavigationTests {
    private func popups(in window: NSWindow) -> [ShowUsagesPanel] {
        (window.childWindows ?? []).compactMap { $0 as? ShowUsagesPanel }
    }

    @Test
    func itemsListTheFolderThenTheFileThenTheSymbols() {
        let symbol = StructureNode(id: "s", name: "Sym", detail: nil, kind: .function, line: 4, column: 2, children: [])
        let url = URL(fileURLWithPath: "/project/src/App.swift")

        let items = EditorBreadcrumbItem.items(url: url, symbols: [symbol])

        #expect(items.map(\.title) == ["src", "App.swift", "Sym"])
        #expect(items.map(\.id) == ["path/folder", "path/file", "s"])
        #expect(items.map(\.target) == [.folder, .file, .symbol(symbol)])
    }

    @Test
    func aFileDirectlyInTheRootHasNoFolderCrumb() {
        let items = EditorBreadcrumbItem.items(url: URL(fileURLWithPath: "/App.swift"), symbols: [])

        #expect(items.map(\.title) == ["App.swift"])
    }

    @Test
    func clickingASymbolCrumbMovesTheCaretToTheSymbol() async throws {
        try await withTempDir { directory in
            let session = try NavigationSession.make(in: directory)
            let model = EditorBreadcrumbsModel()
            model.bind(instance: session.instance, document: session.document, lspService: LSPService())
            session.instance.cursorPositions = [CursorPosition(line: 3, column: 1)]
            try await eventually(timeout: .seconds(5)) { model.crumbs.map(\.name) == ["Alpha", "Beta"] }
            let content = session.content(model: model)
            let items = EditorBreadcrumbItem.items(url: session.instance.file.url, symbols: model.crumbs)
            let alpha = try #require(items.first { $0.title == "Alpha" })

            content.activate(alpha)

            let position = try #require(session.instance.cursorPositions.first)
            #expect(position.start.line == 1)
            #expect(position.start.column == 1)
            try await eventually(timeout: .seconds(5)) { model.crumbs.map(\.name) == ["Alpha"] }
        }
    }

    @Test
    func clickingTheFolderCrumbDoesNothing() async throws {
        try withTempDir { directory in
            let session = try NavigationSession.make(in: directory)
            session.instance.cursorPositions = [CursorPosition(line: 3, column: 1)]
            let folder = EditorBreadcrumbItem(id: "path/folder", title: "dir", target: .folder)

            session.content().activate(folder)

            #expect(session.instance.cursorPositions.first?.start.line == 3)
        }
    }

    @Test
    func hoveringACrumbTracksItAndRepaintsTheBar() async throws {
        try await withTempDir { directory in
            let session = try NavigationSession.make(in: directory)
            let model = EditorBreadcrumbsModel()
            let hosted = HostedViewFixture.host(size: NSSize(width: 500, height: 60)) {
                session.content(model: model)
            }
            defer { hosted.close() }
            try await hosted.settle()
            let idle = hosted.snapshot()

            model.hover("path/file", isHovering: true)
            #expect(model.hoveredCrumbID == "path/file")
            try await hosted.settle()
            let hovered = hosted.snapshot()
            #expect(HostedView.pixelsDiffer(idle, hovered))

            model.hover("path/folder", isHovering: false)
            #expect(model.hoveredCrumbID == "path/file")

            model.hover("path/file", isHovering: false)
            #expect(model.hoveredCrumbID == nil)
            try await hosted.settle()
            #expect(HostedView.pixelsDiffer(hovered, hosted.snapshot()))
        }
    }

    @Test
    func crumbHandlersHoverTheModelAndActivateTheItem() throws {
        try withTempDir { directory in
            let session = try NavigationSession.make(in: directory)
            session.instance.cursorPositions = [CursorPosition(line: 3, column: 1)]
            let model = EditorBreadcrumbsModel()
            let content = session.content(model: model)
            let symbol = StructureNode(id: "s", name: "Sym", detail: nil, kind: .function, line: 7, column: 2, children: [])
            let item = EditorBreadcrumbItem(id: "s", title: "Sym", target: .symbol(symbol))

            content.hoverAction(for: item)(true)
            #expect(model.hoveredCrumbID == "s")
            content.hoverAction(for: item)(false)
            #expect(model.hoveredCrumbID == nil)

            content.tapAction(for: item)()
            let position = try #require(session.instance.cursorPositions.first)
            #expect(position.start.line == 7)
            #expect(position.start.column == 2)
        }
    }

    @Test
    func clickingTheFileCrumbOpensTheStructurePopup() async throws {
        try withTempDir { directory in
            let session = try NavigationSession.make(in: directory)
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            workspace.makeWindowControllers()
            let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
            let window = try #require(controller.window)
            window.isReleasedWhenClosed = false
            window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
            defer {
                for child in window.childWindows ?? [] {
                    child.close()
                }
                window.close()
                workspace.close()
            }
            let content = session.content(workspace: workspace)
            let file = EditorBreadcrumbItem(id: "path/file", title: "Doc.md", target: .file)

            content.activate(file)

            let panel = try #require(popups(in: window).first)
            #expect(panel.contentView is NSHostingView<StructurePopupView>)
        }
    }

    @Test
    func theFileCrumbWithoutAWorkspaceOrControllerOpensNothing() async throws {
        try withTempDir { directory in
            let session = try NavigationSession.make(in: directory)
            let workspace = WorkspaceDocument()
            try workspace.read(from: directory, ofType: "")
            defer { workspace.close() }
            let file = EditorBreadcrumbItem(id: "path/file", title: "Doc.md", target: .file)

            session.content().activate(file)
            session.content(workspace: workspace).openStructurePopup()

            #expect(workspace.windowControllers.isEmpty)
        }
    }

    @Test
    func theBarInjectsTheWorkspaceFromTheEnvironment() async throws {
        try await withTempDir { directory in
            let session = try NavigationSession.make(in: directory)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 500, height: 60)) {
                EditorBreadcrumbsBar(editorInstance: session.instance, codeFile: session.document)
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
        }
    }
}
