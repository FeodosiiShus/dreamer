import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct WindowExtensionsCoverageTests {
    @MainActor
    private final class CloseCounter: NSObject, NSWindowDelegate {
        private(set) var closeCount = 0

        func windowWillClose(_ notification: Notification) {
            closeCount += 1
        }
    }

    private func makeWindow(
        identifier: SceneID? = nil,
        frame: NSRect = NSRect(x: 100, y: 100, width: 400, height: 300),
        counter: CloseCounter? = nil
    ) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let identifier {
            window.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        }
        window.delegate = counter
        return window
    }

    @Test
    func closeWindowClosesTheWindowWithTheIdentifier() {
        let counter = CloseCounter()
        let window = makeWindow(identifier: .about, counter: counter)
        let bystanderCounter = CloseCounter()
        let bystander = makeWindow(counter: bystanderCounter)
        defer {
            window.close()
            bystander.close()
        }

        for existing in NSApp.windows where existing !== window && existing.identifier?.rawValue == SceneID.about.rawValue {
            existing.identifier = nil
        }
        NSApp.closeWindow(.about)

        #expect(counter.closeCount == 1)
        #expect(bystanderCounter.closeCount == 0)
    }

    @Test
    func closeWindowIsANoOpWithoutAMatchingWindow() {
        let counter = CloseCounter()
        let window = makeWindow(counter: counter)
        defer { window.close() }

        NSApp.closeWindow(.about)

        #expect(counter.closeCount == 0)
    }

    @Test
    func closeWindowVariadicClosesEveryNamedWindow() {
        let extensionsCounter = CloseCounter()
        let settingsCounter = CloseCounter()
        let extensionsWindow = makeWindow(identifier: .about, counter: extensionsCounter)
        let settingsWindow = makeWindow(identifier: .settings, counter: settingsCounter)
        defer {
            extensionsWindow.close()
            settingsWindow.close()
        }

        for existing in NSApp.windows where existing !== extensionsWindow && existing !== settingsWindow {
            let raw = existing.identifier?.rawValue
            if raw == SceneID.about.rawValue || raw == SceneID.settings.rawValue {
                existing.identifier = nil
            }
        }
        NSApp.closeWindow(.about, .settings)

        #expect(extensionsCounter.closeCount == 1)
        #expect(settingsCounter.closeCount == 1)
    }

    @Test
    func openSwiftUIWindowsCountsOnlyWindowsCarryingSceneIdentifiers() {
        let before = NSApp.openSwiftUIWindows
        let sceneWindow = makeWindow(identifier: .about)
        let otherWindow = makeWindow()
        otherWindow.identifier = NSUserInterfaceItemIdentifier("not-a-scene")
        defer {
            sceneWindow.close()
            otherWindow.close()
        }

        #expect(NSApp.openSwiftUIWindows == before + 1)
    }

    @Test
    func openWindowActionAcceptsASceneIdentifier() async throws {
        let probe = OpenWindowProbe()
        let hosted = HostedViewFixture.host(size: NSSize(width: 100, height: 100)) {
            OpenWindowProbeView(probe: probe)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(100))

        #expect(probe.invocations == 1)
    }
}

@MainActor
private final class OpenWindowProbe {
    var invocations = 0
}

private struct OpenWindowProbeView: View {
    let probe: OpenWindowProbe

    @Environment(\.openWindow)
    private var openWindow

    var body: some View {
        Color.clear.onAppear {
            openWindow(sceneID: .about)
            probe.invocations += 1
        }
    }
}
