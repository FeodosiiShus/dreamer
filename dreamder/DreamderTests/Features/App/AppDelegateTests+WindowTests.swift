import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension AppDelegateTests {
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
            delegate.sceneOpener = { openedScenes.append($0) }
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
            delegate.sceneOpener = { openedScenes.append($0) }
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
        delegate.sceneOpener = { openedScenes.append($0) }

        delegate.openWelcome(delegate)
        delegate.openAbout(delegate)
        delegate.showDreamderSettings(nil)

        #expect(openedScenes == [.welcome, .about, .settings])
    }

    @Test
    func openingASceneBeforeAnOpenerIsInstalledQueuesItUntilTheOpenerArrives() {
        let delegate = AppDelegate()
        delegate.applicationWindows = { [] }
        var openedScenes: [SceneID] = []

        delegate.openScene(.about)
        delegate.openScene(.welcome)
        #expect(openedScenes.isEmpty)

        delegate.installSceneOpener { openedScenes.append($0) }
        #expect(openedScenes == [.about, .welcome])

        delegate.openScene(.settings)
        #expect(openedScenes == [.about, .welcome, .settings])

        delegate.installSceneOpener { openedScenes.append($0) }
        #expect(openedScenes == [.about, .welcome, .settings])
    }

    @Test
    func openingASceneBeforeAnOpenerIsInstalledFocusesTheExistingSceneWindowInstead() {
        let about = makeStubWindow(scene: .about)
        defer { about.close() }
        let delegate = AppDelegate()
        delegate.applicationWindows = { [about] }
        var openedScenes: [SceneID] = []

        delegate.openScene(.about)
        delegate.installSceneOpener { openedScenes.append($0) }

        #expect(about.focusCalls == 1)
        #expect(openedScenes.isEmpty)
    }

    @Test
    func theInstalledDelegateReceivesStaticSceneRequests() {
        let delegate = AppDelegate()
        var openedScenes: [SceneID] = []
        delegate.installSceneOpener { openedScenes.append($0) }

        withExtendedLifetime(delegate) {
            AppDelegate.openScene(.settings)
        }

        #expect(openedScenes == [.settings])
    }
}
