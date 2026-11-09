import AppKit
import Foundation
import Testing
@testable import Dreamder

enum ProjectNavigatorHarnessError: Error {
    case missingState(String)
    case missingFile(String)
    case missingMenuItem(String)
}

struct ProjectNavigatorDrop {
    let urls: [URL]
    let sourceOperationMask: NSDragOperation
}

@MainActor
final class ProjectNavigatorControllerHarness {
    let root: URL
    let trashDirectory: URL
    let workspace: WorkspaceDocument
    let fileManager: CEWorkspaceFileManager
    let editor: Editor
    let controller: ProjectNavigatorViewController
    let window: NSWindow
    let outlineView: ProjectNavigatorNSOutlineView
    let menu: ProjectNavigatorMenu
    let pasteboard: InMemoryPasteboard
    let sortDefaultsSuite: String
    private let sortDefaults: UserDefaults
    let settings: Dreamder.Settings
    private let settingsDirectory: URL
    private var lockedDirectories: [URL] = []
    private var reloader: ProjectNavigatorHarnessReloader?

    static func run(
        folders: [String] = [],
        files: [String] = [],
        windowHeight: CGFloat = 600,
        loadsTree: Bool = false,
        reloadsOnFileEvents: Bool = false,
        _ body: @MainActor (ProjectNavigatorControllerHarness) async throws -> Void
    ) async throws {
        try await withTempDir { directory in
            let trash = try makeTemporaryDirectory(label: "ProjectNavigatorTrash")
            defer { removeTemporaryDirectory(trash) }
            for folder in folders {
                try FileManager.default.createDirectory(
                    at: directory.appending(path: folder),
                    withIntermediateDirectories: true
                )
            }
            for file in files {
                let url = directory.appending(path: file)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try "content of \(file)\n".write(to: url, atomically: true, encoding: .utf8)
            }
            let harness = try ProjectNavigatorControllerHarness(
                root: directory,
                trashDirectory: trash,
                windowHeight: windowHeight
            )
            defer { harness.close() }
            if loadsTree {
                await harness.loadTree()
            }
            if reloadsOnFileEvents {
                harness.observeFileEvents()
            }
            try await body(harness)
        }
    }

