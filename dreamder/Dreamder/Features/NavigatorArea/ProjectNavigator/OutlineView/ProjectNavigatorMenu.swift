//
//  OutlineMenu.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 07.04.22.
//

import SwiftUI
import UniformTypeIdentifiers

/// A subclass of `NSMenu` implementing the contextual menu for the project navigator
final class ProjectNavigatorMenu: NSMenu {

    /// The item to show the contextual menu for
    var item: CEWorkspaceFile?

    /// The workspace, for opening the item
    var workspace: WorkspaceDocument?

    /// The  `ProjectNavigatorViewController` is being called from.
    /// By sending it, we can access it's variables and functions.
    weak var sender: ProjectNavigatorViewController?

    var confirmsDeletion = true

    var opensExternally: @MainActor (CEWorkspaceFile) -> Bool

    var blameRetry: Task<Void, Never>?

    init(_ sender: ProjectNavigatorViewController) {
        self.sender = sender
        self.opensExternally = { $0.openWithExternalEditor() }
        super.init(title: "Options")
        autoenablesItems = false
    }

    @available(*, unavailable)
    nonisolated override init(title: String) {
        opensExternally = { _ in false }
        super.init(title: title)
    }

    @available(*, unavailable)
    nonisolated required init(coder: NSCoder) {
        opensExternally = { _ in false }
        super.init(coder: coder)
    }

    /// Updates the menu for the selected item and hides it if no item is provided.
    func rebuild() {
        removeAllItems()
        setupMenu()
        disableInactiveItems(in: self)
    }

    /// Creates a `NSMenuItem` depending on the given arguments
    /// - Parameters:
    ///   - title: The title of the menu item
    ///   - action: A `Selector` or `nil` of the action to perform.
    ///   - key: A `keyEquivalent` of the menu item. Defaults to an empty `String`
    ///   - enabled: Whether the item can be performed.
    /// - Returns: A `NSMenuItem` which has the target `self`
    private func menuItem(
        _ title: String,
        action: Selector?,
        key: String = "",
        enabled: Bool = true
    ) -> NSMenuItem {
        let mItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mItem.target = self
        mItem.isEnabled = enabled

        return mItem
    }

    private func disableInactiveItems(in menu: NSMenu) {
        for entry in menu.items where !entry.isSeparatorItem {
            if let submenu = entry.submenu {
                disableInactiveItems(in: submenu)
            } else if entry.action == nil {
                entry.isEnabled = false
            }
        }
    }

