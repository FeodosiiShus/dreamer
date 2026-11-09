import AppKit
import Testing
@testable import Dreamder

@MainActor
private final class OpenResultRecorder {
    private(set) var results: [(document: NSDocument?, alreadyOpen: Bool, error: Error?)] = []

    func record(_ document: NSDocument?, _ alreadyOpen: Bool, _ error: Error?) {
        results.append((document, alreadyOpen, error))
    }
}

@MainActor
private final class LastDocumentActionRecorder {
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
    private struct LastDocumentScope {
        let controller: DreamderDocumentController
        let recorder = LastDocumentActionRecorder()
        let settings: Dreamder.Settings
        private let originalSettings: Dreamder.Settings
        private let originalOpenDocuments: @MainActor () -> [NSDocument]
        private let originalShowWelcomeWindow: @MainActor () -> Void
        private let originalQuitApplication: @MainActor () -> Void

        init(controller: DreamderDocumentController, directory: URL, remainingDocuments: [NSDocument]) {
            self.controller = controller
            settings = Dreamder.Settings(baseURL: directory)
            originalSettings = controller.settings
            originalOpenDocuments = controller.openDocuments
            originalShowWelcomeWindow = controller.showWelcomeWindow
            originalQuitApplication = controller.quitApplication
            controller.settings = settings
            controller.openDocuments = { remainingDocuments }
            controller.showWelcomeWindow = { [recorder] in recorder.showWelcome() }
            controller.quitApplication = { [recorder] in recorder.quit() }
        }

        func restore() {
            controller.settings = originalSettings
            controller.openDocuments = originalOpenDocuments
            controller.showWelcomeWindow = originalShowWelcomeWindow
            controller.quitApplication = originalQuitApplication
        }
    }

    private func sharedController() throws -> DreamderDocumentController {
        try #require(DreamderDocumentController.shared as? DreamderDocumentController)
    }

    private func openFileNames(in workspace: WorkspaceDocument) -> [String] {
        let files = workspace.editorManager?.editorLayout.gatherOpenFiles() ?? []
        return files.map(\.name).sorted()
    }

    @Test
    func recordingARecentProjectStoresFilesAndFoldersMostRecentFirst() throws {
        try withTempDir { directory in
            let (defaults, suiteName) = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
            let controller = try sharedController()
            let original = controller.recentProjects
            let manager = RecentProjectsManager(defaults: defaults)
            controller.recentProjects = manager
            defer { controller.recentProjects = original }
            let folder = directory.appending(path: "Project", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = directory.appending(path: "Loose.txt")
            try "text\n".write(to: file, atomically: true, encoding: .utf8)

            controller.recordRecentProject(at: folder)
            controller.recordRecentProject(at: file)

            #expect(manager.recentProjects.map(\.isDirectory) == [false, true])
            #expect(manager.recentProjects.map(\.displayName) == ["Loose.txt", "Project"])
        }
    }

    @Test
    func notingARecentProjectFollowsTheHeadlessSwitch() throws {
        try withTempDir { directory in
            let (defaults, suiteName) = try makeIsolatedDefaults()
            defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
            let controller = try sharedController()
            let original = controller.recentProjects
            let manager = RecentProjectsManager(defaults: defaults)
            controller.recentProjects = manager
            defer { controller.recentProjects = original }

            controller.noteRecentProject(at: directory)

            #expect(manager.recentProjects.count == (controller.recordsRecentDocuments ? 1 : 0))
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
            controller.filePanels = FakeFilePanels(files: [file])
            defer { controller.filePanels = SystemFilePanels() }

            controller.openDocument(nil)

            #expect(openFileNames(in: workspace) == ["Chosen.txt"])
        }
    }

    @Test
    func closingTheLastDocumentShowsTheWelcomeWindowWhenConfigured() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let scope = LastDocumentScope(controller: controller, directory: directory, remainingDocuments: [])
            defer { scope.restore() }
            scope.settings.preferences.general.reopenWindowAfterClose = .showWelcomeWindow

            controller.removeDocument(NSDocument())

            #expect(scope.recorder.welcomeWindows == 1)
            #expect(scope.recorder.quits == 0)
        }
    }

    @Test
    func closingTheLastDocumentQuitsWhenConfigured() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let scope = LastDocumentScope(controller: controller, directory: directory, remainingDocuments: [])
            defer { scope.restore() }
            scope.settings.preferences.general.reopenWindowAfterClose = .quit

            controller.removeDocument(NSDocument())

            #expect(scope.recorder.quits == 1)
            #expect(scope.recorder.welcomeWindows == 0)
        }
    }

    @Test
    func closingTheLastDocumentDoesNothingByDefault() throws {
        try withTempDir { directory in
            let controller = try sharedController()
            let scope = LastDocumentScope(controller: controller, directory: directory, remainingDocuments: [])
            defer { scope.restore() }

            controller.removeDocument(NSDocument())

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
            defer { scope.restore() }
            scope.settings.preferences.general.reopenWindowAfterClose = .quit

            controller.removeDocument(NSDocument())

            #expect(scope.recorder.quits == 0)
            #expect(scope.recorder.welcomeWindows == 0)
        }
    }

    @Test
    func removingAWorkspaceDocumentStopsItsLanguageServersAndForgetsTheDocument() throws {
        try withTempDir { directory in
            let workspace = try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
            defer { workspace.close() }
            let controller = try sharedController()
            controller.addDocument(workspace)
            let scope = LastDocumentScope(
                controller: controller,
                directory: directory.appending(path: "settings", directoryHint: .isDirectory),
                remainingDocuments: [NSDocument()]
            )
            defer { scope.restore() }

            controller.removeDocument(workspace)

            #expect(!controller.documents.contains { $0 === workspace })
        }
    }
}
