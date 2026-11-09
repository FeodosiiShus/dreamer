import AppKit
import CodeEditSourceEditor
import CodeEditTextView
import Foundation
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
private final class DefinitionDelegateUsagesRecorder {
    private(set) var controllers: [DreamderWindowController] = []

    func record(_ controller: DreamderWindowController) {
        controllers.append(controller)
    }
}

@MainActor
private final class DefinitionDelegateHarness {
    static let mainText = "let value = helper()\nlet other = 2\n"
    static let helperText = "func helper() {}\nfunc helper(_ value: Int) {}\n"
    static let symbolRange = NSRange(location: 12, length: 6)

    let hosted: HostedSourceEditor
    let editor: TextViewController
    let workspace: WorkspaceDocument
    let server: SyncTestServer
    let document: SyncTestDocument
    let delegate: LSPJumpToDefinitionDelegate<SyncTestDocument>
    let usages: DefinitionDelegateUsagesRecorder
    let windowController: DreamderWindowController
    let directory: URL
    let mainURI: String
    let helperURI: String

    static func make(in directory: URL) async throws -> DefinitionDelegateHarness {
        try helperText.write(to: directory.appending(path: "Helper.swift"), atomically: true, encoding: .utf8)
        let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
        let fixture = try HostedSourceEditorFixture.make(in: directory, fileName: "Main.swift", contents: mainText)
        let hosted = fixture.host(coordinators: [])
        try await eventually { hosted.controller?.textView != nil }
        let editor = try #require(hosted.controller)
        try await eventually { editor.textView.lspRangeFrom(nsRange: symbolRange) != nil }
        let server = try await SyncTestServer.make()
        let mainURL = try #require(fixture.document.fileURL)
        let document = try await server.open(uri: mainURL.lspURI, text: mainText)
        let windowController = DreamderWindowController(window: NSWindow(), workspace: nil)
        let recorder = DefinitionDelegateUsagesRecorder()
        let delegate = LSPJumpToDefinitionDelegate<SyncTestDocument>(
            controllerProvider: { _ in windowController },
            showUsages: { recorder.record($0) }
        )
        delegate.setUp(server: server.server, document: document)
        return DefinitionDelegateHarness(
            hosted: hosted,
            editor: editor,
            workspace: workspace,
            server: server,
            document: document,
            delegate: delegate,
            usages: recorder,
            windowController: windowController,
            directory: directory,
            mainURI: mainURL.lspURI,
            helperURI: directory.appending(path: "Helper.swift").lspURI
        )
    }

    private init(
        hosted: HostedSourceEditor,
        editor: TextViewController,
        workspace: WorkspaceDocument,
        server: SyncTestServer,
        document: SyncTestDocument,
        delegate: LSPJumpToDefinitionDelegate<SyncTestDocument>,
        usages: DefinitionDelegateUsagesRecorder,
        windowController: DreamderWindowController,
        directory: URL,
        mainURI: String,
        helperURI: String
    ) {
        self.hosted = hosted
        self.editor = editor
        self.workspace = workspace
        self.server = server
        self.document = document
        self.delegate = delegate
        self.usages = usages
        self.windowController = windowController
        self.directory = directory
        self.mainURI = mainURI
        self.helperURI = helperURI
    }

    func close() {
        hosted.close()
        windowController.window?.close()
        workspace.close()
    }

    func location(_ uri: String, _ line: Int, _ start: Int, _ end: Int) -> Location {
        Location(
            uri: uri,
            range: LSPRange(
                start: Position(line: line, character: start),
                end: Position(line: line, character: end)
            )
        )
    }

    func script(_ locations: [Location]) throws {
        try server.connection.script(.textDocumentDefinition, locations)
    }

    func query(_ range: NSRange = DefinitionDelegateHarness.symbolRange) async -> [JumpToDefinitionLink]? {
        await delegate.queryLinks(forRange: range, textView: editor)
    }

    func activeFileName() -> String? {
        workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent
    }

    func activeCursor() -> CursorPosition? {
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct DefinitionJumpDelegateTests {
    @Test
    func aSingleOtherTargetBecomesOneLinkWithAPreviewAndOpensWithHistory() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            try harness.script([harness.location(harness.helperURI, 1, 5, 11)])

            let links = try #require(await harness.query())

            #expect(links.count == 1)
            let link = try #require(links.first)
            #expect(link.url == LSPDiagnosticMapping.fileURL(fromDocumentURI: harness.helperURI))
            #expect(link.targetRange.start.line == 2)
            #expect(link.targetRange.start.column == 6)
            #expect(link.label == "helper")
            #expect(link.sourcePreview == "func helper(_ value: Int) {}")

            harness.delegate.openLink(link: link)

            #expect(harness.activeFileName() == "Helper.swift")
            #expect(harness.activeCursor()?.start.line == 2)
            #expect(harness.usages.controllers.isEmpty)
        }
    }

