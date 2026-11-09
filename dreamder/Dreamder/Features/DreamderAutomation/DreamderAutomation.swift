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

    static func editorTextView(controller: DreamderWindowController? = activeWindowController()) -> TextView? {
        guard let window = controller?.window else { return nil }
        if let responder = window.firstResponder as? TextView {
            return responder
        }
        return window.contentView.flatMap { firstTextView(in: $0) }
    }

    private static func firstTextView(in view: NSView) -> TextView? {
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
            let insideHit = typeName(of: annotation.hitTest(inside))
            let outsideHit = typeName(of: annotation.hitTest(outside))
            lines.append("hitInside=\(insideHit) hitOutside=\(outsideHit)")
        }
        try? lines.joined(separator: "\n").appending("\n").write(to: output, atomically: true, encoding: .utf8)
    }

    private static func typeName(of view: NSView?) -> String {
        view.map { String(describing: type(of: $0)) } ?? "nil"
    }

    static func showToolWindow(
        named name: String?,
        in controller: DreamderWindowController? = activeWindowController()
    ) {
        guard let name, let manager = controller?.workspace?.toolWindowManager else { return }
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard let id = ToolWindowID(rawValue: parts.last ?? name) else { return }
        switch parts.count == 2 ? parts[0] : "show" {
        case "hide": manager.hide(id)
        case "toggle": manager.toggle(id)
        default: manager.show(id)
        }
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
        let window = activeWindowController()?.window
        window?.makeKey()
        if NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }
        if let controller = window?.windowController, controller.responds(to: selector) {
            NSApp.sendAction(selector, to: controller, from: nil)
        }
    }
}
