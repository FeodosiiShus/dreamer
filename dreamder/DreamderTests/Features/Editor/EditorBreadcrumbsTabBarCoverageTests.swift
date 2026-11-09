import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@Observable
@MainActor
private final class BreadcrumbDocumentSwitch {
    var document: CodeFileDocument

    init(document: CodeFileDocument) {
        self.document = document
    }
}

private struct BreadcrumbSwitchHost: View {
    let switcher: BreadcrumbDocumentSwitch
    let instance: EditorInstance
    let lspService: LSPService
    let toolWindowManager: ToolWindowManager
    let model: EditorBreadcrumbsModel

    var body: some View {
        EditorBreadcrumbsBarContent(
            editorInstance: instance,
            codeFile: switcher.document,
            lspService: lspService,
            toolWindowManager: toolWindowManager,
            model: model
        )
    }
}

@MainActor
private struct BreadcrumbSession {
    static let nested = "# Alpha\n\n## Beta\n\ntext\n"

    let document: CodeFileDocument
    let instance: EditorInstance

    static func make(in directory: URL, name: String = "Doc.md", contents: String = Self.nested) throws -> Self {
        let url = directory.appending(path: name).standardizedFileURL
        let document = try TabBarCoverageLanguageServer.makeDocument(
            at: url,
            contents: contents,
            typeIdentifier: "public.source-code"
        )
        let instance = EditorInstance(workspace: nil, file: CEWorkspaceFile(url: url))
        return Self(document: document, instance: instance)
    }

    func moveCursor(toLine line: Int) {
        instance.cursorPositions = [CursorPosition(line: line, column: 1)]
    }
}

@MainActor
private func breadcrumbNames(_ model: EditorBreadcrumbsModel) -> [String] {
    model.crumbs.map(\.name)
}

