import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension DreamderAutomationTests {
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
}
