import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension DreamderAutomationTests {
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
}
