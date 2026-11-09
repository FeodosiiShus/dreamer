import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct AppDelegateTests {
    private struct OpenFailure: LocalizedError {
        var errorDescription: String? { "Cannot open AppDelegateTests fixture" }
    }

    @MainActor
    private final class StubDocumentController: AppDocumentControlling {
        var stubbedDocuments: [NSDocument] = []
        var documentToReturn: NSDocument?
        var errorToReturn: (any Error)?
        var closeAllCompletes = true
        private(set) var openedURLs: [URL] = []
        private(set) var openPanelCalls = 0
        private(set) var newDocumentCalls = 0
        private(set) var closeAllCalls = 0

        var documents: [NSDocument] { stubbedDocuments }

        func openDocument(
            withContentsOf url: URL,
            display displayDocument: Bool,
            completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
        ) {
            openedURLs.append(url)
            completionHandler(documentToReturn, false, errorToReturn)
        }

        func openDocument(_ sender: Any?) {
            openPanelCalls += 1
        }

        func newDocument(_ sender: Any?) {
            newDocumentCalls += 1
        }

        func closeAllDocuments(
            withDelegate delegate: Any?,
            didCloseAllSelector: Selector?,
            contextInfo: UnsafeMutableRawPointer?
        ) {
            closeAllCalls += 1
            (delegate as? AppDelegate)?.documentController(
                NSDocumentController.shared,
                didCloseAll: closeAllCompletes,
                contextInfo: ()
            )
        }
    }

    @MainActor
    private final class EditedDocument: NSDocument {
        override var isDocumentEdited: Bool { true }
    }

    @MainActor
    private final class RecordingTaskManager: TaskManager {
        private(set) var stopAllCalls = 0

        override func stopAllTasks() {
            stopAllCalls += 1
        }
    }

    @MainActor
    private final class TerminationRecorder {
        private(set) var replies: [Bool] = []
        private(set) var notifications: [String] = []
        private var observer: NSObjectProtocol?

        init() {
            observer = NotificationCenter.default.addObserver(
                forName: .taskNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let identifier = notification.userInfo?["id"] as? String ?? ""
                let action = notification.userInfo?["action"] as? String ?? ""
                guard identifier.hasPrefix("appdelegate.") else { return }
                MainActor.assumeIsolated {
                    self?.notifications.append("\(identifier):\(action)")
                }
            }
        }

        isolated deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func record(reply: Bool) {
            replies.append(reply)
        }
    }

    @MainActor
    private struct TerminationHarness {
        let delegate: AppDelegate
        let controller: StubDocumentController
        let recorder: TerminationRecorder
        let defaults: UserDefaults
        let suiteName: String

        init() throws {
            let isolated = try makeIsolatedDefaults()
            let recorder = TerminationRecorder()
            let delegate = AppDelegate()
            let controller = StubDocumentController()
            delegate.documentsController = controller
            delegate.defaults = isolated.defaults
            delegate.languageServiceOverride = LSPService()
            delegate.replyToTerminate = { recorder.record(reply: $0) }
            self.delegate = delegate
            self.controller = controller
            self.recorder = recorder
            self.defaults = isolated.defaults
            self.suiteName = isolated.suiteName
        }

        func tearDown() {
            removeIsolatedDefaults(defaults, suiteName: suiteName)
        }
    }

    private func makeWorkspace(at directory: URL) throws -> WorkspaceDocument {
        try WorkspaceDocument(for: directory, withContentsOf: directory, ofType: "")
    }

    private func makeCodeFile(in directory: URL, name: String = "Opened.txt") throws -> CodeFileDocument {
        let url = directory.appending(path: name)
        try "alpha\nbravo\n".write(to: url, atomically: true, encoding: .utf8)
        return try CodeFileDocument(for: url, withContentsOf: url, ofType: "public.plain-text")
    }

    private func withReopenBehavior(
        _ behavior: SettingsData.ReopenBehavior,
        _ body: (AppDelegate) throws -> Void
    ) throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            settings.preferences.general.reopenBehavior = behavior
            let delegate = AppDelegate()
            delegate.settings = settings
            try body(delegate)
        }
    }

    @Test(arguments: [
        ([String](), [String]()),
        (["Dreamder"], []),
        (["Dreamder", "--open"], []),
        (["Dreamder", "--open", "/tmp/a.swift"], ["/tmp/a.swift"]),
        (["--open", "/tmp/a", "-x", "--open", "/tmp/b"], ["/tmp/a", "/tmp/b"]),
        (["/tmp/not-a-flag", "--other", "/tmp/c"], [])
    ])
    func openArgumentsYieldTheValueFollowingEachOpenFlag(arguments: [String], expected: [String]) {
        #expect(AppDelegate.openURLs(fromArguments: arguments).map(\.path) == expected)
    }

    @Test
    func finderExtensionRequestOpensEveryListedFileAndClearsTheRequest() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        isolated.defaults.set("/tmp/Alpha.swift;/tmp/with space/Beta.txt;;/tmp/Gamma.md;", forKey: "openInCEFiles")
        let delegate = AppDelegate()
        var opened: [String] = []
        delegate.reopenDocument = { opened.append($0.path) }

        delegate.openFilesRequestedByFinderExtension(defaults: isolated.defaults)

        #expect(opened == ["/tmp/Alpha.swift", "/tmp/with space/Beta.txt", "/tmp/Gamma.md"])
        #expect(isolated.defaults.object(forKey: "openInCEFiles") == nil)
    }

    @Test
    func finderExtensionWithoutARequestOpensNothingAndEnablesOpenInDreamder() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        let delegate = AppDelegate()
        var opened: [URL] = []
        delegate.reopenDocument = { opened.append($0) }

        delegate.openFilesRequestedByFinderExtension(defaults: isolated.defaults)

        #expect(opened.isEmpty)
        #expect(isolated.defaults.object(forKey: "enableOpenInCE") as? Bool == true)
    }

    @Test
    func finderExtensionRequestWithOnlySeparatorsOpensNothingButIsStillCleared() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        isolated.defaults.set(";;;", forKey: "openInCEFiles")
        let delegate = AppDelegate()
        var opened: [URL] = []
        delegate.reopenDocument = { opened.append($0) }

        delegate.openFilesRequestedByFinderExtension(defaults: isolated.defaults)

        #expect(opened.isEmpty)
        #expect(isolated.defaults.object(forKey: "openInCEFiles") == nil)
    }

    @Test(arguments: [
        ("", nil as Int?, nil as Int?),
        (":12", 12, 1),
        (":12:7", 12, 7),
        (":12:0", 12, 1),
        (":12:-3", 12, 1),
        (":12:x", 12, 1),
        (":0", nil, nil),
        (":-4", nil, nil),
        (":abc", nil, nil)
    ])
    func schemeURLCarriesTheCaretPositionAfterThePath(suffix: String, line: Int?, column: Int?) throws {
        try withTempDir { directory in
            let codeFile = try makeCodeFile(in: directory)
            let path = try #require(codeFile.fileURL).path(percentEncoded: false)
            let controller = StubDocumentController()
            controller.documentToReturn = codeFile
            let delegate = AppDelegate()
            delegate.documentsController = controller
            let url = try #require(URL(string: "dreamder://file\(path)\(suffix)"))

            delegate.application(NSApplication.shared, open: [url])

            #expect(controller.openedURLs.map { $0.path(percentEncoded: false) } == [path])
            let position = codeFile.openOptions?.cursorPositions.first
            #expect(position?.start.line == line)
            #expect(position?.start.column == column)
        }
    }

    @Test
    func plainFileURLOpensTheFileWithoutAnyCaretPosition() throws {
        try withTempDir { directory in
            let codeFile = try makeCodeFile(in: directory)
            let fileURL = try #require(codeFile.fileURL)
            let controller = StubDocumentController()
            controller.documentToReturn = codeFile
            let delegate = AppDelegate()
            delegate.documentsController = controller

            delegate.application(NSApplication.shared, open: [fileURL])

            #expect(controller.openedURLs.map(\.path) == [fileURL.path])
            #expect(codeFile.openOptions == nil)
        }
    }

    @Test
    func everyURLIsOpenedInOrder() throws {
        let controller = StubDocumentController()
        let delegate = AppDelegate()
        delegate.documentsController = controller
        let first = try #require(URL(string: "dreamder://file/tmp/First.swift:3"))
        let second = try #require(URL(string: "dreamder://file/tmp/Second.swift"))
        let third = URL(fileURLWithPath: "/tmp/Third.swift")

        delegate.application(NSApplication.shared, open: [first, second, third])

        #expect(controller.openedURLs.map(\.path) == ["/tmp/First.swift", "/tmp/Second.swift", "/tmp/Third.swift"])
    }

    @Test
    func aCaretPositionIsIgnoredForDocumentsThatAreNotCodeFiles() throws {
        let controller = StubDocumentController()
        controller.documentToReturn = EditedDocument()
        let delegate = AppDelegate()
        delegate.documentsController = controller
        let url = try #require(URL(string: "dreamder://file/tmp/Workspace:5:2"))

        delegate.application(NSApplication.shared, open: [url])

        #expect(controller.openedURLs.map(\.path) == ["/tmp/Workspace"])
    }

    @Test
    func openFailureIsReportedInAnAlertAndLeavesNoCaretPosition() throws {
        try withTempDir { directory in
            let codeFile = try makeCodeFile(in: directory)
            let controller = StubDocumentController()
            controller.documentToReturn = codeFile
            controller.errorToReturn = OpenFailure()
            let delegate = AppDelegate()
            delegate.documentsController = controller
            let url = try #require(URL(string: "dreamder://file/tmp/Broken.swift:9:1"))

            delegate.application(NSApplication.shared, open: [url])

            #expect(DreamderHeadless.suppressedModals.contains("Cannot open AppDelegateTests fixture"))
            #expect(codeFile.openOptions == nil)
        }
    }

    @Test
    func reopeningWithNewDocumentBehaviorCreatesANewDocument() throws {
        try withReopenBehavior(.newDocument) { delegate in
            let controller = StubDocumentController()
            delegate.documentsController = controller

            delegate.handleOpen()

            #expect(controller.newDocumentCalls == 1)
            #expect(controller.openPanelCalls == 0)
        }
    }

    @Test
    func reopeningWithOpenPanelBehaviorShowsTheOpenPanel() throws {
        try withReopenBehavior(.openPanel) { delegate in
            let controller = StubDocumentController()
            delegate.documentsController = controller

            delegate.handleOpen()

            #expect(controller.openPanelCalls == 1)
            #expect(controller.newDocumentCalls == 0)
        }
    }

    @Test
    func dockReopenWithoutVisibleWindowsRunsTheReopenBehaviorAndSuppressesTheDefault() throws {
        try withReopenBehavior(.newDocument) { delegate in
            let controller = StubDocumentController()
            delegate.documentsController = controller

            let handledByAppKit = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)

            #expect(handledByAppKit == false)
            #expect(controller.newDocumentCalls == 1)
        }
    }

    @Test
    func dockReopenWithVisibleWindowsNeverRunsTheReopenBehavior() throws {
        try withReopenBehavior(.newDocument) { delegate in
            let controller = StubDocumentController()
            delegate.documentsController = controller

            let handledByAppKit = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)

            #expect(handledByAppKit == false)
            #expect(controller.newDocumentCalls == 0)
            #expect(controller.openPanelCalls == 0)
        }
    }

    @Test
    func applicationPolicyHooksKeepTheAppAliveAndSkipUntitledDocuments() {
        let delegate = AppDelegate()

        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false)
        #expect(delegate.applicationShouldOpenUntitledFile(NSApplication.shared) == false)
        #expect(delegate.applicationSupportsSecureRestorableState(NSApplication.shared))
    }

    @Test
    func terminationRecordsOnlyOpenWorkspacesForRecovery() async throws {
        try await withTempDir { directory in
            let first = directory.appending(path: "First", directoryHint: .isDirectory)
            let second = directory.appending(path: "Second", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            let harness = try TerminationHarness()
            defer { harness.tearDown() }
            let firstWorkspace = try makeWorkspace(at: first)
            let secondWorkspace = try makeWorkspace(at: second)
            defer {
                firstWorkspace.close()
                secondWorkspace.close()
            }
            let codeFile = try makeCodeFile(in: directory)
            harness.controller.stubbedDocuments = [firstWorkspace, codeFile, WorkspaceDocument(), secondWorkspace]

            let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

            #expect(reply == .terminateLater)
            #expect(harness.defaults.stringArray(forKey: AppDelegate.recoverWorkspacesKey) == [first.path, second.path])
            try await eventually { harness.recorder.replies == [true] }
        }
    }

    @Test
    func terminationWithNoDocumentsRecordsAnEmptyRecoveryList() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        harness.defaults.set(["/stale/project"], forKey: AppDelegate.recoverWorkspacesKey)

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(harness.defaults.stringArray(forKey: AppDelegate.recoverWorkspacesKey) == [])
        try await eventually { harness.recorder.replies == [true] }
    }

    @Test
    func cleanTerminationStopsTasksThenRepliesOnceAfterLanguageServersStopped() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let workspace = WorkspaceDocument()
        let manager = RecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        let activeTask = CETask(target: "build")
        manager.activeTasks[activeTask.id] = CEActiveTask(task: activeTask)
        workspace.taskManager = manager
        harness.controller.stubbedDocuments = [workspace]

        let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateLater)
        #expect(harness.controller.closeAllCalls == 0)
        #expect(manager.stopAllCalls == 1)
        try await eventually { harness.recorder.replies == [true] && harness.recorder.notifications.count >= 3 }
        #expect(harness.recorder.replies == [true])
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:create",
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:delete"
        ])
    }

    @Test
    func cleanTerminationWithIdleTasksDoesNotAnnounceTaskTermination() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let workspace = WorkspaceDocument()
        let manager = RecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        workspace.taskManager = manager
        harness.controller.stubbedDocuments = [workspace]

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually { harness.recorder.replies == [true] && harness.recorder.notifications.count >= 2 }
        #expect(manager.stopAllCalls == 1)
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:delete"
        ])
    }

    @Test
    func terminationWithUnsavedDocumentsClosesThemFirstAndThenRepliesOnce() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        harness.controller.stubbedDocuments = [EditedDocument()]

        let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(reply == .terminateLater)
        #expect(harness.controller.closeAllCalls == 1)
        try await eventually { harness.recorder.replies == [true] }
    }

    @Test
    func cancellingTheSavePromptKeepsTheApplicationRunning() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let workspace = WorkspaceDocument()
        let manager = RecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        workspace.taskManager = manager
        harness.controller.closeAllCompletes = false
        harness.controller.stubbedDocuments = [workspace, EditedDocument()]

        let reply = harness.delegate.applicationShouldTerminate(NSApplication.shared)
        try await Task.sleep(for: .milliseconds(300))

        #expect(reply == .terminateLater)
        #expect(harness.controller.closeAllCalls == 1)
        #expect(manager.stopAllCalls == 0)
        #expect(harness.recorder.replies.isEmpty)
        #expect(harness.recorder.notifications.isEmpty)
    }

    @Test
    func terminationAnnouncesAndStopsRunningLanguageServers() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        let service = try #require(harness.delegate.languageServiceOverride)
        let key = LSPService.ClientKey(.swift, "/app-delegate-tests/\(UUID().uuidString)")
        service.languageClients[key] = LanguageServicesFixture.makeClient(key, pid: Int32.max)

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually { harness.recorder.replies == [true] && harness.recorder.notifications.count >= 3 }
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:create",
            "appdelegate.terminate_language_servers:delete"
        ])
        #expect(service.languageClients.isEmpty)
    }

    private final class StuckShutdownConnection: ServerConnection, Sendable {
        let eventSequence: EventSequence

        init() {
            let (sequence, _) = EventSequence.makeStream()
            eventSequence = sequence
        }

        func sendNotification(_ notif: ClientNotification) async throws {}

        func sendRequest<Response: Decodable & Sendable>(_ request: ClientRequest) async throws -> Response {
            if request.method == .shutdown {
                try await Task.sleep(for: .seconds(3600))
                throw CancellationError()
            }
            let data = try JSONEncoder().encode(InitializationResponse(capabilities: .init(), serverInfo: nil))
            return try JSONDecoder().decode(Response.self, from: data)
        }
    }

    @Test
    func languageServersThatNeverAnswerShutdownAreKilledWhenTheTimeoutExpires() async throws {
        let harness = try TerminationHarness()
        defer { harness.tearDown() }
        harness.delegate.languageServerShutdownTimeout = .milliseconds(100)
        let service = try #require(harness.delegate.languageServiceOverride)
        let key = LSPService.ClientKey(.swift, "/app-delegate-tests/stuck/\(UUID().uuidString)")
        let instance = InitializingServer(
            server: StuckShutdownConnection(),
            initializeParamsProvider: LSPService.LanguageServerType.getInitParams(workspacePath: key.workspacePath)
        )
        _ = try await instance.initializeIfNeeded()
        service.languageClients[key] = LSPService.LanguageServerType(
            languageId: key.languageId,
            binary: LanguageServerBinary(execPath: LanguageServicesFixture.missingBinary, args: [], env: nil),
            lspInstance: instance,
            lspPid: Int32.max,
            serverCapabilities: ServerCapabilities(),
            rootPath: URL(fileURLWithPath: key.workspacePath),
            logContainer: LanguageServerLogContainer(languageID: key.languageId.rawValue)
        )

        _ = harness.delegate.applicationShouldTerminate(NSApplication.shared)

        try await eventually(timeout: .seconds(30)) {
            harness.recorder.replies == [true] && harness.recorder.notifications.count >= 3
        }
        #expect(harness.recorder.notifications == [
            "appdelegate.terminate_tasks:delete",
            "appdelegate.terminate_language_servers:create",
            "appdelegate.terminate_language_servers:delete"
        ])
    }

    @MainActor
    private final class StubWindow: NSWindow {
        var stubbedMiniaturized = false
        var stubbedVisible = false
        private(set) var deminiaturizeCalls = 0
        private(set) var focusCalls = 0

        override var isMiniaturized: Bool { stubbedMiniaturized }
        override var isVisible: Bool { stubbedVisible }

        override func deminiaturize(_ sender: Any?) {
            deminiaturizeCalls += 1
        }

        override func makeKeyAndOrderFront(_ sender: Any?) {
            focusCalls += 1
        }
    }

    private func makeStubWindow(
        miniaturized: Bool = false,
        visible: Bool = false,
        scene: SceneID? = nil
    ) -> StubWindow {
        let window = StubWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.stubbedMiniaturized = miniaturized
        window.stubbedVisible = visible
        window.identifier = scene.map { NSUserInterfaceItemIdentifier($0.rawValue) }
        return window
    }

    @Test(arguments: [
        (
            ["Dreamder", "--open", "/tmp/a.swift", "--open", "/tmp/b.swift"],
            false,
            ["/tmp/a.swift", "/tmp/b.swift"],
            0
        ),
        (["Dreamder", "--open", "/tmp/a.swift"], true, ["/tmp/a.swift"], 0),
        ([String](), false, [String](), 1),
        (["Dreamder"], true, [String](), 0)
    ])
    func launchOpensTheRequestedURLsOrFallsBackToTheReopenBehavior(
        arguments: [String],
        windowsWereReopened: Bool,
        expectedOpened: [String],
        expectedNewDocuments: Int
    ) throws {
        try withReopenBehavior(.newDocument) { delegate in
            let controller = StubDocumentController()
            delegate.documentsController = controller
            var opened: [String] = []
            delegate.reopenDocument = { opened.append($0.path) }

            delegate.openInitialDocuments(arguments: arguments, windowsWereReopened: windowsWereReopened)

            #expect(opened == expectedOpened)
            #expect(controller.newDocumentCalls == expectedNewDocuments)
        }
    }

    @Test
    func dockReopenRestoresAMiniaturizedWindowWhenNothingElseIsVisible() {
        let miniaturized = makeStubWindow(miniaturized: true)
        let hidden = makeStubWindow()
        defer {
            miniaturized.close()
            hidden.close()
        }

        AppDelegate().restoreMiniaturizedWindow(in: [hidden, miniaturized], sender: nil)

        #expect(miniaturized.deminiaturizeCalls == 1)
        #expect(hidden.deminiaturizeCalls == 0)
    }

    @Test
    func dockReopenLeavesMiniaturizedWindowsAloneWhileAnotherWindowIsVisible() {
        let miniaturized = makeStubWindow(miniaturized: true)
        let visible = makeStubWindow(visible: true)
        defer {
            miniaturized.close()
            visible.close()
        }

        AppDelegate().restoreMiniaturizedWindow(in: [miniaturized, visible], sender: nil)

        #expect(miniaturized.deminiaturizeCalls == 0)
        #expect(visible.deminiaturizeCalls == 0)
    }

    @Test
    func dockReopenWithoutMiniaturizedWindowsRestoresNothing() {
        let hidden = makeStubWindow()
        defer { hidden.close() }

        AppDelegate().restoreMiniaturizedWindow(in: [hidden], sender: nil)

        #expect(hidden.deminiaturizeCalls == 0)
    }

    @Test
    func welcomeReopenFocusesTheExistingWelcomeWindow() throws {
        try withReopenBehavior(.welcome) { delegate in
            let welcome = makeStubWindow(scene: .welcome)
            let about = makeStubWindow(scene: .about)
            defer {
                welcome.close()
                about.close()
            }
            var openedScenes: [SceneID] = []
            delegate.sceneOpenerOverride = { openedScenes.append($0) }
            delegate.applicationWindows = { [about, welcome] }

            delegate.handleOpen()

            #expect(welcome.focusCalls == 1)
            #expect(about.focusCalls == 0)
            #expect(openedScenes.isEmpty)
        }
    }

    @Test
    func welcomeReopenOpensTheWelcomeSceneWhenNoWelcomeWindowExists() throws {
        try withReopenBehavior(.welcome) { delegate in
            let about = makeStubWindow(scene: .about)
            defer { about.close() }
            var openedScenes: [SceneID] = []
            delegate.sceneOpenerOverride = { openedScenes.append($0) }
            delegate.applicationWindows = { [about] }

            delegate.handleOpen()

            #expect(openedScenes == [.welcome])
            #expect(about.focusCalls == 0)
        }
    }

    @Test
    func windowActionsOpenTheirScenes() {
        let delegate = AppDelegate()
        var openedScenes: [SceneID] = []
        delegate.sceneOpenerOverride = { openedScenes.append($0) }

        delegate.openWelcome(delegate)
        delegate.openAbout(delegate)
        delegate.showDreamderSettings(nil)

        #expect(openedScenes == [.welcome, .about, .settings])
    }

    @Test
    func openingASceneWithoutAnOverrideDelegatesToTheEnvironmentAction() {
        let delegate = AppDelegate()

        delegate.openScene(.about)

        #expect(delegate.sceneOpenerOverride == nil)
    }

    @Test
    func pollingOpensEveryFinderExtensionRequestAsItArrives() async throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        let defaults = isolated.defaults
        let delegate = AppDelegate()
        var opened: [String] = []
        delegate.reopenDocument = { opened.append($0.path) }
        delegate.finderExtensionDefaults = { defaults }
        delegate.finderExtensionPollInterval = .milliseconds(10)

        delegate.startPollingFinderExtensionRequests()
        defaults.set("/tmp/First.swift", forKey: "openInCEFiles")
        try await eventually(timeout: .seconds(30)) { opened == ["/tmp/First.swift"] }

        defaults.set("/tmp/Second.swift;/tmp/Third.swift", forKey: "openInCEFiles")
        try await eventually(timeout: .seconds(30)) {
            opened == ["/tmp/First.swift", "/tmp/Second.swift", "/tmp/Third.swift"]
        }
        #expect(defaults.object(forKey: "openInCEFiles") == nil)
        #expect(delegate.checkForFilesToOpen())
    }

    @Test
    func unavailableSharedDefaultsStopThePolling() async throws {
        let delegate = AppDelegate()
        var requests = 0
        delegate.finderExtensionDefaults = {
            requests += 1
            return nil
        }
        delegate.finderExtensionPollInterval = .milliseconds(10)

        delegate.startPollingFinderExtensionRequests()
        try await eventually(timeout: .seconds(30)) { requests == 1 }
        try await Task.sleep(for: .milliseconds(100))

        #expect(requests == 1)
        #expect(delegate.checkForFilesToOpen() == false)
        #expect(requests == 2)
    }

    @Test
    func restartingThePollingReplacesThePreviousLoop() async throws {
        let delegate = AppDelegate()
        var requests = 0
        delegate.finderExtensionDefaults = {
            requests += 1
            return nil
        }

        delegate.startPollingFinderExtensionRequests()
        delegate.startPollingFinderExtensionRequests()
        try await eventually(timeout: .seconds(30)) { requests >= 1 }
        try await Task.sleep(for: .milliseconds(100))

        #expect(requests == 1)
        #expect(delegate.checkForFilesToOpen() == false)
    }

    @Test
    func reopenedDocumentWindowsAdoptTheDocumentName() {
        let document = NSDocument()
        document.displayName = "Renamed Fixture"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        window.title = "Stale"
        document.addWindowController(NSWindowController(window: window))
        defer { window.close() }

        AppDelegate.synchronizeWindowTitle(of: document)
        #expect(window.title == "Renamed Fixture")

        AppDelegate.synchronizeWindowTitle(of: nil)
        AppDelegate.synchronizeWindowTitle(of: NSDocument())
    }

    @Test
    func defaultReopenOpensTheRequestedFileThroughTheDocumentController() async throws {
        try await withTempDir { directory in
            let url = directory.appending(path: "Reopened.txt")
            try "alpha\n".write(to: url, atomically: true, encoding: .utf8)
            let delegate = AppDelegate()

            delegate.reopenDocument(url)

            try await eventually(timeout: .seconds(30)) {
                DreamderDocumentController.shared.document(for: url) != nil
            }
            try await Task.sleep(for: .milliseconds(200))
            let document = try #require(DreamderDocumentController.shared.document(for: url))
            document.close()
        }
    }
}
