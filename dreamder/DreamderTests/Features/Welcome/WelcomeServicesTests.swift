import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
private final class ScriptedDocumentController: AppDocumentControlling {
    var failure: (any Error)?
    var openedDocument: NSDocument?
    private(set) var requested: [URL] = []
    var documents: [NSDocument] { [] }

    func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        requested.append(url)
        completionHandler(openedDocument, false, failure)
    }

    func openDocument(_ sender: Any?) {}
    func newDocument(_ sender: Any?) {}
    func closeAllDocuments(
        withDelegate delegate: Any?,
        didCloseAllSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {}
}

@MainActor
private final class AttemptCounter {
    var count = 0
}

@MainActor
private final class CallLog {
    var completions = 0
    var errors: [any Error] = []
    var cancellations = 0
    var reportedDocument: NSDocument?
}

@MainActor
@Suite(.serialized, .uiGate)
struct WelcomeServicesTests {
    private func waitForModalCount(above count: Int) async {
        for _ in 0..<60 where DreamderHeadless.suppressedModals.count <= count {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func sampleProject(_ path: String = "/p/sample") -> RecentProject {
        RecentProject(
            path: path,
            displayName: RecentProject.displayName(forPath: path),
            projectOpenTimestamp: 0,
            isDirectory: true,
            hidden: false
        )
    }

    @Test
    func openingADocumentCompletes() {
        let controller = ScriptedDocumentController()
        let log = CallLog()

        controller.openDocument(at: URL(filePath: "/p/ok.txt"), onCompletion: { log.completions += 1 })

        #expect(log.completions == 1)
        #expect(controller.requested == [URL(filePath: "/p/ok.txt")])
    }

    @Test
    func aFailedOpenShowsTheErrorAndReportsIt() {
        let controller = ScriptedDocumentController()
        let message = "welcome-open-failure-\(UUID().uuidString)"
        controller.failure = NSError(domain: "WelcomeTests", code: 7, userInfo: [NSLocalizedDescriptionKey: message])
        let log = CallLog()

        controller.openDocument(
            at: URL(filePath: "/p/missing.txt"),
            onCompletion: { log.completions += 1 },
            onError: { log.errors.append($0) }
        )

        #expect(log.completions == 0)
        #expect(log.errors.count == 1)
        #expect(DreamderHeadless.suppressedModals.contains(message))
    }

    @Test
    func aFailedOpenWithTheDefaultHandlersOnlyShowsTheAlert() {
        let controller = ScriptedDocumentController()
        let message = "welcome-default-failure-\(UUID().uuidString)"
        controller.failure = NSError(domain: "WelcomeTests", code: 8, userInfo: [NSLocalizedDescriptionKey: message])

        controller.openDocument(at: URL(filePath: "/p/missing.txt"))

        #expect(DreamderHeadless.suppressedModals.contains(message))
    }

    @Test
    func theLiveRevealGoesToFinder() {
        let url = URL(filePath: "/p/reveal-\(UUID().uuidString)", directoryHint: .isDirectory)

        WelcomeServices.live.reveal([url])

        #expect(DreamderHeadless.suppressedExternalOpens.contains(url.absoluteString))
    }

    @Test
    func theLiveRemovalConfirmationIsAnAlertThatHeadlessModeDeclines() {
        let confirmed = WelcomeServices.live.confirmRemoval(sampleProject())

        #expect(confirmed == false)
        #expect(DreamderHeadless.suppressedModals.contains("Remove Recent Project"))
    }

    @Test
    func dismissClosesEveryWelcomeWindowOfTheGivenWindows() {
        let windows = (0..<2).map { _ in makeWindow(scene: SceneID.welcome.rawValue) }
        let bystander = makeWindow(scene: "not-welcome")
        defer { bystander.close() }
        let services = makeServices(controller: ScriptedDocumentController(), windows: { windows + [bystander] })

        services.dismiss()

        #expect(windows.allSatisfy { !$0.isVisible })
        #expect(bystander.isVisible)
    }

    @Test
    func aCancelledOpenDialogReportsCancellationOnly() {
        let controller = ScriptedDocumentController()
        let panels = FakeFilePanels()
        let log = CallLog()

        controller.openDocument(
            onCompletion: { _, _ in log.completions += 1 },
            onCancel: { log.cancellations += 1 },
            panels: panels
        )

        #expect(log.cancellations == 1)
        #expect(log.completions == 0)
        #expect(controller.requested.isEmpty)
        let request = panels.openRequests.first
        #expect(request?.title == "Open Workspace or File")
        #expect(request?.canChooseFiles == true)
        #expect(request?.canChooseDirectories == true)
    }

    @Test
    func aChosenFileIsOpenedAndTheDocumentReported() {
        let controller = ScriptedDocumentController()
        let document = NSDocument()
        controller.openedDocument = document
        let chosen = URL(filePath: "/p/chosen-\(UUID().uuidString).txt")
        let log = CallLog()

        controller.openDocument(
            onCompletion: { reported, _ in
                log.completions += 1
                log.reportedDocument = reported
            },
            onCancel: { log.cancellations += 1 },
            panels: FakeFilePanels(files: [chosen, URL(filePath: "/p/ignored.txt")])
        )

        #expect(controller.requested == [chosen])
        #expect(log.completions == 1)
        #expect(log.cancellations == 0)
        #expect(log.reportedDocument === document)
    }

    @Test
    func aChosenFileThatFailsToOpenShowsTheErrorAndReportsNothing() {
        let controller = ScriptedDocumentController()
        let message = "welcome-chosen-failure-\(UUID().uuidString)"
        controller.failure = NSError(domain: "WelcomeTests", code: 9, userInfo: [NSLocalizedDescriptionKey: message])
        let log = CallLog()

        controller.openDocument(
            onCompletion: { _, _ in log.completions += 1 },
            onCancel: { log.cancellations += 1 },
            panels: FakeFilePanels(files: [URL(filePath: "/p/broken.txt")])
        )

        #expect(log.completions == 0)
        #expect(log.cancellations == 0)
        #expect(DreamderHeadless.suppressedModals.contains(message))
    }

    @Test
    func aChosenFileWithoutADocumentShowsTheGenericAlert() {
        let controller = ScriptedDocumentController()
        let log = CallLog()
        let before = DreamderHeadless.suppressedModals.count

        controller.openDocument(
            onCompletion: { _, _ in log.completions += 1 },
            onCancel: { log.cancellations += 1 },
            panels: FakeFilePanels(files: [URL(filePath: "/p/empty.txt")])
        )

        #expect(log.completions == 0)
        #expect(DreamderHeadless.suppressedModals.dropFirst(before).contains("Failed to get document"))
    }

    @Test
    func theApplicationWindowsIncludeAWindowTheTestCreated() {
        let window = makeWindow(scene: SceneID.welcome.rawValue)
        defer { window.close() }

        #expect(WelcomeServices.applicationWindows().contains(window))
    }

    @Test
    func theLiveCloneViewModelIsFresh() {
        let model = WelcomeServices.live.makeCloneViewModel()

        #expect(model.repoUrlStr.isEmpty)
        #expect(model.isCloning == false)
    }

    @Test
    func theLiveNewProjectShowsTheSavePanelAndIgnoresCancellation() async throws {
        let before = DreamderHeadless.suppressedModals.count
        let log = CallLog()

        WelcomeServices.live.newProject { log.completions += 1 }
        try await eventually(timeout: .seconds(30)) { DreamderHeadless.suppressedModals.count > before }

        #expect(log.completions == 0)
    }

    @Test
    func theLiveOpenDialogIsCancelledInHeadlessMode() async {
        let before = DreamderHeadless.suppressedModals.count
        let log = CallLog()

        WelcomeServices.live.openFromDisk { log.completions += 1 }
        await waitForModalCount(above: before)

        #expect(log.completions == 0)
        #expect(DreamderHeadless.suppressedModals.count > before)
    }

    @Test
    func theLiveOpenReportsAMissingFileThroughTheSharedController() async {
        let before = DreamderHeadless.suppressedModals.count
        let log = CallLog()

        WelcomeServices.live.open(URL(filePath: "/dreamder-welcome-missing/\(UUID().uuidString).txt")) {
            log.completions += 1
        }
        await waitForModalCount(above: before)

        #expect(log.completions == 0)
        #expect(DreamderHeadless.suppressedModals.count > before)
    }

    @Test
    func theDocumentControllerRecordsOpenedProjectsInItsManager() throws {
        let controller = try #require(NSDocumentController.shared as? DreamderDocumentController)
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let manager = RecentProjectsManager(defaults: defaults)

        try withTempDir { directory in
            let file = directory.appending(path: "note.txt")
            try Data("x".utf8).write(to: file)
            controller.recordRecentProject(at: directory, in: manager)
            controller.recordRecentProject(at: file, in: manager)

            #expect(manager.recentProjects.map(\.displayName) == ["note.txt", directory.lastPathComponent])
            #expect(manager.recentProjects.map(\.isDirectory) == [false, true])
        }
    }

    @Test
    func aSuccessfulOpenWithTheDefaultHandlersOpensTheRequestedURL() {
        let controller = ScriptedDocumentController()

        controller.openDocument(at: URL(filePath: "/p/default-success.txt"))

        #expect(controller.requested == [URL(filePath: "/p/default-success.txt")])
    }

    @Test
    func copyingToTheClipboardReplacesThePasteboardText() {
        let pasteboard = InMemoryPasteboard()
        let services = makeServices(pasteboard: pasteboard, controller: ScriptedDocumentController())

        services.copyToClipboard("/p/copied")

        #expect(pasteboard.plainText == "/p/copied")
    }

    @Test
    func openingThroughTheInjectedControllerRequestsTheURLAndCompletes() {
        let controller = ScriptedDocumentController()
        let log = CallLog()
        let services = makeServices(controller: controller)

        services.open(URL(filePath: "/p/injected.txt")) { log.completions += 1 }

        #expect(controller.requested == [URL(filePath: "/p/injected.txt")])
        #expect(log.completions == 1)
    }

    @Test
    func aChosenFileFromTheOpenDialogCompletesTheWelcomeAction() {
        let controller = ScriptedDocumentController()
        controller.openedDocument = NSDocument()
        let chosen = URL(filePath: "/p/disk-\(UUID().uuidString).txt")
        let log = CallLog()
        let services = makeServices(controller: controller, panels: FakeFilePanels(files: [chosen]))

        services.openFromDisk { log.completions += 1 }

        #expect(controller.requested == [chosen])
        #expect(log.completions == 1)
    }

    @Test
    func aCancelledOpenDialogLeavesTheWelcomeActionPending() {
        let controller = ScriptedDocumentController()
        let log = CallLog()
        let services = makeServices(controller: controller, panels: FakeFilePanels())

        services.openFromDisk { log.completions += 1 }

        #expect(controller.requested.isEmpty)
        #expect(log.completions == 0)
    }

    @Test
    func creatingANewProjectCompletesWhenTheDocumentWasCreated() async throws {
        let log = CallLog()
        let services = makeServices(controller: ScriptedDocumentController(), createsDocument: true)

        services.newProject { log.completions += 1 }

        try await eventually(timeout: .seconds(30)) { log.completions == 1 }
    }

    @Test
    func creatingANewProjectThatWasCancelledNeverCompletes() async throws {
        let log = CallLog()
        let attempts = AttemptCounter()
        let controller = ScriptedDocumentController()
        let services = makeServices(controller: controller, createsDocument: false, attempts: attempts)

        services.newProject { log.completions += 1 }
        try await eventually(timeout: .seconds(30)) { attempts.count == 1 }
        try await Task.sleep(for: .milliseconds(50))

        #expect(log.completions == 0)
    }

    private func makeWindow(scene: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(scene)
        window.orderFront(nil)
        return window
    }

    private func makeServices(
        pasteboard: any PasteboardAccess = InMemoryPasteboard(),
        controller: ScriptedDocumentController,
        panels: any FilePanelPresenting = FakeFilePanels(),
        createsDocument: Bool = false,
        attempts: AttemptCounter = AttemptCounter(),
        windows: @escaping @MainActor () -> [NSWindow] = { [] }
    ) -> WelcomeServices {
        WelcomeServices.make(
            pasteboard: pasteboard,
            documents: { controller },
            panels: panels,
            createDocument: {
                attempts.count += 1
                return createsDocument
            },
            windows: windows
        )
    }
}