    /// Configures the menu based on the current selection in the outline view.
    /// - Menu items get added depending on the amount of selected items.
    private func setupMenu() { // swiftlint:disable:this function_body_length
        guard let item else { return }
        let selection = selectedItems()
        let isRootItem = item.url == workspace?.workspaceFileManager?.folderUrl
        let sortMode = sender?.sortModes.mode(for: item.url) ?? .name

        let showInFinder = menuItem("Show in Finder", action: #selector(showInFinder))

        let openInTab = menuItem("Open in Tab", action: #selector(openInTab))
        let openInNewWindow = menuItem(
            "Open in New Window",
            action: #selector(openInNewWindow),
            enabled: !selection.isEmpty && selection.allSatisfy { !$0.isFolder }
        )
        let openExternalEditor = menuItem("Open with External Editor", action: #selector(openWithExternalEditor))
        let openAs = menuItem("Open As", action: nil)

        let cut = menuItem(
            "Cut",
            action: #selector(cutFiles),
            key: "x",
            enabled: !selection.contains { $0.isRoot }
        )
        let copy = menuItem("Copy", action: #selector(copyFiles), key: "c")
        let paste = menuItem("Paste", action: #selector(pasteFiles), key: "v", enabled: sender?.canPaste == true)

        let copyPath = menuItem("Copy Path", action: #selector(copyPath))
        let copyRelativePath = menuItem("Copy Relative Path", action: #selector(copyRelativePath))

        let newFile = menuItem("New File...", action: #selector(newFile))
        let newFileFromClipboard = menuItem("New File from Clipboard", action: #selector(newFileFromClipboard))
        let newFolder = menuItem("New Folder", action: #selector(newFolder))

        let rename = menuItem("Rename", action: #selector(renameFile))

        let trash = menuItem("Move to Trash", action: isRootItem ? nil : #selector(trash), enabled: !isRootItem)

        // trash has to be the previous menu item for delete.isAlternate to work correctly
        let delete = menuItem("Delete Immediately...", action: isRootItem ? nil : #selector(delete), enabled: !isRootItem)
        delete.keyEquivalentModifierMask = .option
        delete.isAlternate = true

        let duplicate = menuItem("Duplicate \(item.isFolder ? "Folder" : "File")", action: #selector(duplicate))

        let sortByName = menuItem("Sort by Name", action: #selector(sortByName), enabled: item.isFolder)
        sortByName.state = item.isFolder && sortMode == .name ? .on : .off

        let sortByType = menuItem("Sort by Type", action: #selector(sortByType), enabled: item.isFolder)
        sortByType.state = item.isFolder && sortMode == .type ? .on : .off

        let sourceControl = menuItem("Source Control", action: nil)

        items = [
            showInFinder,
            NSMenuItem.separator(),
            openInTab,
            openInNewWindow,
            openExternalEditor,
            openAs,
            NSMenuItem.separator(),
            cut,
            copy,
            paste,
            NSMenuItem.separator(),
            copyPath,
            copyRelativePath,
            NSMenuItem.separator(),
            newFile,
            newFileFromClipboard,
            newFolder
        ]

        if canCreateFolderFromSelection() {
            items.append(menuItem("New Folder from Selection", action: #selector(newFolderFromSelection)))
        }
        items.append(NSMenuItem.separator())
        if selection.count == 1 {
            items.append(rename)
        }

        items.append(
            contentsOf: [
                trash,
                delete,
                duplicate,
                NSMenuItem.separator(),
                sortByName,
                sortByType,
                NSMenuItem.separator(),
                sourceControl,
            ]
        )

        let rootURL = workspace?.workspaceFileManager?.folderUrl.standardizedFileURL
        if item.isFolder, item.url.standardizedFileURL != rootURL {
            let markDirectoryAs = menuItem("Mark Directory as", action: nil)
            items.append(markDirectoryAs)
            setSubmenu(markDirectoryAsMenu(item: item), for: markDirectoryAs)
        }

        setSubmenu(openAsMenu(item: item), for: openAs)
        setSubmenu(sourceControlMenu(item: item), for: sourceControl)
    }

    /// Submenu for **Open As** menu item.
    private func openAsMenu(item: CEWorkspaceFile) -> NSMenu {
        let openAsMenu = NSMenu(title: "Open As")
        func getMenusItems() -> ([NSMenuItem], [NSMenuItem]) {
            // Use UTType to distinguish between bundle file and user-browsable directory
            // The isDirectory property is not accurate on this.
            guard let type = item.contentType else { return ([.none()], []) }
            if type.conforms(to: .folder) {
                return ([.none()], [])
            }
            var primaryItems = [NSMenuItem]()
            if type.conforms(to: .sourceCode) {
                primaryItems.append(.sourceCode())
            }
            if type.conforms(to: .propertyList) {
                primaryItems.append(.propertyList())
            }
            if let xcassets = UTType(filenameExtension: "xcassets"), type.conforms(to: xcassets) {
                primaryItems.append(NSMenuItem(title: "Asset Catalog Document", action: nil, keyEquivalent: ""))
            }
            if let xib = UTType(filenameExtension: "xib"), type.conforms(to: xib) {
                primaryItems.append(NSMenuItem(title: "Interface Builder XIB Document", action: nil, keyEquivalent: ""))
            }
            if let xcodeproj = UTType(filenameExtension: "xcodeproj"), type.conforms(to: xcodeproj) {
                primaryItems.append(NSMenuItem(title: "Xcode Project", action: nil, keyEquivalent: ""))
            }
            var secondaryItems = [NSMenuItem]()
            if type.conforms(to: .text) {
                secondaryItems.append(.asciiPropertyList())
                secondaryItems.append(.hex())
            }

            if type.conforms(to: .data) {
                secondaryItems.append(.quickLook())
            }

            return (primaryItems, secondaryItems)
        }
        let (primaryItems, secondaryItems) = getMenusItems()
        for item in primaryItems {
            openAsMenu.addItem(item)
        }
        if !secondaryItems.isEmpty {
            openAsMenu.addItem(.separator())
        }
        for item in secondaryItems {
            openAsMenu.addItem(item)
        }
        return openAsMenu
    }

    /// Submenu for **Source Control** menu item.
    private func sourceControlMenu(item: CEWorkspaceFile) -> NSMenu {
        let isRepository = workspace?.sourceControlManager?.isGitRepository == true
        let sourceControlMenu = NSMenu(title: "Source Control")
        sourceControlMenu.autoenablesItems = false

        sourceControlMenu.addItem(menuItem("Show History", action: #selector(showHistory), enabled: isRepository))

        let annotate = menuItem(
            "Annotate with Git Blame",
            action: #selector(annotate),
            enabled: isRepository && !item.isFolder
        )
        annotate.state = isAnnotating(item) ? .on : .off
        sourceControlMenu.addItem(annotate)

        sourceControlMenu.addItem(
            menuItem("Rollback…", action: #selector(rollback), enabled: isRepository && !item.isFolder)
        )

        return sourceControlMenu
    }

    private func markDirectoryAsMenu(item: CEWorkspaceFile) -> NSMenu {
        let menu = NSMenu(title: "Mark Directory as")
        let isExcluded = ExcludedDirectories.rules(covering: item.url).isExclusionRoot(item.url)
        let entry = isExcluded
            ? menuItem("Cancel Exclusion", action: #selector(cancelExclusion))
            : menuItem("Excluded", action: #selector(markExcluded))
        entry.image = IntelliJIcon.nsImage("nodes/excludeRoot")
        menu.addItem(entry)
        return menu
    }

    @objc
    private func markExcluded() {
        guard let item else { return }
        workspace?.excludedDirectories?.exclude(item.url)
        sender?.outlineView.reloadItem(item, reloadChildren: true)
        workspace?.searchState?.addProjectToIndex()
    }

    @objc
    private func cancelExclusion() {
        guard let item else { return }
        workspace?.excludedDirectories?.cancelExclusion(item.url)
        sender?.outlineView.reloadItem(item, reloadChildren: true)
        workspace?.searchState?.addProjectToIndex()
    }
}

extension NSMenuItem {
    fileprivate static func none() -> NSMenuItem {
        let item = NSMenuItem(title: "<None>", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    fileprivate static func sourceCode() -> NSMenuItem {
        NSMenuItem(title: "Source Code", action: nil, keyEquivalent: "")
    }

    fileprivate static func propertyList() -> NSMenuItem {
        NSMenuItem(title: "Property List", action: nil, keyEquivalent: "")
    }

    fileprivate static func asciiPropertyList() -> NSMenuItem {
        NSMenuItem(title: "ASCII Property List", action: nil, keyEquivalent: "")
    }

    fileprivate static func hex() -> NSMenuItem {
        NSMenuItem(title: "Hex", action: nil, keyEquivalent: "")
    }

    fileprivate static func quickLook() -> NSMenuItem {
        NSMenuItem(title: "Quick Look", action: nil, keyEquivalent: "")
    }
}
