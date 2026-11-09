import AppKit
import CodeEditTextView

@MainActor
enum DreamderAutomation {
    static let snapshotNotification = Notification.Name("dev.dreamder.snapshot")
    static let openNotification = Notification.Name("dev.dreamder.open")
    static let actionNotification = Notification.Name("dev.dreamder.action")
    static let toolWindowNotification = Notification.Name("dev.dreamder.toolwindow")
    static let contextMenuNotification = Notification.Name("dev.dreamder.contextmenu")
    static let annotateNotification = Notification.Name("dev.dreamder.annotate")
    static let menuItemNotification = Notification.Name("dev.dreamder.menuitem")

    static func install(
        center: NotificationCenter = DistributedNotificationCenter.default(),
        enabled: Bool = DreamderHeadless.isEnabled,
        queue: OperationQueue? = .main
    ) {
        guard enabled else { return }
        let commands: [(name: Notification.Name, run: @MainActor (String?) -> Void)] = [
            (snapshotNotification, { snapshot(to: $0) }),
            (actionNotification, { perform(actionNamed: $0) }),
            (openNotification, { open(path: $0) }),
            (toolWindowNotification, { showToolWindow(named: $0) }),
            (contextMenuNotification, { writeContextMenu(to: $0) }),
            (annotateNotification, { toggleAnnotate(to: $0) }),
            (menuItemNotification, { performMenuItem(named: $0) })
        ]
        for command in commands {
            center.addObserver(forName: command.name, object: nil, queue: queue) { note in
                let argument = note.object as? String
                MainActor.assumeIsolated { command.run(argument) }
            }
        }
        MergeAutomation.install(center: center)
    }

    static func activeWindowController(
        keyWindow: NSWindow? = NSApp.keyWindow,
        orderedWindows: [NSWindow] = NSApp.orderedWindows
    ) -> DreamderWindowController? {
        if let controller = keyWindow?.windowController as? DreamderWindowController {
            return controller
        }
        return orderedWindows.lazy.compactMap { $0.windowController as? DreamderWindowController }.first
    }

    private static func editorTextView() -> TextView? {
        guard let window = activeWindowController()?.window else { return nil }
        if let responder = window.firstResponder as? TextView {
            return responder
        }
        return firstTextView(in: window.contentView)
    }

    private static func firstTextView(in view: NSView?) -> TextView? {
        guard let view else { return nil }
        if let textView = view as? TextView, textView.window != nil {
            return textView
        }
        for subview in view.subviews {
            if let found = firstTextView(in: subview) {
                return found
            }
        }
        return nil
    }

    private static func editorMenu() -> (textView: TextView, menu: NSMenu?)? {
        guard let window = activeWindowController()?.window, let textView = editorTextView() else { return nil }
        guard let event = rightMouseEvent(in: window, textView: textView) else { return (textView, nil) }
        return (textView, textView.menu(for: event))
    }

