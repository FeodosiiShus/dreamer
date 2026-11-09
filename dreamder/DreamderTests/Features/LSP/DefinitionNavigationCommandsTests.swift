import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class DefinitionUsagesRecorder {
    private(set) var controllers: [DreamderWindowController] = []

    func record(_ controller: DreamderWindowController) {
        controllers.append(controller)
    }
}

@MainActor
private final class DefinitionNavigationHarness {
    static let mainText = "let value = helper()\nlet other = 2\n"
    static let helperText = "func helper() {}\nfunc helper(_ value: Int) {}\n"
    static let typesText = "struct Model {}\nprotocol Shape {}\n"
    static let notesText = "plain notes\n"

    let fixture: LSPServiceFixture
    let files: LSPServiceWorkspace
    let client: LanguageServer<CodeFileDocument>
    let connection: ScriptedServerConnection
    let controller: DreamderWindowController?
    let tab: EditorInstance
    let recorder = DefinitionUsagesRecorder()
    private let service: LSPService

    var workspace: WorkspaceDocument {
        files.workspace
    }

    var mainURL: URL {
        files.directory.appending(path: "Main.swift")
    }

    static func make(
        in directory: URL,
        withWindow: Bool = true,
        openedFile: String = "Main.swift"
    ) async throws -> DefinitionNavigationHarness {
        let files = try LSPServiceWorkspace(
            directory: directory,
            files: ["Main.swift": mainText, "Helper.swift": helperText, "Types.swift": typesText, "Notes.txt": notesText]
        )
        let fixture = LSPServiceFixture()
        let service = fixture.makeService()
        let client = try await service.startServer(for: .swift, workspacePath: files.path)
        let connection = try #require(fixture.created.first?.connection)
        var controller: DreamderWindowController?
        if withWindow {
            files.workspace.makeWindowControllers()
            controller = files.workspace.windowControllers.first as? DreamderWindowController
            controller?.window?.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
            controller?.window?.isReleasedWhenClosed = false
        }
        LSPDefinitionNavigator.open(
            url: files.directory.appending(path: openedFile),
            position: CursorPosition(line: 1, column: 1),
            in: files.workspace
        )
        let tab = try #require(files.workspace.editorManager?.activeEditor.selectedTab)
        return DefinitionNavigationHarness(
            fixture: fixture,
            service: service,
            files: files,
            client: client,
            connection: connection,
            controller: controller,
            tab: tab
        )
    }

    private init(
        fixture: LSPServiceFixture,
        service: LSPService,
        files: LSPServiceWorkspace,
        client: LanguageServer<CodeFileDocument>,
        connection: ScriptedServerConnection,
        controller: DreamderWindowController?,
        tab: EditorInstance
    ) {
        self.fixture = fixture
        self.service = service
        self.files = files
        self.client = client
        self.connection = connection
        self.controller = controller
        self.tab = tab
    }

    func close() {
        for child in controller?.window?.childWindows ?? [] {
            child.close()
        }
        controller?.window?.close()
        files.close()
    }

    func environment(line: Int, character: Int) -> LSPNavigationEnvironment {
        let context = LSPEditorContext(
            workspace: workspace,
            tab: tab,
            fileURL: mainURL,
            documentURI: mainURL.lspURI,
            position: Position(line: line, character: character),
            documentText: Self.mainText,
            lineText: "",
            symbol: "",
            client: client,
            service: service
        )
        return LSPNavigationEnvironment(
            resolveContext: { _ in .ready(context) },
            showUsages: { [recorder] in recorder.record($0) }
        )
    }

    func environment(result: LSPEditorContextResult) -> LSPNavigationEnvironment {
        LSPNavigationEnvironment(
            resolveContext: { _ in result },
            showUsages: { [recorder] in recorder.record($0) }
        )
    }

    func location(_ name: String, _ line: Int, _ start: Int, _ end: Int) -> Location {
        Location(
            uri: files.uri(name),
            range: LSPRange(
                start: Position(line: line, character: start),
                end: Position(line: line, character: end)
            )
        )
    }

    func activeFileName() -> String? {
        workspace.editorManager?.activeEditor.selectedTab?.file.url.lastPathComponent
    }

    func activeCursor() -> CursorPosition? {
        workspace.editorManager?.activeEditor.selectedTab?.cursorPositions.first
    }

    func requests(_ method: ClientRequest.Method) -> Int {
        connection.requestCount(method)
    }

    func panel() -> ShowUsagesPanel? {
        controller?.window?.childWindows?.compactMap { $0 as? ShowUsagesPanel }.first
    }

    func chooserModel() -> DefinitionChooserViewModel? {
        (panel()?.contentView as? NSHostingView<DefinitionChooserView>)?.rootView.model
    }

