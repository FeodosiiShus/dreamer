import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderAutomationTests {
    private static let sampleSource = "let one = 1\nlet two = 2\nlet three = 3\n"

    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let manager: EditorManager
        let root: URL

        func bringToFront() {
            controller.window?.makeKeyAndOrderFront(nil)
        }

        func path(_ relative: String) -> String {
            root.appending(path: relative).path(percentEncoded: false)
        }

        func openTab(_ relative: String) throws {
            let file = try #require(workspace.workspaceFileManager?.getFile(path(relative), createIfNotFound: true))
            manager.openTab(item: file)
        }

        func close() {
            controller.window?.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL, files: [String] = ["One.swift"]) throws -> Harness {
        for file in files {
            let url = directory.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.sampleSource.write(to: url, atomically: true, encoding: .utf8)
        }
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        DreamderDocumentController.shared.addDocument(workspace)
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        controller.window?.isReleasedWhenClosed = false
        let manager = try #require(workspace.editorManager)
        return Harness(workspace: workspace, controller: controller, manager: manager, root: directory)
    }

    private func output(_ name: String, in directory: URL) throws -> String {
        try String(contentsOf: directory.appending(path: name), encoding: .utf8)
    }

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

    @Test
    func contextMenuDumpDescribesTheEditorMenu() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            let textView = TextView(string: "hello\nworld\n")
            textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            window.contentView?.addSubview(textView)
            defer { textView.removeFromSuperview() }
            window.makeFirstResponder(textView)
            harness.bringToFront()
            let output = directory.appending(path: "menu")

            DreamderAutomation.writeContextMenu(to: output.path(percentEncoded: false))

            let lines = try self.output("contextmenu.txt", in: output).split(separator: "\n").map(String.init)
            #expect(lines.first == "class=TextView")
            #expect(lines.contains("items=3"))
            #expect(lines.contains("keyDownFallback=<nil>"))
            #expect(lines.contains { $0.hasPrefix("controlClickItems") } == false)
            #expect(Array(lines.suffix(3)) == ["Cut [enabled] ⌘X", "Copy [enabled] ⌘C", "Paste [enabled] ⌘V"])
        }
    }

    @Test
    func menuItemCommandReportsMissingItems() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            let textView = TextView(string: "hello\n")
            textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            window.contentView?.addSubview(textView)
            defer { textView.removeFromSuperview() }
            window.makeFirstResponder(textView)
            harness.bringToFront()
            let output = directory.appending(path: "item")

            DreamderAutomation.performMenuItem(named: output.path(percentEncoded: false) + "|Nothing Here")

            #expect(try self.output("menuitem.txt", in: output) == "error: menu item Nothing Here not found\n")
        }
    }

    @Test
    func annotateReportsMissingCoordinatorsAndTogglesExistingOnes() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.bringToFront()
            let output = directory.appending(path: "annotate")
            let outputPath = output.path(percentEncoded: false)

            DreamderAutomation.toggleAnnotate(to: outputPath)
            #expect(try self.output("annotate.txt", in: output) == "error: no blame coordinator\n")

            try harness.openTab("One.swift")
            DreamderAutomation.toggleAnnotate(to: outputPath)
            #expect(try self.output("annotate.txt", in: output) == "error: no blame coordinator\n")

            let tab = try #require(harness.manager.activeEditor.selectedTab)
            let coordinator = GitBlameCoordinator(editorInstance: tab, codeFile: CodeFileDocument())
            withExtendedLifetime(coordinator) {
                DreamderAutomation.toggleAnnotate(to: outputPath)
                #expect(coordinator.isAnnotating)
                #expect((try? self.output("annotate.txt", in: output)) == "annotating=true\n")

                DreamderAutomation.toggleAnnotate(to: outputPath)
                #expect(coordinator.isAnnotating == false)
                #expect((try? self.output("annotate.txt", in: output)) == "annotating=false\n")
            }
        }
    }

    @Test
    func describeRendersMenusWithSeparatorsShortcutsAndSubmenus() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let cut = NSMenuItem(title: "Cut", action: nil, keyEquivalent: "x")
        cut.keyEquivalentModifierMask = [.command]
        let copy = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "c")
        copy.keyEquivalentModifierMask = [.command, .shift, .option, .control]
        let functionKey = UnicodeScalar(UInt32(NSF5FunctionKey)).map { String(Character($0)) } ?? ""
        let run = NSMenuItem(title: "Run", action: nil, keyEquivalent: functionKey)
        run.keyEquivalentModifierMask = []
        run.isEnabled = false
        let plain = NSMenuItem(title: "Plain", action: nil, keyEquivalent: "")
        let parent = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(NSMenuItem(title: "Safari", action: nil, keyEquivalent: ""))
        parent.submenu = submenu
        for item in [cut, copy, NSMenuItem.separator(), run, plain, parent] {
            menu.addItem(item)
        }

        let lines = DreamderAutomation.describe(menu: menu, level: 0)

        #expect(lines == [
            "Cut [enabled] ⌘X",
            "Copy [enabled] ⌃⌥⇧⌘C",
            "---",
            "Run [disabled] F5",
            "Plain [enabled]",
            "Open With [enabled]",
            "  Safari [enabled]"
        ])
    }

    @Test
    func findItemSearchesSubmenusDepthFirstByExactTitle() {
        let menu = NSMenu()
        let parent = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let nested = NSMenuItem(title: "Safari", action: nil, keyEquivalent: "")
        submenu.addItem(nested)
        parent.submenu = submenu
        let top = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        menu.addItem(parent)
        menu.addItem(top)

        #expect(DreamderAutomation.findItem(in: menu, title: "Safari") === nested)
        #expect(DreamderAutomation.findItem(in: menu, title: "Copy") === top)
        #expect(DreamderAutomation.findItem(in: menu, title: "Open With") === parent)
        #expect(DreamderAutomation.findItem(in: menu, title: "safari") == nil)
        #expect(DreamderAutomation.findItem(in: menu, title: "Paste") == nil)
    }

    @MainActor
    private final class ActionProbe: NSObject, NSApplicationDelegate {
        private(set) var calls = 0

        @objc func dreamderAutomationProbe(_ sender: Any?) {
            calls += 1
        }
    }

    private func makeInstalledCenter() -> NotificationCenter {
        let center = NotificationCenter()
        DreamderAutomation.install(center: center, enabled: true, queue: nil)
        return center
    }

    private func attachTextView(
        to harness: Harness,
        text: String = "hello\nworld\n",
        inside container: NSView? = nil,
        makeFirstResponder: Bool = true
    ) throws -> TextView {
        let window = try #require(harness.controller.window)
        let textView = TextView(string: text)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        if let container {
            container.addSubview(textView)
            window.contentView?.addSubview(container)
        } else {
            window.contentView?.addSubview(textView)
        }
        if makeFirstResponder {
            window.makeFirstResponder(textView)
        }
        harness.bringToFront()
        return textView
    }

    private func outputLines(_ name: String, in directory: URL) throws -> [String] {
        try output(name, in: directory).split(separator: "\n").map(String.init)
    }

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

    @Test
    func activeWindowControllerPrefersTheKeyWindowThenTheFrontMostController() throws {
        try withTempDir { first in
            try withTempDir { second in
                let firstHarness = try makeHarness(in: first, files: ["Alpha.swift"])
                defer { firstHarness.close() }
                let secondHarness = try makeHarness(in: second, files: ["Beta.swift"])
                defer { secondHarness.close() }
                let firstWindow = try #require(firstHarness.controller.window)
                let secondWindow = try #require(secondHarness.controller.window)
                let plain = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
                    styleMask: [.titled],
                    backing: .buffered,
                    defer: true
                )
                plain.isReleasedWhenClosed = false
                defer { plain.close() }

                let preferred = DreamderAutomation.activeWindowController(
                    keyWindow: secondWindow,
                    orderedWindows: [firstWindow]
                )
                #expect(preferred === secondHarness.controller)

                let fallback = DreamderAutomation.activeWindowController(
                    keyWindow: plain,
                    orderedWindows: [plain, firstWindow, secondWindow]
                )
                #expect(fallback === firstHarness.controller)

                let withoutKey = DreamderAutomation.activeWindowController(
                    keyWindow: nil,
                    orderedWindows: [secondWindow]
                )
                #expect(withoutKey === secondHarness.controller)

                #expect(DreamderAutomation.activeWindowController(keyWindow: plain, orderedWindows: [plain]) == nil)
                #expect(DreamderAutomation.activeWindowController(keyWindow: nil, orderedWindows: []) == nil)
            }
        }
    }

    @Test
    func contextMenuDumpReportsAWindowWithoutAnEditorTextView() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.bringToFront()
            let output = directory.appending(path: "no-editor")

            DreamderAutomation.writeContextMenu(to: output.path(percentEncoded: false))

            #expect(try self.output("contextmenu.txt", in: output) == "error: no editor text view\n")
        }
    }

    @Test
    func menuItemCommandReportsAWindowWithoutAnEditorMenu() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.bringToFront()
            let output = directory.appending(path: "no-editor-item")

            DreamderAutomation.performMenuItem(named: output.path(percentEncoded: false) + "|Copy")
            DreamderAutomation.performMenuItem(named: nil)

            #expect(try self.output("menuitem.txt", in: output) == "error: no editor menu\n")
        }
    }

    @Test
    func contextMenuDumpFindsATextViewThatIsNestedAndNotFirstResponder() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            let textView = try attachTextView(to: harness, inside: container, makeFirstResponder: false)
            defer { container.removeFromSuperview() }
            #expect(textView.window === harness.controller.window)
            let output = directory.appending(path: "nested-menu")

            DreamderAutomation.writeContextMenu(to: output.path(percentEncoded: false))

            #expect(try outputLines("contextmenu.txt", in: output).first == "class=TextView")
        }
    }

    @Test
    func contextMenuDumpListsControlClickItemsAndReportsMissingMenus() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let textView = try attachTextView(to: harness)
            defer { textView.removeFromSuperview() }
            EditorContextMenuInstaller.install()
            defer { EditorContextMenuInstaller.removeHandler(for: textView) }
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(NSMenuItem(title: "Probe", action: nil, keyEquivalent: ""))
            let present = directory.appending(path: "present")
            let absent = directory.appending(path: "absent")

            EditorContextMenuInstaller.setHandler({ _ in menu }, for: textView)
            DreamderAutomation.writeContextMenu(to: present.path(percentEncoded: false))
            let presentLines = try outputLines("contextmenu.txt", in: present)

            #expect(presentLines.contains("items=1"))
            #expect(presentLines.contains("controlClickItems=1"))
            #expect(presentLines.contains("keyDownFallback=<nil>"))
            #expect(presentLines.last == "Probe [enabled]")

            EditorContextMenuInstaller.setHandler({ _ in nil }, for: textView)
            DreamderAutomation.writeContextMenu(to: absent.path(percentEncoded: false))
            let absentLines = try outputLines("contextmenu.txt", in: absent)

            #expect(absentLines.contains("items=0"))
            #expect(absentLines.contains { $0.hasPrefix("controlClickItems") } == false)
            #expect(absentLines.last == "<nil menu>")
        }
    }

    @Test
    func menuItemCommandPerformsTheNamedItemAndReportsTheActiveTab() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            let textView = try attachTextView(to: harness)
            defer { textView.removeFromSuperview() }
            EditorContextMenuInstaller.install()
            defer { EditorContextMenuInstaller.removeHandler(for: textView) }
            let probe = ActionProbe()
            let menu = NSMenu()
            menu.autoenablesItems = false
            let actionItem = NSMenuItem(
                title: "Probe",
                action: #selector(ActionProbe.dreamderAutomationProbe(_:)),
                keyEquivalent: ""
            )
            actionItem.target = probe
            menu.addItem(actionItem)
            menu.addItem(NSMenuItem(title: "Inert", action: nil, keyEquivalent: ""))
            EditorContextMenuInstaller.setHandler({ _ in menu }, for: textView)
            let performed = directory.appending(path: "performed")
            let inert = directory.appending(path: "inert")

            DreamderAutomation.performMenuItem(named: performed.path(percentEncoded: false) + "|Probe")
            let performedLines = try outputLines("menuitem.txt", in: performed)

            #expect(probe.calls == 1)
            #expect(performedLines.first == "item=Probe enabled=true hasAction=true")
            #expect(performedLines.contains("handled=true"))
            #expect(performedLines.contains { $0.hasPrefix("tabURL=") && $0.hasSuffix("/One.swift") })
            #expect(performedLines.contains { $0.hasPrefix("root=") })
            #expect(performedLines.contains("relative=One.swift"))
            #expect(performedLines.contains { $0.hasPrefix("windows=") })
            #expect(performedLines.contains { $0.hasPrefix("window ") && $0.contains(" parent=") })

            DreamderAutomation.performMenuItem(named: inert.path(percentEncoded: false) + "|Inert")
            let inertLines = try outputLines("menuitem.txt", in: inert)

            #expect(probe.calls == 1)
            #expect(inertLines.first == "item=Inert enabled=true hasAction=false")
            #expect(inertLines.contains("handled=false"))
        }
    }

    @Test
    func annotateCommandReportsTheAnnotationViewOfTheEditorScrollView() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            try harness.openTab("One.swift")
            let tab = try #require(harness.manager.activeEditor.selectedTab)
            let window = try #require(harness.controller.window)
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            let textView = TextView(string: "hello\nworld\n")
            textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            scrollView.documentView = textView
            scrollView.addSubview(GitBlameAnnotationView(textView: textView))
            window.contentView?.addSubview(scrollView)
            defer { scrollView.removeFromSuperview() }
            window.makeFirstResponder(textView)
            harness.bringToFront()
            let coordinator = GitBlameCoordinator(editorInstance: tab, codeFile: CodeFileDocument())
            let output = directory.appending(path: "annotation")

            withExtendedLifetime(coordinator) {
                DreamderAutomation.toggleAnnotate(to: output.path(percentEncoded: false))
            }

            let lines = try outputLines("annotate.txt", in: output)
            #expect(lines.first == "annotating=true")
            #expect(lines.contains { $0.hasPrefix("annotationView=") && $0.hasSuffix("hidden=false") })
            #expect(lines.contains { $0.hasPrefix("textInsets=") })
            #expect(lines.contains { $0.hasPrefix("hitInside=") && $0.contains(" hitOutside=") })
        }
    }

    @Test
    func performStopsAtTheResponderThatHandlesTheAction() {
        let probe = ActionProbe()
        let previous = NSApp.delegate
        NSApp.delegate = probe
        defer { NSApp.delegate = previous }

        DreamderAutomation.perform(actionNamed: "dreamderAutomationProbe:")

        #expect(probe.calls == 1)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    @Test
    func snapshotUsesTheWindowServerImageWhenOneIsAvailable() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            harness.bringToFront()
            let provided = try makeImage(width: 64, height: 32)
            var requested: [NSWindow] = []
            let output = directory.appending(path: "provided-shots")

            DreamderAutomation.snapshot(
                to: output.path(percentEncoded: false),
                windowImage: { window in
                    requested.append(window)
                    return provided
                }
            )

            #expect(requested.contains { $0 === window })
            let manifest = try outputLines("windows.txt", in: output)
            let manifestIndex = try #require(manifest.indices.dropFirst().first {
                manifest[$0].hasPrefix("\(window.windowNumber) ")
            })
            let picture = try Data(contentsOf: output.appending(path: "window-\(manifestIndex - 1).png"))
            let representation = try #require(NSBitmapImageRep(data: picture))
            #expect(representation.pixelsWide == 64)
        }
    }
}