    static func writeContextMenu(to path: String?) {
        let directory = URL(fileURLWithPath: path ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("contextmenu.txt")

        guard let (textView, menu) = editorMenu() else {
            try? "error: no editor text view\n".write(to: output, atomically: true, encoding: .utf8)
            return
        }

        var lines = ["class=\(type(of: textView))", "items=\(menu?.items.count ?? 0)"]
        if let controlClickItems = controlClickMenu()?.items.count {
            lines.append("controlClickItems=\(controlClickItems)")
        }
        lines.append("keyDownFallback=\(keyDownMenu() == nil ? "<nil>" : "menu")")
        if let selectionStates = selectionStates(textView: textView) {
            lines.append("onSelection=\(selectionStates)")
        }
        if let menu {
            lines.append(contentsOf: describe(menu: menu, level: 0))
        } else {
            lines.append("<nil menu>")
        }
        try? lines.joined(separator: "\n").appending("\n").write(to: output, atomically: true, encoding: .utf8)
    }

    private static func controlClickMenu() -> NSMenu? {
        guard let window = activeWindowController()?.window,
              let textView = editorTextView(),
              let point = caretPoint(textView: textView),
              let event = NSEvent.mouseEvent(
                  with: .leftMouseDown,
                  location: point,
                  modifierFlags: .control,
                  timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: window.windowNumber,
                  context: nil,
                  eventNumber: 0,
                  clickCount: 1,
                  pressure: 1
              ) else { return nil }
        return textView.menu(for: event)
    }

    private static func keyDownMenu() -> NSMenu? {
        guard let window = activeWindowController()?.window,
              let textView = editorTextView(),
              let point = caretPoint(textView: textView),
              let event = NSEvent.keyEvent(
                  with: .keyDown,
                  location: point,
                  modifierFlags: [],
                  timestamp: ProcessInfo.processInfo.systemUptime,
                  windowNumber: window.windowNumber,
                  context: nil,
                  characters: "a",
                  charactersIgnoringModifiers: "a",
                  isARepeat: false,
                  keyCode: 0
              ) else { return nil }
        return textView.menu(for: event)
    }

    private static func selectionStates(textView: TextView) -> String? {
        guard let line = textView.layoutManager?.textLineForOffset(caretOffset(textView: textView)) else { return nil }
        let previous = textView.selectionManager?.textSelections.map(\.range) ?? []
        let range = NSRange(location: line.range.location, length: line.range.upperBound - line.range.location)
        textView.selectionManager?.setSelectedRange(range)
        let applied = textView.selectionManager?.textSelections.map(\.range) ?? []
        let menu = editorMenu()?.menu
        let titles = ["Cut", "Copy", "Paste"]
        let states = titles.map { title in
            let item = menu?.items.first { $0.title == title }
            return "\(title)=\(item?.isEnabled == true ? "enabled" : "disabled")"
        }
        let restore = previous.isEmpty
            ? [NSRange(location: applied.first?.location ?? 0, length: 0)]
            : previous
        textView.selectionManager?.setSelectedRanges(restore)
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
            lines.append("window \(type(of: window)) \(NSStringFromRect(window.frame)) parent=\(parent) title=\(window.title)")
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

    private static func caretPoint(textView: TextView) -> NSPoint? {
        let caret = textView.layoutManager?.rectForOffset(caretOffset(textView: textView))
            ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return textView.convert(CGPoint(x: caret.midX, y: caret.midY), to: nil)
    }

    private static func rightMouseEvent(in window: NSWindow, textView: TextView) -> NSEvent? {
        guard let point = caretPoint(textView: textView) else { return nil }
        return NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
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

    static func toggleAnnotate(to path: String?) {
        let directory = URL(fileURLWithPath: path ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("annotate.txt")

        guard let tab = activeWindowController()?.workspace?.editorManager?.activeEditor.selectedTab,
              let coordinator = GitBlameCoordinator.coordinator(for: tab) else {
            try? "error: no blame coordinator\n".write(to: output, atomically: true, encoding: .utf8)
            return
        }
        coordinator.toggleAnnotate()
        var lines = ["annotating=\(coordinator.isAnnotating)"]
        if let textView = editorTextView(), let scrollView = textView.enclosingScrollView,
           let annotation = scrollView.subviews.first(where: { $0 is GitBlameAnnotationView })
            as? GitBlameAnnotationView {
            lines.append("annotationView=\(NSStringFromRect(annotation.frame)) hidden=\(annotation.isHidden)")
            lines.append("textInsets=\(textView.textInsets.left)")
            let inside = NSPoint(x: textView.textInsets.left + 40, y: 40)
            let outside = NSPoint(x: textView.textInsets.left + GitBlameAnnotationView.columnWidth + 80, y: 40)
            let insideHit = annotation.hitTest(inside).map { String(describing: type(of: $0)) } ?? "nil"
            let outsideHit = annotation.hitTest(outside).map { String(describing: type(of: $0)) } ?? "nil"
            lines.append("hitInside=\(insideHit) hitOutside=\(outsideHit)")
        }
        try? lines.joined(separator: "\n").appending("\n").write(to: output, atomically: true, encoding: .utf8)
    }

    static func showToolWindow(
        named name: String?,
        in controller: DreamderWindowController? = activeWindowController()
    ) {
        guard let name, let id = ToolWindowID(rawValue: name) else { return }
        controller?.workspace?.toolWindowManager.show(id)
    }

    static func open(path: String?) {
        guard let path else { return }
        let parts = path.split(separator: ":", omittingEmptySubsequences: false)
        let location = parts.count >= 3 ? (Int(parts[parts.count - 2]), Int(parts[parts.count - 1])) : (nil, nil)
        let filePath = location.0 != nil && location.1 != nil ? parts.dropLast(2).joined(separator: ":") : path
        let target = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
        let workspaces = DreamderDocumentController.shared.documents.compactMap { $0 as? WorkspaceDocument }
        for workspace in workspaces {
            guard let rootURL = workspace.fileURL else { continue }
            let resolvedRoot = rootURL.resolvingSymlinksInPath().path
            guard target.hasPrefix(resolvedRoot + "/") else { continue }
            let workspacePath = rootURL.path + target.dropFirst(resolvedRoot.count)
            NSApp.activate(ignoringOtherApps: true)
            workspace.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            if let line = location.0, let column = location.1 {
                EditorLocationNavigation.open(
                    fileURL: URL(fileURLWithPath: workspacePath),
                    line: line,
                    column: column,
                    workspace: workspace
                )
            } else if let file = workspace.workspaceFileManager?.getFile(workspacePath, createIfNotFound: true) {
                workspace.editorManager?.openTab(item: file)
            }
            return
        }
    }

    static func perform(actionNamed name: String?) {
        guard let name else { return }
        NSApp.activate(ignoringOtherApps: true)
        let selector = NSSelectorFromString(name)
        let window = NSApp.keyWindow?.windowController is DreamderWindowController
            ? NSApp.keyWindow
            : NSApp.orderedWindows.first { $0.windowController is DreamderWindowController }
        window?.makeKey()
        if NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }
        if let controller = window?.windowController, controller.responds(to: selector) {
            NSApp.sendAction(selector, to: controller, from: nil)
        }
    }

    static func snapshot(
        to path: String?,
        windowImage: @MainActor (NSWindow) -> CGImage? = DreamderAutomation.windowServerImage(of:)
    ) {
        let directory = URL(fileURLWithPath: path ?? NSTemporaryDirectory())
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let windows = NSApp.orderedWindows.filter { $0.isVisible && $0.frame.width > 300 && $0.parent == nil }
        for (index, window) in windows.enumerated() {
            guard let image = capture(window, windowImage: windowImage) else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            let url = directory.appendingPathComponent("window-\(index).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        let method = windowListCreateImage != nil ? "capture=window-server" : "capture=in-process"
        let manifest = [method] + windows.map {
            "\($0.windowNumber) \(type(of: $0)) \(NSStringFromRect($0.frame)) \($0.title)"
        }
        try? manifest.joined(separator: "\n").write(
            to: directory.appendingPathComponent("windows.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func capture(_ window: NSWindow, windowImage: @MainActor (NSWindow) -> CGImage?) -> CGImage? {
        guard let base = render(window, windowImage: windowImage), window.frame.width > 0 else { return nil }
        let layers = [window] + descendants(of: window)
        let union = layers.map(\.frame).reduce(window.frame) { $0.union($1) }
        let scale = CGFloat(base.width) / window.frame.width
        guard let context = CGContext(
            data: nil,
            width: Int((union.width * scale).rounded()),
            height: Int((union.height * scale).rounded()),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return base }
        for layer in layers {
            let image = layer === window ? base : render(layer, windowImage: windowImage)
            guard let image else { continue }
            context.draw(
                image,
                in: CGRect(
                    x: (layer.frame.minX - union.minX) * scale,
                    y: (layer.frame.minY - union.minY) * scale,
                    width: layer.frame.width * scale,
                    height: layer.frame.height * scale
                )
            )
        }
        return context.makeImage()
    }

    private typealias WindowListCreateImage = @convention(c) (
        CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption
    ) -> Unmanaged<CGImage>?

    private static let windowListCreateImage: WindowListCreateImage? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: WindowListCreateImage.self)
    }()

    static func windowServerImage(of window: NSWindow) -> CGImage? {
        windowListCreateImage?(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.bestResolution, .boundsIgnoreFraming]
        )?.takeRetainedValue()
    }

    private static func render(_ window: NSWindow, windowImage: @MainActor (NSWindow) -> CGImage?) -> CGImage? {
        if let image = windowImage(window) {
            return image
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private static func descendants(of window: NSWindow) -> [NSWindow] {
        (window.childWindows ?? [])
            .filter(\.isVisible)
            .flatMap { [$0] + descendants(of: $0) }
    }
}