    func declaration(line: Int, character: Int) async -> LSPNavigationOutcome {
        await LSPNavigationCommands.goToDefinitionAsync(
            workspace: workspace,
            typeDeclaration: false,
            environment: environment(line: line, character: character)
        )
    }

    func typeDeclaration(line: Int, character: Int) async -> LSPNavigationOutcome {
        await LSPNavigationCommands.goToDefinitionAsync(
            workspace: workspace,
            typeDeclaration: true,
            environment: environment(line: line, character: character)
        )
    }

    func implementation(line: Int, character: Int) async -> LSPNavigationOutcome {
        await LSPNavigationCommands.goToImplementationAsync(
            workspace: workspace,
            environment: environment(line: line, character: character)
        )
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct DefinitionNavigationCommandsTests {
    @Test
    func declarationWithOneOtherTargetJumpsAndPlacesTheCaret() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentDefinition, harness.location("Helper.swift", 1, 5, 11))

            let outcome = await harness.declaration(line: 0, character: 13)

            guard case .jumped(let destination) = outcome else {
                Issue.record("expected a jump, got \(outcome)")
                return
            }
            #expect(destination.uri == harness.files.uri("Helper.swift"))
            #expect(harness.activeFileName() == "Helper.swift")
            #expect(harness.activeCursor()?.start.line == 2)
            #expect(harness.activeCursor()?.start.column == 6)
            #expect(harness.recorder.controllers.isEmpty)
            #expect(harness.panel() == nil)
        }
    }

    @Test
    func declarationOnTheDeclarationItselfShowsUsages() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentDefinition, harness.location("Main.swift", 0, 4, 9))

            let outcome = await harness.declaration(line: 0, character: 6)

            #expect(outcome == .usages)
            #expect(harness.recorder.controllers.count == 1)
            #expect(harness.recorder.controllers.first === harness.controller)
            #expect(harness.activeFileName() == "Main.swift")
            #expect(harness.panel() == nil)
        }
    }

    @Test
    func declarationWithoutAnyAnswerShowsUsages() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }

            let outcome = await harness.declaration(line: 1, character: 2)

            #expect(outcome == .usages)
            #expect(harness.recorder.controllers.count == 1)
            #expect(harness.requests(.textDocumentDefinition) == 1)
            #expect(harness.requests(.textDocumentDeclaration) == 1)
        }
    }

    @Test
    func declarationFallsBackToTheDeclarationRequestWhenTheDefinitionIsEmpty() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentDeclaration, harness.location("Types.swift", 0, 7, 12))

            let outcome = await harness.declaration(line: 0, character: 13)

            guard case .jumped = outcome else {
                Issue.record("expected a jump, got \(outcome)")
                return
            }
            #expect(harness.activeFileName() == "Types.swift")
            #expect(harness.requests(.textDocumentDeclaration) == 1)
        }
    }

    @Test
    func declarationWithSeveralTargetsShowsTheChooserSortedByFile() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(
                .textDocumentDefinition,
                [harness.location("Types.swift", 1, 9, 14), harness.location("Helper.swift", 0, 5, 11)]
            )

            let outcome = await harness.declaration(line: 0, character: 13)

            #expect(outcome == .chooser(rowCount: 2))
            let model = try #require(harness.chooserModel())
            #expect(model.title == "Choose Declaration")
            #expect(model.rows.map(\.fileName) == ["Helper.swift", "Types.swift"])
            #expect(model.rows.map(\.lineText) == ["func helper() {}", "protocol Shape {}"])
            #expect(model.rows.map(\.matchRange) == [NSRange(location: 5, length: 6), NSRange(location: 9, length: 5)])
            #expect(harness.activeFileName() == "Main.swift")
        }
    }

    @Test
    func choosingARowJumpsToItAndClosesTheChooser() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(
                .textDocumentDefinition,
                [harness.location("Types.swift", 1, 9, 14), harness.location("Helper.swift", 0, 5, 11)]
            )
            _ = await harness.declaration(line: 0, character: 13)
            let model = try #require(harness.chooserModel())

            model.moveSelection(1)
            model.activate()

            #expect(harness.activeFileName() == "Types.swift")
            #expect(harness.activeCursor()?.start.line == 2)
            #expect(harness.activeCursor()?.start.column == 10)
            #expect(harness.panel() == nil)
        }
    }

    @Test
    func chooserRowsUseOpenTabContentsAndToleratesMissingFiles() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            LSPDefinitionNavigator.open(
                url: directory.appending(path: "Types.swift"),
                position: CursorPosition(line: 1, column: 1),
                in: harness.workspace
            )
            let typesTab = try #require(
                harness.workspace.editorManager?.activeEditor.tabs.first { $0.file.url.lastPathComponent == "Types.swift" }
            )
            let document = try harness.files.document("Types.swift")
            harness.files.setText("Types.swift", "struct Model {}\nprotocol Changed {}\n")
            typesTab.file.fileDocument = document
            try harness.connection.script(
                .textDocumentDefinition,
                [
                    harness.location("Types.swift", 1, 9, 15),
                    harness.location("Ghost.swift", 0, 0, 3),
                    harness.location("Helper.swift", 0, 5, 11)
                ]
            )

            let outcome = await harness.declaration(line: 0, character: 13)

            #expect(outcome == .chooser(rowCount: 3))
            let model = try #require(harness.chooserModel())
            #expect(model.rows.map(\.fileName) == ["Ghost.swift", "Helper.swift", "Types.swift"])
            #expect(model.rows.map(\.lineText) == ["", "func helper() {}", "protocol Changed {}"])
            withExtendedLifetime(document) {}
        }
    }

    @Test
    func typeDeclarationAsksOnlyForTheTypeDefinitionAndJumps() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentDefinition, harness.location("Helper.swift", 0, 5, 11))
            try harness.connection.script(.textDocumentTypeDefinition, harness.location("Types.swift", 1, 9, 14))

            let outcome = await harness.typeDeclaration(line: 0, character: 6)

            guard case .jumped = outcome else {
                Issue.record("expected a jump, got \(outcome)")
                return
            }
            #expect(harness.activeFileName() == "Types.swift")
            #expect(harness.requests(.textDocumentDefinition) == 0)
            #expect(harness.requests(.textDocumentDeclaration) == 0)
            #expect(harness.requests(.textDocumentTypeDefinition) == 1)
        }
    }

    @Test
    func typeDeclarationJumpsEvenWhenTheTargetIsTheCaretPlace() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentTypeDefinition, harness.location("Main.swift", 0, 4, 9))

            let outcome = await harness.typeDeclaration(line: 0, character: 6)

            guard case .jumped = outcome else {
                Issue.record("expected a jump, got \(outcome)")
                return
            }
            #expect(harness.activeFileName() == "Main.swift")
            #expect(harness.activeCursor()?.start.line == 1)
            #expect(harness.activeCursor()?.start.column == 5)
            #expect(harness.recorder.controllers.isEmpty)
        }
    }

    @Test
    func typeDeclarationWithSeveralTargetsShowsTheTypeChooser() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(
                .textDocumentTypeDefinition,
                [harness.location("Types.swift", 0, 7, 12), harness.location("Types.swift", 1, 9, 14)]
            )

            let outcome = await harness.typeDeclaration(line: 0, character: 6)

            #expect(outcome == .chooser(rowCount: 2))
            #expect(harness.chooserModel()?.title == "Choose Type Declaration")
        }
    }

    @Test
    func typeDeclarationWithoutAnswerShowsAShortMessage() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentDefinition, harness.location("Helper.swift", 0, 5, 11))

            let outcome = await harness.typeDeclaration(line: 0, character: 6)

            #expect(outcome == .message("No type declaration found"))
            let model = try #require(harness.chooserModel())
            #expect(model.isMessage)
            #expect(model.message == "No type declaration found")
            #expect(model.title == "Go to Type Declaration")
            #expect(harness.activeFileName() == "Main.swift")
            #expect(harness.recorder.controllers.isEmpty)
        }
    }

    @Test
    func implementationWithOneTargetJumpsEvenWhenItIsTheCaretPlace() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(.textDocumentImplementation, harness.location("Main.swift", 0, 4, 9))

            let outcome = await harness.implementation(line: 0, character: 6)

            guard case .jumped = outcome else {
                Issue.record("expected a jump, got \(outcome)")
                return
            }
            #expect(harness.activeFileName() == "Main.swift")
            #expect(harness.activeCursor()?.start.column == 5)
            #expect(harness.requests(.textDocumentImplementation) == 1)
            #expect(harness.requests(.textDocumentDefinition) == 0)
        }
    }

    @Test
    func implementationWithSeveralTargetsShowsTheImplementationChooser() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            try harness.connection.script(
                .textDocumentImplementation,
                [harness.location("Helper.swift", 0, 5, 11), harness.location("Helper.swift", 1, 5, 11)]
            )

            let outcome = await harness.implementation(line: 0, character: 6)

            #expect(outcome == .chooser(rowCount: 2))
            let model = try #require(harness.chooserModel())
            #expect(model.title == "Choose Implementation")
            #expect(model.rows.map(\.displayLine) == [1, 2])
        }
    }

    @Test
    func implementationWithoutAnswerShowsAShortMessage() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }

            let outcome = await harness.implementation(line: 0, character: 6)

            #expect(outcome == .message("No implementations found"))
            let model = try #require(harness.chooserModel())
            #expect(model.message == "No implementations found")
            #expect(model.title == "Go to Implementation")
        }
    }

    @Test
    func aMissingServerShowsAMessageForEveryKind() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            let environment = harness.environment(result: .missingServer)

            let declaration = await LSPNavigationCommands.goToDefinitionAsync(
                workspace: harness.workspace,
                typeDeclaration: false,
                environment: environment
            )
            #expect(declaration == .missingServer)
            #expect(harness.chooserModel()?.message == "Go to Declaration needs a language server for this file")

            let type = await LSPNavigationCommands.goToDefinitionAsync(
                workspace: harness.workspace,
                typeDeclaration: true,
                environment: environment
            )
            #expect(type == .missingServer)
            #expect(harness.chooserModel()?.message == "Go to Type Declaration needs a language server for this file")

            let implementation = await LSPNavigationCommands.goToImplementationAsync(
                workspace: harness.workspace,
                environment: environment
            )
            #expect(implementation == .missingServer)
            #expect(harness.chooserModel()?.message == "Go to Implementation needs a language server for this file")
            #expect(harness.controller?.window?.childWindows?.count == 1)
        }
    }

    @Test
    func anUnavailableEditorDoesNothing() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory)
            defer { harness.close() }
            let environment = harness.environment(result: .unavailable)

            let declaration = await LSPNavigationCommands.goToDefinitionAsync(
                workspace: harness.workspace,
                typeDeclaration: false,
                environment: environment
            )
            let implementation = await LSPNavigationCommands.goToImplementationAsync(
                workspace: harness.workspace,
                environment: environment
            )

            #expect(declaration == .unavailable)
            #expect(implementation == .unavailable)
            #expect(harness.panel() == nil)
            #expect(harness.recorder.controllers.isEmpty)
        }
    }

    @Test
    func outcomesDoNotNeedAWindowController() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory, withWindow: false)
            defer { harness.close() }
            try harness.connection.script(
                .textDocumentImplementation,
                [harness.location("Helper.swift", 0, 5, 11), harness.location("Types.swift", 0, 7, 12)]
            )

            let usages = await harness.declaration(line: 1, character: 2)
            let chooser = await harness.implementation(line: 0, character: 6)
            let message = await harness.typeDeclaration(line: 0, character: 6)
            let missing = await LSPNavigationCommands.goToImplementationAsync(
                workspace: harness.workspace,
                environment: harness.environment(result: .missingServer)
            )

            #expect(usages == .usages)
            #expect(chooser == .chooser(rowCount: 2))
            #expect(message == .message("No type declaration found"))
            #expect(missing == .missingServer)
            #expect(harness.recorder.controllers.isEmpty)
            #expect(harness.workspace.windowControllers.isEmpty)
        }
    }

    @Test
    func liveEnvironmentResolvesTheEditorAndShowsUsages() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory, openedFile: "Notes.txt")
            defer { harness.close() }
            let live = LSPNavigationEnvironment.live

            guard case .unavailable = live.resolveContext(nil) else {
                Issue.record("expected unavailable without a workspace")
                return
            }
            guard case .missingServer = live.resolveContext(harness.workspace) else {
                Issue.record("expected a missing server for a file no server has open")
                return
            }
            let controller = try #require(harness.controller)

            live.showUsages(controller)

            #expect(harness.panel() != nil)
        }
    }

    @Test
    func entryPointsRunTheLiveEnvironmentInAStoredTask() async throws {
        try await withTempDir { directory in
            let harness = try await DefinitionNavigationHarness.make(in: directory, openedFile: "Notes.txt")
            defer { harness.close() }

            LSPNavigationCommands.goToDefinition(workspace: nil, typeDeclaration: false)
            let first = try #require(LSPNavigationCommands.pendingNavigation)
            await first.value
            LSPNavigationCommands.goToDefinition(workspace: nil, typeDeclaration: true)
            await LSPNavigationCommands.pendingNavigation?.value
            LSPNavigationCommands.goToImplementation(workspace: nil)
            await LSPNavigationCommands.pendingNavigation?.value
            #expect(harness.panel() == nil)

            LSPNavigationCommands.goToDefinition(workspace: harness.workspace, typeDeclaration: false)
            await LSPNavigationCommands.pendingNavigation?.value
            #expect(harness.chooserModel()?.message == "Go to Declaration needs a language server for this file")

            LSPNavigationCommands.goToImplementation(workspace: harness.workspace)
            await LSPNavigationCommands.pendingNavigation?.value
            #expect(harness.chooserModel()?.message == "Go to Implementation needs a language server for this file")
        }
    }

    @Test
    func asyncEntryPointsDefaultToTheLiveEnvironment() async throws {
        let declaration = await LSPNavigationCommands.goToDefinitionAsync(workspace: nil, typeDeclaration: false)
        let implementation = await LSPNavigationCommands.goToImplementationAsync(workspace: nil)

        #expect(declaration == .unavailable)
        #expect(implementation == .unavailable)
    }
}
