import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension DreamderAutomationTests {
    @Test
    func installedSnapshotRouteWritesTheWindowManifestToTheNotifiedDirectory() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            let center = makeInstalledCenter()
            harness.bringToFront()
            let shots = directory.appending(path: "route-shots")

            center.post(name: DreamderAutomation.snapshotNotification, object: shots.path(percentEncoded: false))

            let manifest = try outputLines("windows.txt", in: shots)
            #expect(manifest.contains { $0.hasPrefix("\(window.windowNumber) ") })
        }
    }

    @Test
    func installedToolWindowRouteShowsTheNamedToolWindowAndIgnoresMissingNames() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let center = makeInstalledCenter()
            harness.bringToFront()
            let before = harness.workspace.toolWindowManager.visibleWindows

            center.post(name: DreamderAutomation.toolWindowNotification, object: nil)
            #expect(harness.workspace.toolWindowManager.visibleWindows == before)

            center.post(name: DreamderAutomation.toolWindowNotification, object: "git")
            #expect(harness.workspace.toolWindowManager.isVisible(.git))
        }
    }

    @Test
    func installedOpenRouteOpensTheNotifiedFile() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let center = makeInstalledCenter()

            center.post(name: DreamderAutomation.openNotification, object: harness.path("One.swift") + ":2:4")

            let tab = try #require(harness.manager.activeEditor.selectedTab)
            #expect(tab.file.name == "One.swift")
            #expect(tab.cursorPositions.first?.start.line == 2)
            #expect(tab.cursorPositions.first?.start.column == 4)
        }
    }

    @Test
    func installedActionRouteSendsTheNotifiedSelector() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            let center = makeInstalledCenter()
            harness.bringToFront()

            center.post(name: DreamderAutomation.actionNotification, object: "splitEditorRight:")

            #expect(harness.manager.flattenedEditors.count == 2)
        }
    }

    @Test
    func installedContextMenuRouteWritesTheEditorMenuDump() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let textView = try attachTextView(to: harness)
            defer { textView.removeFromSuperview() }
            let center = makeInstalledCenter()
            let output = directory.appending(path: "route-menu")

            center.post(name: DreamderAutomation.contextMenuNotification, object: output.path(percentEncoded: false))

            #expect(try outputLines("contextmenu.txt", in: output).first == "class=TextView")
        }
    }

    @Test
    func installedAnnotateRouteReportsAMissingBlameCoordinator() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let center = makeInstalledCenter()
            harness.bringToFront()
            let output = directory.appending(path: "route-annotate")

            center.post(name: DreamderAutomation.annotateNotification, object: output.path(percentEncoded: false))

            #expect(try self.output("annotate.txt", in: output) == "error: no blame coordinator\n")
        }
    }

    @Test
    func installedMenuItemRouteReportsAMissingEditorMenu() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let center = makeInstalledCenter()
            harness.bringToFront()
            let output = directory.appending(path: "route-item")

            center.post(
                name: DreamderAutomation.menuItemNotification,
                object: output.path(percentEncoded: false) + "|Copy"
            )

            #expect(try self.output("menuitem.txt", in: output) == "error: no editor menu\n")
        }
    }

    @Test
    func installWithoutHeadlessModeRegistersNoRoutes() throws {
        try withTempDir { directory in
            let center = NotificationCenter()
            DreamderAutomation.install(center: center, enabled: false, queue: nil)
            let shots = directory.appending(path: "disabled-shots")

            center.post(name: DreamderAutomation.snapshotNotification, object: shots.path(percentEncoded: false))

            #expect(FileManager.default.fileExists(atPath: shots.path(percentEncoded: false)) == false)
        }
    }
}