    init(root directory: URL, trashDirectory: URL, windowHeight: CGFloat) throws {
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        guard let previous = workspace.workspaceFileManager,
              let editorManager = workspace.editorManager else {
            throw ProjectNavigatorHarnessError.missingState("workspace")
        }
        let manager = CEWorkspaceFileManager(
            folderUrl: previous.folderUrl,
            ignoredFilesAndFolders: previous.ignoredFilesAndFolders,
            fileManager: ProjectNavigatorTrashingFileManager(trashDirectory: trashDirectory),
            sourceControlManager: workspace.sourceControlManager
        )
        previous.cleanUp()
        workspace.workspaceFileManager = manager
        workspace.sourceControlManager?.fileManager = manager

        let editor = editorManager.activeEditor
        editor.workspace = workspace

        let controller = ProjectNavigatorViewController()
        controller.workspace = workspace
        controller.editor = editor
        controller.autosavesExpandedItems = false
        let settingsDirectory = try makeTemporaryDirectory(label: "ProjectNavigatorSettings")
        let settings = Dreamder.Settings(baseURL: settingsDirectory)
        controller.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: windowHeight),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 320, height: windowHeight))
        window.orderFront(nil)
        controller.view.layoutSubtreeIfNeeded()

        guard let outlineView = controller.outlineView as? ProjectNavigatorNSOutlineView,
              let menu = outlineView.menu as? ProjectNavigatorMenu else {
            throw ProjectNavigatorHarnessError.missingState("outline view")
        }
        let pasteboard = InMemoryPasteboard()
        controller.pasteboard = pasteboard
        let sortDefaults = try makeIsolatedDefaults()
        controller.sortModes = ProjectNavigatorSortModes(
            rootURL: previous.folderUrl,
            defaults: sortDefaults.defaults
        )

        self.root = previous.folderUrl
        self.trashDirectory = trashDirectory
        self.workspace = workspace
        self.fileManager = manager
        self.editor = editor
        self.controller = controller
        self.window = window
        self.outlineView = outlineView
        self.menu = menu
        self.pasteboard = pasteboard
        self.sortDefaultsSuite = sortDefaults.suiteName
        self.sortDefaults = sortDefaults.defaults
        self.settings = settings
        self.settingsDirectory = settingsDirectory
    }

    func close() {
        for directory in lockedDirectories {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        }
        lockedDirectories.removeAll()
        window.contentViewController = nil
        window.close()
        removeIsolatedDefaults(sortDefaults, suiteName: sortDefaultsSuite)
        removeTemporaryDirectory(settingsDirectory)
        workspace.close()
    }

    func url(_ relativePath: String) -> URL {
        root.appending(path: relativePath)
    }

    func file(_ relativePath: String) throws -> CEWorkspaceFile {
        guard let file = fileManager.getFile(url(relativePath).path, createIfNotFound: true) else {
            throw ProjectNavigatorHarnessError.missingFile(relativePath)
        }
        return file
    }

    var rootFile: CEWorkspaceFile {
        fileManager.workspaceItem
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relativePath).path)
    }

    func contents(_ relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    func write(_ relativePath: String, _ text: String = "x\n") throws {
        let target = url(relativePath)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: target, atomically: true, encoding: .utf8)
    }

    func makeDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(at: url(relativePath), withIntermediateDirectories: true)
    }

    func remove(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: url(relativePath))
    }

    func lock(_ relativePath: String, permissions: Int = 0o555) throws {
        let directory = url(relativePath)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
        lockedDirectories.append(directory)
    }

    func names(in relativePath: String) throws -> [String] {
        let directory = relativePath.isEmpty ? root : url(relativePath)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func reload() {
        outlineView.reloadData()
        controller.view.layoutSubtreeIfNeeded()
    }

    func settleOutline() async throws {
        controller.view.layoutSubtreeIfNeeded()
        outlineView.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        controller.view.layoutSubtreeIfNeeded()
    }

    func observeFileEvents() {
        let observer = ProjectNavigatorHarnessReloader(controller: controller)
        fileManager.addObserver(observer)
        reloader = observer
    }

    func loadTree() async {
        var pending = [rootFile]
        while let folder = pending.popLast() {
            await fileManager.loadChildren(of: folder)
            let children = (fileManager.childrenMap[folder.id] ?? []).compactMap { fileManager.flattenedFileItems[$0] }
            pending.append(contentsOf: children.filter(\.isFolder))
        }
        reload()
        outlineView.expandItem(rootFile)
    }

    func expand(_ relativePath: String) throws {
        outlineView.expandItem(try file(relativePath))
        controller.view.layoutSubtreeIfNeeded()
    }

    func row(of file: CEWorkspaceFile) -> Int {
        outlineView.row(forItem: file)
    }

    func select(_ files: [CEWorkspaceFile]) {
        let rows = IndexSet(files.map { outlineView.row(forItem: $0) }.filter { $0 >= 0 })
        controller.shouldSendSelectionUpdate = false
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
        controller.shouldSendSelectionUpdate = true
    }

    func click(_ file: CEWorkspaceFile?) {
        outlineView.clickedRowOverride = file.map { outlineView.row(forItem: $0) }
    }

    func buildMenu(clicking file: CEWorkspaceFile?) -> ProjectNavigatorMenu {
        click(file)
        controller.menuNeedsUpdate(menu)
        return menu
    }

    func cell(for file: CEWorkspaceFile) -> ProjectNavigatorTableViewCell? {
        let row = outlineView.row(forItem: file)
        guard row >= 0 else { return nil }
        return outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ProjectNavigatorTableViewCell
    }

    func menuItem(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title {
                return item
            }
            if let submenu = item.submenu, let nested = menuItem(titled: title, in: submenu) {
                return nested
            }
        }
        return nil
    }

    func titles(of menu: NSMenu) -> [String] {
        menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    }

    @discardableResult
    func perform(_ title: String, in menu: NSMenu) throws -> Bool {
        guard let item = menuItem(titled: title, in: menu), let action = item.action else {
            throw ProjectNavigatorHarnessError.missingMenuItem(title)
        }
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    func dropInfo(urls: [URL], mask: NSDragOperation = .move) -> ProjectNavigatorDrop {
        ProjectNavigatorDrop(urls: urls, sourceOperationMask: mask)
    }

    func acceptDrop(_ drop: ProjectNavigatorDrop, onto item: Any?) -> Bool {
        controller.acceptDrop(of: drop.urls, sourceOperationMask: drop.sourceOperationMask, onto: item)
    }

    func dropOperation(
        for drop: ProjectNavigatorDrop,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        controller.dropOperation(
            in: outlineView,
            proposedItem: item,
            proposedChildIndex: index,
            sourceOperationMask: drop.sourceOperationMask
        )
    }

    func childNames(of item: CEWorkspaceFile?) -> [String] {
        let count = controller.outlineView(outlineView, numberOfChildrenOfItem: item)
        return (0..<count).compactMap {
            (controller.outlineView(outlineView, child: $0, ofItem: item) as? CEWorkspaceFile)?.name
        }
    }

    var placeholderCell: ProjectNavigatorTableViewCell? {
        guard let placeholder = controller.pendingCreation?.placeholder else { return nil }
        return cell(for: placeholder)
    }

    @discardableResult
    func submitCreation(_ name: String) throws -> Bool {
        let cell = try #require(placeholderCell)
        let field = try #require(cell.textField)
        field.stringValue = name
        return cell.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
    }

    @discardableResult
    func cancelCreationWithEscape() throws -> Bool {
        let cell = try #require(placeholderCell)
        let field = try #require(cell.textField)
        return cell.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:)))
    }

    func blurCreation(with name: String) throws {
        let cell = try #require(placeholderCell)
        cell.textField?.stringValue = name
        cell.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    }

    func writeClipboard(_ files: [String], cut: Bool) {
        ProjectNavigatorClipboard(pasteboard: pasteboard).write(files.map { url($0) }, isCut: cut)
    }

    func pasteAndWait(into folder: CEWorkspaceFile) async {
        await controller.paste(into: folder)
    }
}

@MainActor
final class ProjectNavigatorHarnessReloader: CEWorkspaceFileManagerObserver {
    private weak var controller: ProjectNavigatorViewController?

    init(controller: ProjectNavigatorViewController) {
        self.controller = controller
    }

    func fileManagerUpdated(updatedItems: Set<CEWorkspaceFile>) {
        guard let controller else { return }
        for item in updatedItems {
            controller.outlineView.reloadItem(item, reloadChildren: true)
        }
        controller.revealPendingItem()
    }
}

@MainActor
struct ProjectNavigatorWeakController {
    weak var controller: ProjectNavigatorViewController?
}
