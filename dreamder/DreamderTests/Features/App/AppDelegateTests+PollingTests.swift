import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageClient
import LanguageServerProtocol
import Testing
@testable import Dreamder

extension AppDelegateTests {
    @Test
    func quittingFlushesTheDebouncedSettings() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory)
            settings.preferences.general.reopenBehavior = .newDocument
            let delegate = AppDelegate()
            delegate.settings = settings

            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

            let reloaded = Dreamder.Settings(baseURL: directory)
            #expect(reloaded.preferences.general.reopenBehavior == .newDocument)
        }
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
        defaults.set(["/tmp/First.swift"], forKey: "openInCEFiles")
        try await eventually(timeout: .seconds(30)) { opened == ["/tmp/First.swift"] }

        defaults.set(["/tmp/Second.swift", "/tmp/Third.swift"], forKey: "openInCEFiles")
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
