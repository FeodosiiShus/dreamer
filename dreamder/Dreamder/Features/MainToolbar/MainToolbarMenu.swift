import AppKit
import SwiftUI

final class MainToolbarMenuAnchor {
    weak var view: NSView?
}

struct MainToolbarMenuAnchorView: NSViewRepresentable {
    let anchor: MainToolbarMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = MainToolbarMenuAnchorNSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

private final class MainToolbarMenuAnchorNSView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

extension MainToolbarMenuAnchor {
    func present(_ menu: NSMenu) {
        guard let view = view else { return }
        _ = menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: view.bounds.height + Islands.islandGap),
            in: view
        )
    }
}

final class MainToolbarTaskSelection: NSObject {
    let taskManager: TaskManager
    let taskID: UUID

    init(taskManager: TaskManager, taskID: UUID) {
        self.taskManager = taskManager
        self.taskID = taskID
    }
}

@MainActor
final class MainToolbarMenuActions: NSObject {
    static let shared = MainToolbarMenuActions()

    private let recentProjectsMenu = RecentProjectsMenu()

    func projectMenu(window: NSWindow?) -> NSMenu {
        let menu = NSMenu(title: "Project")

        let open = NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recent.submenu = recentProjectsMenu.makeMenu()
        menu.addItem(recent)

        menu.addItem(.separator())

        let close = NSMenuItem(title: "Close Project", action: #selector(closeProject(_:)), keyEquivalent: "")
        close.target = self
        close.representedObject = window
        menu.addItem(close)

        return menu
    }

    func settingsMenu() -> NSMenu {
        let menu = NSMenu(title: "Settings")

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let palette = NSMenuItem(
            title: "Command Palette",
            action: #selector(openCommandPalette(_:)),
            keyEquivalent: ""
        )
        palette.target = self
        menu.addItem(palette)

        return menu
    }

    func taskMenu(taskManager: TaskManager) -> NSMenu {
        let menu = NSMenu(title: "Run Configuration")

        for task in taskManager.availableTasks {
            let item = NSMenuItem(
                title: task.name.isEmpty ? "Untitled Task" : task.name,
                action: #selector(selectTask(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = MainToolbarTaskSelection(taskManager: taskManager, taskID: task.id)
            item.state = task.id == taskManager.selectedTaskID ? .on : .off
            menu.addItem(item)
        }

        if !taskManager.availableTasks.isEmpty {
            menu.addItem(.separator())
        }

        let edit = NSMenuItem(
            title: "Edit Configurations…",
            action: #selector(openWorkspaceSettings(_:)),
            keyEquivalent: ""
        )
        edit.target = self
        menu.addItem(edit)

        return menu
    }

    @objc private func openDocument(_ sender: Any?) {
        NSDocumentController.shared.openDocument(nil)
    }

    @objc private func closeProject(_ sender: Any?) {
        guard let window = (sender as? NSMenuItem)?.representedObject as? NSWindow else { return }
        NSApp.sendAction(#selector(NSWindow.performClose(_:)), to: window, from: nil)
    }

    @objc private func selectTask(_ sender: Any?) {
        guard let selection = (sender as? NSMenuItem)?.representedObject as? MainToolbarTaskSelection else {
            return
        }
        selection.taskManager.selectedTaskID = selection.taskID
    }

    @objc private func openSettings(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.openWindow(sceneID: .settings)
    }

    @objc private func openWorkspaceSettings(_ sender: Any?) {
        NSApp.sendAction(#selector(DreamderWindowController.openWorkspaceSettings(_:)), to: nil, from: nil)
    }

    @objc private func openCommandPalette(_ sender: Any?) {
        NSApp.sendAction(#selector(DreamderWindowController.openCommandPalette(_:)), to: nil, from: nil)
    }
}