@MainActor
private func awaitRepaint(_ hosted: HostedView, from before: NSBitmapImageRep?) async throws -> NSBitmapImageRep? {
    var latest = before
    try await eventually(timeout: .seconds(30)) {
        latest = hosted.snapshot()
        return HostedView.pixelsDiffer(before, latest)
    }
    return latest
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorBreadcrumbsModelTabBarCoverageTests {
    @Test
    func cursorMovesTheBreadcrumbsThroughNestedHeaders() async throws {
        try await withTempDir { directory in
            let session = try BreadcrumbSession.make(in: directory)
            let model = EditorBreadcrumbsModel()
            model.bind(instance: session.instance, document: session.document, lspService: LSPService())

            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha"] }

            session.moveCursor(toLine: 3)
            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha", "Beta"] }

            session.instance.cursorPositions = [CursorPosition(range: NSRange(location: 0, length: 0))]
            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha"] }

            session.instance.cursorPositions = [CursorPosition(range: NSRange(location: 10, length: 0))]
            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha", "Beta"] }
        }
    }

    @Test
    func textEditsReloadTheBreadcrumbsAfterTheDebounce() async throws {
        try await withTempDir { directory in
            let session = try BreadcrumbSession.make(in: directory, contents: "# Alpha\n")
            let fixture = HostedSourceEditorFixture(document: session.document, editorInstance: session.instance)
            let hosted = fixture.host(
                coordinators: [session.document.contentCoordinator],
                size: NSSize(width: 900, height: 600)
            )
            defer { hosted.close() }
            try await eventually(timeout: .seconds(30)) { hosted.controller?.textView?.window === hosted.window }
            let textView = try #require(hosted.controller?.textView)
            let model = EditorBreadcrumbsModel()
            model.bind(instance: session.instance, document: session.document, lspService: LSPService())
            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha"] }

            textView.replaceCharacters(in: NSRange(location: 2, length: 5), with: "Gamma")

            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Gamma"] }
        }
    }

    @Test
    func languageServerSymbolsReplaceTheTextExtractor() async throws {
        try await withTempDir { directory in
            let session = try BreadcrumbSession.make(in: directory)
            let service = LSPService()
            try await TabBarCoverageLanguageServer.install(
                symbolPayload: TabBarCoverageLanguageServer.symbols(TabBarCoverageLanguageServer.outerInnerSymbols()),
                tracking: session.document,
                in: service
            )
            session.moveCursor(toLine: 3)
            let model = EditorBreadcrumbsModel()

            model.bind(instance: session.instance, document: session.document, lspService: service)

            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["ServerOuter", "serverInner"] }
        }
    }

    @Test
    func emptyLanguageServerAnswerFallsBackToTheTextExtractor() async throws {
        try await withTempDir { directory in
            let session = try BreadcrumbSession.make(in: directory)
            let service = LSPService()
            try await TabBarCoverageLanguageServer.install(
                symbolPayload: TabBarCoverageLanguageServer.nullSymbols,
                tracking: session.document,
                in: service
            )
            session.moveCursor(toLine: 3)
            let model = EditorBreadcrumbsModel()

            model.bind(instance: session.instance, document: session.document, lspService: service)

            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha", "Beta"] }
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorBreadcrumbsBarTabBarCoverageTests {
    @Test
    func contentCopiesThePathAndRevealsTheStructureToolWindow() async throws {
        try withTempDir { directory in
            let session = try BreadcrumbSession.make(in: directory)
            let manager = ToolWindowManager()
            let pasteboard = InMemoryPasteboard()
            let content = EditorBreadcrumbsBarContent(
                editorInstance: session.instance,
                codeFile: session.document,
                lspService: LSPService(),
                toolWindowManager: manager,
                pasteboard: pasteboard
            )

            content.copyPath()
            content.showStructure()

            #expect(pasteboard.plainText == session.instance.file.url.path(percentEncoded: false))
            #expect(manager.isVisible(.structure))
        }
    }

    @Test
    func contextMenuOffersTheStructureToolWindowAndCopyPath() throws {
        try withTempDir { directory in
            let session = try BreadcrumbSession.make(in: directory)
            let manager = ToolWindowManager()
            let pasteboard = InMemoryPasteboard()
            let content = EditorBreadcrumbsBarContent(
                editorInstance: session.instance,
                codeFile: session.document,
                lspService: LSPService(),
                toolWindowManager: manager,
                pasteboard: pasteboard
            )
            let menu = CommandsACoverageSupport.host { content.contextMenuItems() }
            defer { menu.close() }

            #expect(menu.titles == ["Show Structure Tool Window", "Copy Path"])

            try menu.click(titled: "Copy Path")
            try menu.click(titled: "Show Structure Tool Window")

            #expect(pasteboard.plainText == session.instance.file.url.path(percentEncoded: false))
            #expect(manager.isVisible(.structure))
        }
    }

    @Test
    func contentRendersCrumbsAndRebindsWhenTheDocumentChanges() async throws {
        try await withTempDir { directory in
            let first = try BreadcrumbSession.make(in: directory, name: "One.md")
            let second = try BreadcrumbSession.make(in: directory, name: "Two.md", contents: "# Omega\n\n## Sigma\n")
            let switcher = BreadcrumbDocumentSwitch(document: first.document)
            let service = LSPService()
            let manager = ToolWindowManager()
            let model = EditorBreadcrumbsModel()
            let hosted = HostedViewFixture.host(size: NSSize(width: 500, height: 60)) {
                BreadcrumbSwitchHost(
                    switcher: switcher,
                    instance: first.instance,
                    lspService: service,
                    toolWindowManager: manager,
                    model: model
                )
            }
            defer { hosted.close() }

            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha"] }
            try await hosted.settle(.milliseconds(100))
            let singleCrumb = hosted.snapshot()
            #expect(hosted.renders())

            first.moveCursor(toLine: 3)
            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Alpha", "Beta"] }
            let nested = try await awaitRepaint(hosted, from: singleCrumb)

            switcher.document = second.document
            try await eventually(timeout: .seconds(30)) { breadcrumbNames(model) == ["Omega", "Sigma"] }
            _ = try await awaitRepaint(hosted, from: nested)
        }
    }

    @Test
    func barReadsItsEnvironmentAndRendersTheCrumbs() async throws {
        try await withTempDir { directory in
            let session = try BreadcrumbSession.make(in: directory)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 500, height: 60)) {
                EditorBreadcrumbsBar(editorInstance: session.instance, codeFile: session.document)
            }
            defer { hosted.close() }
            let beforeBinding = hosted.snapshot()

            _ = try await awaitRepaint(hosted, from: beforeBinding)
        }
    }
}
