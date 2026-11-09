import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderAutomationTests {
    @Test(arguments: [
        "project", "commit", "structure", "run", "find", "terminal", "problems", "git", "languageServices"
    ])
    func showToolWindowShowsTheNamedToolWindow(name: String) throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let id = try #require(ToolWindowID(rawValue: name))

            harness.bringToFront()
            DreamderAutomation.showToolWindow(named: name, in: harness.controller)

            #expect(harness.workspace.toolWindowManager.isVisible(id))
        }
    }

    @Test(arguments: ["nonsense", "Project", ""])
    func showToolWindowIgnoresUnknownNames(name: String) throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let before = harness.workspace.toolWindowManager.visibleWindows

            harness.bringToFront()
            DreamderAutomation.showToolWindow(named: name, in: harness.controller)

            #expect(harness.workspace.toolWindowManager.visibleWindows == before)
        }
    }

    @Test
    func showToolWindowWithoutNameChangesNothing() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let before = harness.workspace.toolWindowManager.visibleWindows

            harness.bringToFront()
            DreamderAutomation.showToolWindow(named: nil, in: harness.controller)

            #expect(harness.workspace.toolWindowManager.visibleWindows == before)
        }
    }

    @Test
    func openShowsTheFileInTheOwningWorkspace() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, files: ["One.swift", "Sources/Inner.swift"])
            defer { harness.close() }

            DreamderAutomation.open(path: harness.path("One.swift"))
            #expect(harness.manager.activeEditor.selectedTab?.file.name == "One.swift")

            DreamderAutomation.open(path: harness.path("Sources/Inner.swift"))
            #expect(harness.manager.activeEditor.selectedTab?.file.name == "Inner.swift")
            #expect(harness.manager.activeEditor.tabs.count == 2)
        }
    }

    @Test
    func openWithLineAndColumnPlacesTheCaret() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            DreamderAutomation.open(path: harness.path("One.swift") + ":3:5")

            let tab = try #require(harness.manager.activeEditor.selectedTab)
            #expect(tab.file.name == "One.swift")
            #expect(tab.cursorPositions.first?.start.line == 3)
            #expect(tab.cursorPositions.first?.start.column == 5)
        }
    }

    @Test
    func openMovesTheCaretOfAnAlreadyOpenFile() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            DreamderAutomation.open(path: harness.path("One.swift") + ":1:2")
            DreamderAutomation.open(path: harness.path("One.swift") + ":2:7")

            let tab = try #require(harness.manager.activeEditor.selectedTab)
            #expect(harness.manager.activeEditor.tabs.count == 1)
            #expect(tab.cursorPositions.first?.start.line == 2)
            #expect(tab.cursorPositions.first?.start.column == 7)
        }
    }

    @Test
    func openResolvesSymlinkedWorkspacePaths() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let resolved = directory.resolvingSymlinksInPath().appending(path: "One.swift").path(percentEncoded: false)

            DreamderAutomation.open(path: resolved + ":2:3")

            let tab = try #require(harness.manager.activeEditor.selectedTab)
            #expect(tab.file.name == "One.swift")
            #expect(tab.cursorPositions.first?.start.line == 2)
        }
    }

    @Test
    func openRoutesTheFileToTheWorkspaceThatContainsIt() throws {
        try withTempDir { first in
            try withTempDir { second in
                let firstHarness = try makeHarness(in: first, files: ["Alpha.swift"])
                defer { firstHarness.close() }
                let secondHarness = try makeHarness(in: second, files: ["Beta.swift"])
                defer { secondHarness.close() }

                DreamderAutomation.open(path: secondHarness.path("Beta.swift"))

                #expect(secondHarness.manager.activeEditor.selectedTab?.file.name == "Beta.swift")
                #expect(firstHarness.manager.activeEditor.tabs.isEmpty)

                DreamderAutomation.open(path: firstHarness.path("Alpha.swift") + ":1:1")

                #expect(firstHarness.manager.activeEditor.selectedTab?.file.name == "Alpha.swift")
                #expect(secondHarness.manager.activeEditor.tabs.count == 1)
            }
        }
    }

    @Test
    func openIgnoresFilesOutsideEveryWorkspace() throws {
        try withTempDir { directory in
            let root = directory.appending(path: "app")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let siblingFile = directory.appending(path: "app-extra/Other.swift")
            try FileManager.default.createDirectory(
                at: siblingFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.sampleSource.write(to: siblingFile, atomically: true, encoding: .utf8)
            let harness = try makeHarness(in: root, files: ["Inside.swift"])
            defer { harness.close() }

            DreamderAutomation.open(path: siblingFile.path(percentEncoded: false))
            DreamderAutomation.open(path: "/nonexistent-dreamder-root/Missing.swift:1:1")
            DreamderAutomation.open(path: nil)

            #expect(harness.manager.activeEditor.tabs.isEmpty)
        }
    }

    @Test
    func performSendsTheSelectorThroughTheResponderChain() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            #expect(harness.manager.flattenedEditors.count == 1)

            harness.bringToFront()
            DreamderAutomation.perform(actionNamed: "splitEditorRight:")

            #expect(harness.manager.flattenedEditors.count == 2)
            #expect(harness.manager.activeEditor.selectedTab?.file.name == "One.swift")
        }
    }

    @Test
    func performIgnoresMissingAndUnhandledSelectors() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")

            harness.bringToFront()
            DreamderAutomation.perform(actionNamed: nil)
            DreamderAutomation.perform(actionNamed: "dreamderNoSuchAction:")

            #expect(harness.manager.flattenedEditors.count == 1)
        }
    }

    @Test
    func snapshotWritesAManifestListingTheVisibleWindows() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            harness.bringToFront()
            let output = directory.appending(path: "shots")

            DreamderAutomation.snapshot(to: output.path(percentEncoded: false))

            let manifest = try String(contentsOf: output.appending(path: "windows.txt"), encoding: .utf8)
            let lines = manifest.split(separator: "\n").map(String.init)
            let method = try #require(lines.first)
            #expect(method == "capture=window-server" || method == "capture=in-process")
            #expect(lines.contains { $0.hasPrefix("\(window.windowNumber) ") })
            let pictures = try FileManager.default.contentsOfDirectory(atPath: output.path(percentEncoded: false))
                .filter { $0.hasPrefix("window-") && $0.hasSuffix(".png") }
            #expect(pictures.isEmpty == false)
        }
    }
}