    @Test
    func severalTargetsStayAsSeparateLinks() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            try harness.script([
                harness.location(harness.helperURI, 0, 5, 11),
                harness.location(harness.helperURI, 1, 5, 11),
                harness.location(harness.helperURI, 0, 5, 11)
            ])

            let links = try #require(await harness.query())

            #expect(links.map { $0.targetRange.start.line } == [1, 2])
            #expect(links.map(\.sourcePreview) == ["func helper() {}", "func helper(_ value: Int) {}"])
            harness.delegate.openLink(link: links[1])
            #expect(harness.activeFileName() == "Helper.swift")
            #expect(harness.activeCursor()?.start.line == 2)
        }
    }

    @Test
    func theDeclarationAnswerIsUsedWhenTheDefinitionIsEmpty() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            try harness.server.connection.script(
                .textDocumentDeclaration,
                harness.location(harness.helperURI, 0, 5, 11)
            )

            let links = try #require(await harness.query())

            #expect(links.count == 1)
            #expect(harness.server.connection.requestCount(.textDocumentDefinition) == 1)
            #expect(harness.server.connection.requestCount(.textDocumentDeclaration) == 1)
        }
    }

    @Test
    func theSymbolItselfYieldsOneSelfLinkThatShowsUsages() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            try harness.script([
                harness.location(harness.helperURI, 0, 5, 11),
                harness.location(harness.mainURI, 0, 12, 18)
            ])

            let links = try #require(await harness.query())

            #expect(links.count == 1)
            let link = try #require(links.first)
            #expect(link.url == LSPDiagnosticMapping.fileURL(fromDocumentURI: harness.mainURI))
            #expect(link.targetRange.start.line == 1)
            #expect(link.targetRange.start.column == 13)

            harness.delegate.openLink(link: link)

            #expect(harness.usages.controllers.count == 1)
            #expect(harness.usages.controllers.first === harness.windowController)
            #expect(harness.activeFileName() == nil)
        }
    }

    @Test
    func aSelfLinkJumpsWhenNoWindowControllerWasCaptured() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            let recorder = DefinitionDelegateUsagesRecorder()
            let delegate = LSPJumpToDefinitionDelegate<SyncTestDocument>(
                controllerProvider: { _ in nil },
                showUsages: { recorder.record($0) }
            )
            delegate.setUp(server: harness.server.server, document: harness.document)
            try harness.script([harness.location(harness.mainURI, 0, 12, 18)])

            let links = try #require(await delegate.queryLinks(forRange: DefinitionDelegateHarness.symbolRange, textView: harness.editor))
            delegate.openLink(link: links[0])

            #expect(recorder.controllers.isEmpty)
            #expect(harness.activeFileName() == "Main.swift")
        }
    }

    @Test
    func theSelfMarkerIsRefreshedByEveryQueryAndIgnoresForeignLinks() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            try harness.script([harness.location(harness.mainURI, 0, 12, 18)])
            let selfLinks = try #require(await harness.query())
            let foreign = JumpToDefinitionLink(
                url: LSPDiagnosticMapping.fileURL(fromDocumentURI: harness.helperURI),
                targetRange: CursorPosition(line: 1, column: 6),
                typeName: "helper",
                sourcePreview: "",
                documentation: nil
            )

            harness.delegate.openLink(link: foreign)
            #expect(harness.usages.controllers.isEmpty)
            #expect(harness.activeFileName() == "Helper.swift")

            try harness.script([harness.location(harness.helperURI, 0, 5, 11)])
            let otherSymbol = NSRange(location: 4, length: 5)
            _ = try #require(await harness.query(otherSymbol))
            harness.delegate.openLink(link: selfLinks[0])

            #expect(harness.usages.controllers.isEmpty)
            #expect(harness.activeFileName() == "Main.swift")
        }
    }

    @Test
    func linksWithoutAFileURLAreIgnored() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            let link = JumpToDefinitionLink(
                url: nil,
                targetRange: CursorPosition(line: 1, column: 1),
                typeName: "value",
                sourcePreview: "",
                documentation: nil
            )

            harness.delegate.openLink(link: link)

            #expect(harness.activeFileName() == nil)
            #expect(harness.usages.controllers.isEmpty)
        }
    }

    @Test
    func queriesYieldNothingWithoutAnAnswerAServerOrAUsableRange() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }

            #expect(await harness.query() == nil)
            #expect(await harness.query(NSRange(location: 10_000, length: 1)) == nil)

            let unattached = LSPJumpToDefinitionDelegate<SyncTestDocument>()
            #expect(await unattached.queryLinks(forRange: DefinitionDelegateHarness.symbolRange, textView: harness.editor) == nil)

            let untitled = SyncTestDocument(uri: "untitled:1", text: DefinitionDelegateHarness.mainText)
            let nonFile = LSPJumpToDefinitionDelegate<SyncTestDocument>()
            nonFile.setUp(server: harness.server.server, document: untitled)
            #expect(await nonFile.queryLinks(forRange: DefinitionDelegateHarness.symbolRange, textView: harness.editor) == nil)

            let uriless = SyncTestDocument(uri: nil, text: DefinitionDelegateHarness.mainText)
            let withoutURI = LSPJumpToDefinitionDelegate<SyncTestDocument>()
            withoutURI.setUp(server: harness.server.server, document: uriless)
            #expect(await withoutURI.queryLinks(forRange: DefinitionDelegateHarness.symbolRange, textView: harness.editor) == nil)

            try harness.script([harness.location(harness.helperURI, 0, 5, 11)])
            harness.delegate.reset()
            #expect(await harness.query() == nil)
        }
    }

    @Test
    func theDefaultDelegateResolvesTheWindowControllerOfTheEditorWindow() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionDelegateHarness.make(in: directory)
            defer { harness.close() }
            let window = harness.hosted.window
            let controller = DreamderWindowController(window: window, workspace: nil)
            window.windowController = controller
            let delegate = LSPJumpToDefinitionDelegate<SyncTestDocument>()
            delegate.setUp(server: harness.server.server, document: harness.document)
            try harness.script([harness.location(harness.mainURI, 0, 12, 18)])

            let links = try #require(await delegate.queryLinks(forRange: DefinitionDelegateHarness.symbolRange, textView: harness.editor))
            delegate.openLink(link: links[0])

            #expect(window.windowController === controller)
            #expect(harness.activeFileName() == nil)
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct DefinitionNavigatorJumpTests {
    @Test
    func jumpingOpensTheFileAtThePosition() throws {
        try withTempDir { directory in
            try "alpha\nbeta\n".write(to: directory.appending(path: "Target.swift"), atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let url = directory.appending(path: "Target.swift")

            LSPDefinitionNavigator.jump(url: url, position: CursorPosition(line: 2, column: 3), in: workspace)

            let tab = workspace.editorManager?.activeEditor.selectedTab
            #expect(tab?.file.url.lastPathComponent == "Target.swift")
            #expect(tab?.cursorPositions.first?.start.line == 2)
            #expect(tab?.cursorPositions.first?.start.column == 3)
        }
    }

    @Test
    func jumpingFindsTheWorkspaceOfTheFileOrDoesNothing() throws {
        try withTempDir { directory in
            try "alpha\n".write(to: directory.appending(path: "Target.swift"), atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }

            LSPDefinitionNavigator.jump(
                url: URL(fileURLWithPath: "/nonexistent/dreamder/Elsewhere.swift"),
                position: CursorPosition(line: 1, column: 1)
            )
            #expect(workspace.editorManager?.activeEditor.selectedTab == nil)

            LSPDefinitionNavigator.jump(
                url: directory.appending(path: "Target.swift"),
                position: CursorPosition(line: 1, column: 2)
            )
            #expect(workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first?.start.column == 2)
        }
    }

    @Test
    func jumpingToADestinationUsesItsOneBasedPosition() throws {
        try withTempDir { directory in
            try "alpha\nbeta\n".write(to: directory.appending(path: "Target.swift"), atomically: true, encoding: .utf8)
            let workspace = try HostedSourceEditorFixture.registerWorkspace(at: directory)
            defer { workspace.close() }
            let url = directory.appending(path: "Target.swift")
            let destination = LSPNavigationDestination(
                uri: url.lspURI,
                fileURL: url,
                range: LSPRange(start: Position(line: 1, character: 2), end: Position(line: 1, character: 4))
            )

            LSPDefinitionNavigator.jump(to: destination, in: workspace)

            let cursor = workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first
            #expect(cursor?.start.line == 2)
            #expect(cursor?.start.column == 3)
        }
    }

    @Test
    func openingInAWorkspaceWithoutAnEditorManagerOpensNothing() throws {
        try withTempDir { directory in
            let workspace = WorkspaceDocument()
            defer { workspace.close() }
            let manager = workspace.editorManager
            workspace.editorManager = nil

            LSPDefinitionNavigator.open(
                url: directory.appending(path: "Target.swift"),
                position: CursorPosition(line: 1, column: 1),
                in: workspace
            )

            #expect(manager?.activeEditor.tabs.isEmpty == true)
        }
    }

    @Test
    func aFileOutsideTheIndexedWorkspaceTreeStillOpensAtThePosition() throws {
        try withTempDir { directory in
            let url = directory.appending(path: "Loose.swift")
            try "alpha\nbeta\n".write(to: url, atomically: true, encoding: .utf8)
            let workspace = WorkspaceDocument()
            defer { workspace.close() }

            LSPDefinitionNavigator.open(url: url, position: CursorPosition(line: 2, column: 4), in: workspace)

            let tab = workspace.editorManager?.activeEditor.selectedTab
            #expect(tab?.file.url.lastPathComponent == "Loose.swift")
            #expect(tab?.cursorPositions.first?.start.line == 2)
            #expect(tab?.cursorPositions.first?.start.column == 4)
        }
    }
}
