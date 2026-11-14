import AppKit
import Testing
@testable import Dreamder

@MainActor
final class OpenResultRecorder {
    private(set) var results: [(document: NSDocument?, alreadyOpen: Bool, error: Error?)] = []

    func record(_ document: NSDocument?, _ alreadyOpen: Bool, _ error: Error?) {
        results.append((document, alreadyOpen, error))
    }
}

@MainActor
final class LastDocumentActionRecorder {
    private(set) var welcomeWindows = 0
    private(set) var quits = 0

    func showWelcome() {
        welcomeWindows += 1
    }

    func quit() {
        quits += 1
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderDocumentControllerCoverageTests {
    @MainActor
    struct LastDocumentScope {
        let controller: DreamderDocumentController
        let recorder = LastDocumentActionRecorder()
        let settings: Dreamder.Settings
        let service = LSPServiceFixture().makeService()
        let remainingDocuments: [NSDocument]

        init(controller: DreamderDocumentController, directory: URL, remainingDocuments: [NSDocument]) {
            self.controller = controller
            self.remainingDocuments = remainingDocuments
            settings = Dreamder.Settings(baseURL: directory)
        }

        func remove(_ document: NSDocument) {
            let remaining = remainingDocuments
            controller.finishRemoval(
                of: document,
                context: DocumentRemovalContext(
                    lspService: service,
                    openDocuments: { remaining },
                    settings: settings,
                    showWelcomeWindow: { [recorder] in recorder.showWelcome() },
                    quitApplication: { [recorder] in recorder.quit() }
                )
            )
        }
    }

    func sharedController() throws -> DreamderDocumentController {
        try #require(DreamderDocumentController.shared as? DreamderDocumentController)
    }

    func openFileNames(in workspace: WorkspaceDocument) -> [String] {
        let files = workspace.editorManager?.editorLayout.gatherOpenFiles() ?? []
        return files.map(\.name).sorted()
    }

    @Test
    func recordingARecentProjectStoresFilesAndFoldersMostRecentFirst() throws {
        try withTempDir { directory in
            let (defaults, suiteName) = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
            let controller = try sharedController()
            let manager = RecentProjectsManager(defaults: defaults)
            let folder = directory.appending(path: "Project", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = directory.appending(path: "Loose.txt")
            try "text\n".write(to: file, atomically: true, encoding: .utf8)

            controller.recordRecentProject(at: folder, in: manager)
            controller.recordRecentProject(at: file, in: manager)

            #expect(manager.recentProjects.map(\.isDirectory) == [false, true])
            #expect(manager.recentProjects.map(\.displayName) == ["Loose.txt", "Project"])
        }
    }

    @Test
    func notingARecentProjectFollowsTheRecordingSwitch() throws {
        try withTempDir { directory in
            let (defaults, suiteName) = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
            let controller = try sharedController()
            let manager = RecentProjectsManager(defaults: defaults)

            controller.noteRecentProject(at: directory, recording: false, in: manager)
            #expect(manager.recentProjects.isEmpty)

            controller.noteRecentProject(at: directory, recording: true, in: manager)
            #expect(manager.recentProjects.count == 1)
        }
    }

    @Test
    func headlessModeSkipsTheSystemRecentDocumentsList() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let file = directory.appending(path: "Recent.txt")
            try "text\n".write(to: file, atomically: true, encoding: .utf8)
            let document = NSDocument()
            document.fileURL = file

            controller.noteNewRecentDocument(document)
            controller.noteNewRecentDocumentURL(file)

            #expect(!controller.recordsRecentDocuments)
            #expect(!controller.recentDocumentURLs.contains(file))
        }
    }

    @Test
    func openingAFileOutsideEveryWorkspaceCreatesADocumentAndReportsIt() async throws {
        try await withTempDir { directory in
            let file = directory.appending(path: "Loose.txt")
            try "loose\n".write(to: file, atomically: true, encoding: .utf8)
            let controller = try sharedController()
            let recorder = OpenResultRecorder()

            controller.openDocument(withContentsOf: file, display: false) { document, alreadyOpen, error in
                recorder.record(document, alreadyOpen, error)
            }
            try await eventually(timeout: .seconds(30)) { !recorder.results.isEmpty }

            let result = try #require(recorder.results.first)
            let document = try #require(result.document)
            defer { document.close() }
            #expect(recorder.results.count == 1)
            #expect(result.error == nil)
            #expect(!result.alreadyOpen)
            #expect(document.fileURL?.lastPathComponent == "Loose.txt")
            #expect(controller.documents.contains { $0 === document })
        }
    }

    @Test
    func openingAMissingFileReportsTheErrorWithoutADocument() async throws {
        try await withTempDir { directory in
            let missing = directory.appending(path: "Missing.txt")
            let controller = try sharedController()
            let recorder = OpenResultRecorder()

            controller.openDocument(withContentsOf: missing, display: false) { document, alreadyOpen, error in
                recorder.record(document, alreadyOpen, error)
            }
            try await eventually(timeout: .seconds(30)) { !recorder.results.isEmpty }

            let result = try #require(recorder.results.first)
            #expect(result.document == nil)
            #expect(result.error != nil)
        }
    }

    @Test
    func theOpenActionOpensTheChosenFileInTheWorkspaceThatContainsIt() throws {
        try withTempDir { directory in
            let file = directory.appending(path: "Chosen.txt")
            try "chosen\n".write(to: file, atomically: true, encoding: .utf8)
            let workspace = try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
            defer { workspace.close() }
            let controller = try sharedController()
            controller.addDocument(workspace)

            controller.openDocument(panels: FakeFilePanels(files: [file]))

            #expect(openFileNames(in: workspace) == ["Chosen.txt"])
        }
    }

    @Test
    func closingTheLastDocumentShowsTheWelcomeWindowWhenConfigured() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let scope = LastDocumentScope(controller: controller, directory: directory, remainingDocuments: [])
            scope.settings.preferences.general.reopenWindowAfterClose = .showWelcomeWindow

            scope.remove(NSDocument())

            #expect(scope.recorder.welcomeWindows == 1)
            #expect(scope.recorder.quits == 0)
        }
    }

    @Test
    func theDefaultWelcomeActionOpensTheWelcomeSceneThroughTheInstalledOpener() throws {
        let controller = try sharedController()
        let delegate = AppDelegate()
        var openedScenes: [SceneID] = []
        delegate.installSceneOpener { openedScenes.append($0) }

        withExtendedLifetime(delegate) {
            controller.showWelcomeWindow()
        }

        #expect(openedScenes == [.welcome])
    }

    @Test
    func closingTheLastDocumentQuitsWhenConfigured() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let scope = LastDocumentScope(controller: controller, directory: directory, remainingDocuments: [])
            scope.settings.preferences.general.reopenWindowAfterClose = .quit

            scope.remove(NSDocument())

            #expect(scope.recorder.quits == 1)
            #expect(scope.recorder.welcomeWindows == 0)
        }
    }

    @Test
    func closingTheLastDocumentDoesNothingByDefault() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let scope = LastDocumentScope(controller: controller, directory: directory, remainingDocuments: [])

            scope.remove(NSDocument())

            #expect(scope.recorder.quits == 0)
            #expect(scope.recorder.welcomeWindows == 0)
        }
    }

    @Test
    func closingADocumentWhileOthersRemainOpenNeverReopensOrQuits() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let scope = LastDocumentScope(
                controller: controller,
                directory: directory,
                remainingDocuments: [NSDocument()]
            )
            scope.settings.preferences.general.reopenWindowAfterClose = .quit

            scope.remove(NSDocument())

            #expect(scope.recorder.quits == 0)
            #expect(scope.recorder.welcomeWindows == 0)
        }
    }

    @Test
    func removingAWorkspaceDocumentForgetsTheDocument() throws {
        try withTempDir { directory in
            let workspace = try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
            defer { workspace.close() }
            let controller = try sharedController()
            controller.addDocument(workspace)

            controller.removeDocument(workspace)

            #expect(!controller.documents.contains { $0 === workspace })
        }
    }
}
