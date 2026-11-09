import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct HeadlessTestHostTests {
    @Test
    func theTestHostRunsHeadless() {
        #expect(DreamderHeadless.isEnabled)
        #expect(NSApp.activationPolicy() == .accessory)
    }

    private func windowServerRecord(for window: NSWindow, options: CGWindowListOption) -> [String: Any]? {
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.first { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
    }

    @Test
    func orderedWindowsNeverReachAnyScreen() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.systemRed.cgColor
        defer { window.close() }

        window.makeKeyAndOrderFront(nil)

        #expect(window.isVisible)
        #expect(window.level == DreamderHeadless.hiddenLevel)
        #expect(window.alphaValue == 0)
        #expect(window.collectionBehavior.isSuperset(of: [.transient, .ignoresCycle, .stationary]))
        #expect(window.isRestorable == false)
        #expect(NSApp.isActive == false)
        #expect(NSApp.activationPolicy() == .accessory)
        #expect(DreamderHeadless.intersectsAnyScreen(window.frame) == false)

        #expect(windowServerRecord(for: window, options: [.optionOnScreenOnly]) == nil)
        try await eventually(timeout: .seconds(20)) {
            windowServerRecord(for: window, options: [.optionAll])?[kCGWindowLayer as String] as? Int
                == Int(CGWindowLevelForKey(.minimumWindow))
        }
        let settled = try #require(windowServerRecord(for: window, options: [.optionAll]))
        let layer = try #require(settled[kCGWindowLayer as String] as? Int)
        #expect(layer == Int(CGWindowLevelForKey(.minimumWindow)))
        let alpha = try #require(settled[kCGWindowAlpha as String] as? Double)
        #expect(alpha == 0)
        let boundsDictionary = try #require(settled[kCGWindowBounds as String] as? NSDictionary)
        let bounds = try #require(CGRect(dictionaryRepresentation: boundsDictionary))
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(bounds) })
    }

    @Test
    func hiddenWindowsStillRenderForSnapshots() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemGreen.cgColor
        window.contentView = view
        defer { window.close() }

        window.orderFront(nil)
        view.display()

        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let color = try #require(representation.colorAt(x: 60, y: 40)?.usingColorSpace(.sRGB))
        #expect(color.greenComponent > 0.5)
        #expect(color.redComponent < 0.5)
    }

    @Test
    func recentDocumentsAreNotRecordedInHeadlessMode() throws {
        let controller = try #require(DreamderDocumentController.shared as? DreamderDocumentController)
        #expect(controller.recordsRecentDocuments == false)

        controller.noteNewRecentDocumentURL(URL(filePath: "/tmp/dreamder-headless-recent/\(UUID().uuidString).txt"))
        controller.noteNewRecentDocument(CodeFileDocument())
    }

    @Test
    func welcomeRecentsAreNotRecordedInHeadlessMode() throws {
        let controller = try #require(DreamderDocumentController.shared as? DreamderDocumentController)
        let before = RecentProjectsManager.shared.recentPaths

        controller.noteRecentProject(
            at: URL(filePath: "/tmp/dreamder-headless-recent/\(UUID().uuidString)")
        )

        #expect(RecentProjectsManager.shared.recentPaths == before)
    }

    @Test
    func everyModalAndExternalOpenEntryPointIsIntercepted() {
        #expect(DreamderHeadless.missingSelectors.isEmpty)
        #expect(DreamderHeadless.interceptedSelectors.isSuperset(of: [
            "NSAlert.runModal",
            "NSAlert.beginSheetModalForWindow:completionHandler:",
            "NSApplication.runModalForWindow:",
            "NSApplication.terminate:",
            "NSMenu.popUpMenuPositioningItem:atLocation:inView:",
            "NSMenu.+popUpContextMenu:withEvent:forView:",
            "NSWorkspace.openURL:",
            "NSWorkspace.activateFileViewerSelectingURLs:",
            "NSWorkspace.selectFile:inFileViewerRootedAtPath:",
            "NSWorkspace.openURL:configuration:completionHandler:",
            "NSWorkspace.openURLs:withApplicationAtURL:configuration:completionHandler:",
            "NSWorkspace.openApplicationAtURL:configuration:completionHandler:"
        ]))
    }

    @Test
    func terminatingTheApplicationIsSuppressed() {
        let before = DreamderHeadless.suppressedTerminations

        NSApplication.shared.terminate(nil)

        #expect(DreamderHeadless.suppressedTerminations == before + 1)
    }

    @Test
    func uncaughtExceptionsAreReportedThroughTheInstalledHandler() throws {
        let handler = try #require(NSGetUncaughtExceptionHandler())

        handler(NSException(name: .genericException, reason: "headless-report", userInfo: nil))
    }

    @Test
    func systemFilePanelsAnswerCancelWithoutConstructingAnyPanel() {
        let token = UUID().uuidString
        let panels = SystemFilePanels()
        let before = DreamderHeadless.suppressedModals.count

        let opened = panels.chooseFiles(OpenPanelRequest(message: "headless open \(token)"))
        let saved = panels.chooseSaveLocation(SavePanelRequest(message: "headless save \(token)"))

        #expect(opened.isEmpty)
        #expect(saved == nil)
        #expect(DreamderHeadless.suppressedModals.count == before + 2)
        let mine = DreamderHeadless.suppressedModals.filter { $0.hasSuffix(token) }
        #expect(mine == ["headless open \(token)", "headless save \(token)"])
    }

    @Test
    func panelRequestsDescribeThemselvesByMessageThenTitleThenPrompt() {
        #expect(OpenPanelRequest(title: "t", prompt: "p", message: "m").summary == "m")
        #expect(OpenPanelRequest(title: "t", prompt: "p").summary == "t")
        #expect(OpenPanelRequest(prompt: "p").summary == "p")
        #expect(OpenPanelRequest().summary == "")
        #expect(SavePanelRequest(title: "t", prompt: "p", message: "m").summary == "m")
        #expect(SavePanelRequest(title: "t", prompt: "p").summary == "t")
        #expect(SavePanelRequest(prompt: "p").summary == "p")
        #expect(SavePanelRequest().summary == "")
    }

    @Test
    func popupMenusNeverOpen() throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSMenu.popUpMenuPositioningItem:atLocation:inView:"))
        try #require(DreamderHeadless.interceptedSelectors.contains("NSMenu.+popUpContextMenu:withEvent:forView:"))
        let menu = NSMenu(title: "headless menu")
        menu.addItem(NSMenuItem(title: "Item", action: nil, keyEquivalent: ""))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))

        #expect(menu.popUp(positioning: nil, at: .zero, in: view) == false)
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        NSMenu.popUpContextMenu(menu, with: event, for: view)

        #expect(DreamderHeadless.suppressedModals.suffix(2) == ["headless menu", "headless menu"])
    }

    @Test
    func applicationModalSessionsAreAbortedWithoutAppearing() throws {
        try #require(DreamderHeadless.interceptedSelectors.contains("NSApplication.runModalForWindow:"))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "headless modal"
        defer { window.close() }

        #expect(NSApp.runModal(for: window) == .abort)
        #expect(window.isVisible == false)
        #expect(DreamderHeadless.suppressedModals.last == "headless modal")
    }

    @Test
    func externalApplicationsAndFinderAreNeverLaunched() async throws {
        try #require(DreamderHeadless.missingSelectors.isEmpty)
        try #require(DreamderHeadless.interceptedSelectors.contains("NSWorkspace.openURL:"))
        let url = URL(filePath: "/tmp/dreamder-headless-external/\(UUID().uuidString)")
        let application = URL(filePath: "/System/Applications/TextEdit.app")

        #expect(NSWorkspace.shared.open(url) == false)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #expect(NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "") == false)
        let configured: (any Error)? = await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                continuation.resume(returning: error)
            }
        }
        #expect(configured != nil)
        let withApplication: (any Error)? = await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: application,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                continuation.resume(returning: error)
            }
        }
        #expect(withApplication != nil)
        let launched: (any Error)? = await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                continuation.resume(returning: error)
            }
        }
        #expect(launched != nil)

        let recorded = DreamderHeadless.suppressedExternalOpens.suffix(6)
        #expect(recorded == [
            url.absoluteString, url.absoluteString, url.path, url.absoluteString, url.absoluteString,
            application.absoluteString
        ])
    }

    @Test(arguments: [
        ([String: String](), false, false),
        (["DREAMDER_HEADLESS": "1"], false, true),
        (["DREAMDER_HEADLESS": "0"], false, false),
        (["DREAMDER_HEADLESS": "yes"], false, false),
        ([String: String](), true, true),
        (["DREAMDER_HEADLESS": "0"], true, true)
    ])
    func headlessIsEnabledByTheEnvironmentOrTheLaunchArgument(
        environment: [String: String],
        argument: Bool,
        expected: Bool
    ) throws {
        try withIsolatedDefaults { defaults in
            defaults.set(argument, forKey: DreamderHeadless.argumentKey)

            #expect(DreamderHeadless.resolveIsEnabled(environment: environment, defaults: defaults) == expected)
        }
    }
}
