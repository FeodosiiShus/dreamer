import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
final class KeyProbeView: NSView {
    var keyDowns = 0

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        keyDowns += 1
    }
}

@MainActor
final class PanelCallLog {
    var keyCodes: [UInt16] = []
    var closes = 0
}

@MainActor
final class ScreenlessWindow: NSWindow {
    override var screen: NSScreen? { nil }
}

@MainActor
@Suite(.serialized, .isolatedDefaults, .uiGate)
struct SearchEverywherePanelTests {
    @MainActor
    struct Rig {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow
        let host: SearchEverywherePanelHost

        var panels: [SearchEverywherePanel] {
            (window.childWindows ?? []).compactMap { $0 as? SearchEverywherePanel }
        }

        func panel(width: CGFloat) -> SearchEverywherePanel? {
            panels.first { $0.frame.width == width }
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.tearDownFileScope()
        }
    }

    func makeRig(_ dir: URL) throws -> Rig {
        let defaults = try IsolatedDefaults.require()
        let workspace = try SearchEverywhereFixtures.makeWorkspace(dir)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let controller = DreamderWindowController(window: window, workspace: nil)
        controller.workspace = workspace
        window.windowController = controller
        let host = SearchEverywherePanelHost(
            defaults: defaults,
            recentFiles: SearchEverywhereRecentFilesStore(defaults: defaults)
        )
        return Rig(workspace: workspace, controller: controller, window: window, host: host)
    }

    func hide(_ panel: SearchEverywherePanel) {
        let delegate = panel.delegate
        panel.delegate = nil
        panel.orderOut(nil)
        panel.delegate = delegate
    }

    @Test
    func togglingOpensClosesAndReopensAFreshPanel() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }

            rig.host.toggle(in: rig.controller)
            let first = try #require(rig.panels.first)
            #expect(rig.panels.count == 1)
            #expect(first.isVisible)
            #expect(first.frame.size == NSSize(width: 670, height: 520))

            rig.host.toggle(in: rig.controller)
            #expect(!first.isVisible)
            #expect(rig.panels.isEmpty)

            rig.host.toggle(in: rig.controller)
            let second = try #require(rig.panels.first)
            #expect(second !== first)
            #expect(second.isVisible)
        }
    }

    @Test
    func aHiddenPanelIsPresentedAgainInTheSameWindow() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }
            rig.host.toggle(in: rig.controller)
            let panel = try #require(rig.panels.first)
            hide(panel)
            rig.window.removeChildWindow(panel)
            #expect(!panel.isVisible)
            #expect(panel.parent == nil)

            rig.host.toggle(in: rig.controller)

            #expect(panel.isVisible)
            #expect(panel.parent === rig.window)
            #expect(rig.panels.count == 1)
        }
    }

    @Test
    func aHiddenPanelStillAttachedIsPresentedWithoutReparenting() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }
            rig.host.toggle(in: rig.controller)
            let panel = try #require(rig.panels.first)
            hide(panel)

            rig.host.toggle(in: rig.controller)

            #expect(panel.isVisible)
            #expect(panel.parent === rig.window)
            #expect(rig.panels.count == 1)
        }
    }

    @Test
    func openingATabReusesTheExistingPanel() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }

            rig.host.open(tab: .classes, in: rig.controller)
            let first = try #require(rig.panels.first)
            rig.host.open(tab: .symbols, in: rig.controller)

            #expect(rig.panels.count == 1)
            #expect(rig.panels.first === first)
            #expect(first.isVisible)
        }
    }

    @Test
    func recentFilesGetTheirOwnSmallerPanel() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            defer { rig.close() }

            rig.host.toggle(in: rig.controller)
            rig.host.openRecentFiles(in: rig.controller)
            let recent = try #require(rig.panel(width: 560))

            #expect(rig.panels.count == 2)
            #expect(recent.frame.size == NSSize(width: 560, height: 400))
            #expect(rig.panel(width: 670) !== recent)

            rig.host.openRecentFiles(in: rig.controller)
            #expect(rig.panels.count == 2)
            #expect(rig.panel(width: 560) === recent)
        }
    }

    @Test
    func theRecentFilesActionOpensTheRecentFilesPanelInTheWindow() throws {
        try withTempDir { dir in
            let rig = try makeRig(dir)
            let workspaceKey = "dreamder.recentFiles.\(rig.workspace.fileURL?.standardizedFileURL.path ?? "untitled")"
            defer {
                rig.close()
                UserDefaults.standard.removeObject(forKey: workspaceKey)
            }

            rig.controller.openRecentFiles(nil)

            let recent = try #require(rig.panel(width: 560))
            #expect(recent.isVisible)
            #expect(recent.frame.size == NSSize(width: 560, height: 400))
        }
    }
}
