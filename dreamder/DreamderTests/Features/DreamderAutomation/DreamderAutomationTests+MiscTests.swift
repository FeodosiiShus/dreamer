import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension DreamderAutomationTests {
    @Test
    func captureMethodNamesTheWindowServerOrInProcessRendering() {
        #expect(DreamderAutomation.captureMethod(windowServerAvailable: true) == "capture=window-server")
        #expect(DreamderAutomation.captureMethod(windowServerAvailable: false) == "capture=in-process")
    }

    @Test
    func windowServerSymbolResolutionFailsForUnknownSymbols() {
        #expect(DreamderAutomation.resolveWindowListCreateImage(symbol: "dreamderNoSuchWindowServerSymbol") == nil)
        #expect(DreamderAutomation.resolveWindowListCreateImage(symbol: "getpid") != nil)
    }

    @Test
    func contextMenuDumpWithoutADirectoryWritesIntoTheTemporaryDirectory() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let textView = try attachTextView(to: harness)
            defer { textView.removeFromSuperview() }
            removeTemporaryFile("contextmenu.txt")
            defer { removeTemporaryFile("contextmenu.txt") }

            DreamderAutomation.writeContextMenu(to: nil)

            #expect(try outputLines("contextmenu.txt", in: temporaryDirectory).first == "class=TextView")
        }
    }

    @Test
    func menuPresenceDistinguishesAMenuFromNone() {
        #expect(DreamderAutomation.menuPresence(NSMenu()) == "menu")
        #expect(DreamderAutomation.menuPresence(nil) == "<nil>")
    }

    @Test
    func caretHelpersFallBackWhenTheOffsetHasNoLine() {
        let textView = TextView(string: "hello\nworld\n")
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)

        #expect(DreamderAutomation.selectionStates(textView: textView, caretOffset: -1) == nil)
        #expect(
            DreamderAutomation.caretPoint(textView: textView, offset: -1)
                == textView.convert(CGPoint(x: 0.5, y: 0.5), to: nil)
        )
    }

    @Test
    func menuItemCommandWithoutADirectoryWritesIntoTheTemporaryDirectory() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let textView = try attachTextView(to: harness)
            defer { textView.removeFromSuperview() }
            removeTemporaryFile("menuitem.txt")
            defer { removeTemporaryFile("menuitem.txt") }

            DreamderAutomation.performMenuItem(named: "Nothing Here")

            #expect(
                try output("menuitem.txt", in: temporaryDirectory) == "error: menu item Nothing Here not found\n"
            )
        }
    }

    @Test
    func menuItemCommandListsVisibleChildWindowsWithTheirParent() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            let textView = try attachTextView(to: harness)
            defer { textView.removeFromSuperview() }
            EditorContextMenuInstaller.install()
            defer { EditorContextMenuInstaller.removeHandler(for: textView) }
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(NSMenuItem(title: "Inert", action: nil, keyEquivalent: ""))
            EditorContextMenuInstaller.setHandler({ _ in menu }, for: textView)
            let child = makeProbeWindow(width: 120, style: [.borderless])
            child.orderFront(nil)
            window.addChildWindow(child, ordered: .above)
            defer {
                window.removeChildWindow(child)
                child.close()
            }
            let output = directory.appending(path: "child-windows")

            DreamderAutomation.performMenuItem(named: output.path(percentEncoded: false) + "|Inert")

            let parentType = String(describing: type(of: window))
            let lines = try outputLines("menuitem.txt", in: output)
            #expect(lines.contains { $0.hasPrefix("window ") && $0.contains(" parent=\(parentType) ") })
        }
    }

    @Test
    func describeSpellsMultiCharacterKeyEquivalentsInUppercase() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "Chord", action: nil, keyEquivalent: "ab")
        item.keyEquivalentModifierMask = []
        menu.addItem(item)

        #expect(DreamderAutomation.describe(menu: menu, level: 0) == ["Chord [enabled] AB"])
    }

    @Test
    func showToolWindowHidesAndTogglesWithTheActionPrefix() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.bringToFront()

            DreamderAutomation.showToolWindow(named: "show:git", in: harness.controller)
            #expect(harness.workspace.toolWindowManager.isVisible(.git))

            DreamderAutomation.showToolWindow(named: "hide:git", in: harness.controller)
            #expect(harness.workspace.toolWindowManager.isVisible(.git) == false)

            DreamderAutomation.showToolWindow(named: "toggle:git", in: harness.controller)
            #expect(harness.workspace.toolWindowManager.isVisible(.git))

            DreamderAutomation.showToolWindow(named: "toggle:git", in: harness.controller)
            #expect(harness.workspace.toolWindowManager.isVisible(.git) == false)
        }
    }

    @Test
    func openSkipsWorkspacesWithoutAFileURLAndStillFindsTheOwningOne() throws {
        try withTempDir { directory in
            let detached = WorkspaceDocument()
            DreamderDocumentController.shared.addDocument(detached)
            defer { DreamderDocumentController.shared.removeDocument(detached) }
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            #expect(detached.fileURL == nil)

            DreamderAutomation.open(path: harness.path("One.swift"))

            #expect(harness.manager.activeEditor.selectedTab?.file.name == "One.swift")
        }
    }

    @Test
    func annotateWithoutADirectoryWritesIntoTheTemporaryDirectory() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            harness.bringToFront()
            removeTemporaryFile("annotate.txt")
            defer { removeTemporaryFile("annotate.txt") }

            DreamderAutomation.toggleAnnotate(to: nil)

            #expect(try output("annotate.txt", in: temporaryDirectory) == "error: no blame coordinator\n")
        }
    }

    @Test
    func annotateCommandReportsTheViewHitInsideAndOutsideTheAnnotationColumn() throws {
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
            let annotation = GitBlameAnnotationView(textView: textView)
            annotation.frame = scrollView.bounds
            scrollView.addSubview(annotation)
            window.contentView?.addSubview(scrollView)
            defer { scrollView.removeFromSuperview() }
            window.makeFirstResponder(textView)
            harness.bringToFront()
            let coordinator = GitBlameCoordinator(editorInstance: tab, codeFile: CodeFileDocument())
            let output = directory.appending(path: "annotation-hits")

            withExtendedLifetime(coordinator) {
                DreamderAutomation.toggleAnnotate(to: output.path(percentEncoded: false))
            }

            let lines = try outputLines("annotate.txt", in: output)
            #expect(lines.contains("hitInside=GitBlameAnnotationView hitOutside=nil"))
        }
    }

    @Test
    func editorTextViewIsNilWithoutAWindowController() {
        #expect(DreamderAutomation.editorTextView(controller: nil) == nil)
    }
}
