import AppKit
import CodeEditTextView

private struct EditorMenuContext {
    let window: NSWindow
    let textView: TextView
    let menu: NSMenu?
}

extension DreamderAutomation {
    private static func editorMenu() -> EditorMenuContext? {
        guard let window = activeWindowController()?.window, let textView = editorTextView() else { return nil }
        return EditorMenuContext(
            window: window,
            textView: textView,
            menu: rightMouseMenu(window: window, textView: textView)
        )
    }

    static func writeContextMenu(to path: String?) {
        let directory = URL(fileURLWithPath: path ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("contextmenu.txt")

        guard let context = editorMenu() else {
            try? "error: no editor text view\n".write(to: output, atomically: true, encoding: .utf8)
            return
        }

        let window = context.window
        let textView = context.textView
        let menu = context.menu
        var lines = ["class=\(type(of: textView))", "items=\(menu?.items.count ?? 0)"]
        if let controlClickItems = controlClickMenu(window: window, textView: textView)?.items.count {
            lines.append("controlClickItems=\(controlClickItems)")
        }
        lines.append("keyDownFallback=\(menuPresence(keyDownMenu(window: window, textView: textView)))")
        if let selectionStates = selectionStates(textView: textView, caretOffset: caretOffset(textView: textView)) {
            lines.append("onSelection=\(selectionStates)")
        }
        if let menu {
            lines.append(contentsOf: describe(menu: menu, level: 0))
        } else {
            lines.append("<nil menu>")
        }
        try? lines.joined(separator: "\n").appending("\n").write(to: output, atomically: true, encoding: .utf8)
    }

    static func menuPresence(_ menu: NSMenu?) -> String {
        menu == nil ? "<nil>" : "menu"
    }

    private static func controlClickMenu(window: NSWindow, textView: TextView) -> NSMenu? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: caretPoint(textView: textView, offset: caretOffset(textView: textView)),
            modifierFlags: .control,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ).flatMap { textView.menu(for: $0) }
    }

    private static func keyDownMenu(window: NSWindow, textView: TextView) -> NSMenu? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: caretPoint(textView: textView, offset: caretOffset(textView: textView)),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ).flatMap { textView.menu(for: $0) }
    }

    static func selectionStates(textView: TextView, caretOffset offset: Int) -> String? {
        guard let line = textView.layoutManager?.textLineForOffset(offset),
              let selectionManager = textView.selectionManager else { return nil }
        let previous = selectionManager.textSelections.map(\.range)
        let range = NSRange(location: line.range.location, length: line.range.upperBound - line.range.location)
        selectionManager.setSelectedRange(range)
        let applied = selectionManager.textSelections.map(\.range)
        let menu = editorMenu()?.menu
        let titles = ["Cut", "Copy", "Paste"]
        let states = titles.map { title in
            let item = menu?.items.first { $0.title == title }
            return "\(title)=\(item?.isEnabled == true ? "enabled" : "disabled")"
        }
        let restore = previous.isEmpty
            ? applied.prefix(1).map { NSRange(location: $0.location, length: 0) }
            : previous
        selectionManager.setSelectedRanges(restore)
        let prefix = "applied=\(applied) menuItems=\(menu?.items.count ?? -1)"
        return "\(prefix) \(states.joined(separator: " "))"
    }

    static func performMenuItem(named name: String?) {
        guard let name else { return }
        let parts = name.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let directory = URL(fileURLWithPath: parts.count == 2 ? String(parts[0]) : NSTemporaryDirectory())
        let title = parts.count == 2 ? String(parts[1]) : name
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("menuitem.txt")

        guard let menu = editorMenu()?.menu else {
            try? "error: no editor menu\n".write(to: output, atomically: true, encoding: .utf8)
            return
        }
        guard let item = findItem(in: menu, title: title) else {
            try? "error: menu item \(title) not found\n".write(to: output, atomically: true, encoding: .utf8)
            return
        }

        var lines = ["item=\(item.title) enabled=\(item.isEnabled) hasAction=\(item.action != nil)"]
        if let action = item.action {
            lines.append("handled=\(NSApp.sendAction(action, to: item.target, from: item))")
        } else {
            lines.append("handled=false")
        }
        if let workspace = activeWindowController()?.workspace,
           let tab = workspace.editorManager?.activeEditor.selectedTab,
           let root = workspace.sourceControlManager?.workspaceURL {
            let target = tab.file.url.absoluteURL.standardizedFileURL.path(percentEncoded: false)
            let base = root.absoluteURL.standardizedFileURL.path(percentEncoded: false)
            lines.append("tabURL=\(target)")
            lines.append("root=\(base)")
            lines.append("relative=\(DiffPath.relativePath(of: tab.file.url, from: root))")
        }
        let windows = NSApp.windows.filter { $0.isVisible }
        lines.append("windows=\(windows.count)")
        for window in windows {
            let parent = window.parent.map { String(describing: type(of: $0)) } ?? "nil"
            let frame = NSStringFromRect(window.frame)
            lines.append("window \(type(of: window)) \(frame) parent=\(parent) title=\(window.title)")
        }
        try? lines.joined(separator: "\n").appending("\n").write(to: output, atomically: true, encoding: .utf8)
    }

    static func findItem(in menu: NSMenu, title: String) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title {
                return item
            }
            if let submenu = item.submenu, let found = findItem(in: submenu, title: title) {
                return found
            }
        }
        return nil
    }

    private static func caretOffset(textView: TextView) -> Int {
        textView.selectionManager?.textSelections.first?.range.location ?? 0
    }

    static func caretPoint(textView: TextView, offset: Int) -> NSPoint {
        let caret = textView.layoutManager?.rectForOffset(offset) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return textView.convert(CGPoint(x: caret.midX, y: caret.midY), to: nil)
    }

    private static func rightMouseMenu(window: NSWindow, textView: TextView) -> NSMenu? {
        NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: caretPoint(textView: textView, offset: caretOffset(textView: textView)),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ).flatMap { textView.menu(for: $0) }
    }

    static func describe(menu: NSMenu, level: Int) -> [String] {
        let indent = String(repeating: "  ", count: level)
        var lines: [String] = []
        for item in menu.items {
            if item.isSeparatorItem {
                lines.append("\(indent)---")
                continue
            }
            let state = item.isEnabled ? "enabled" : "disabled"
            lines.append("\(indent)\(item.title) [\(state)]\(keyEquivalentDescription(item))")
            if let submenu = item.submenu {
                lines.append(contentsOf: describe(menu: submenu, level: level + 1))
            }
        }
        return lines
    }

    private static func keyEquivalentDescription(_ item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let key = functionKeyName(item.keyEquivalent) ?? item.keyEquivalent.uppercased()
        return " \(modifierDescription(item.keyEquivalentModifierMask))\(key)"
    }

    private static func functionKeyName(_ keyEquivalent: String) -> String? {
        guard keyEquivalent.unicodeScalars.count == 1,
              let scalar = keyEquivalent.unicodeScalars.first else { return nil }
        let names: [Int: String] = [
            NSF1FunctionKey: "F1", NSF2FunctionKey: "F2", NSF3FunctionKey: "F3",
            NSF4FunctionKey: "F4", NSF5FunctionKey: "F5", NSF6FunctionKey: "F6",
            NSF7FunctionKey: "F7", NSF8FunctionKey: "F8", NSF9FunctionKey: "F9",
            NSF10FunctionKey: "F10", NSF11FunctionKey: "F11", NSF12FunctionKey: "F12"
        ]
        return names[Int(scalar.value)]
    }

    private static func modifierDescription(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) {
            result += "⌃"
        }
        if flags.contains(.option) {
            result += "⌥"
        }
        if flags.contains(.shift) {
            result += "⇧"
        }
        if flags.contains(.command) {
            result += "⌘"
        }
        return result
    }
}
