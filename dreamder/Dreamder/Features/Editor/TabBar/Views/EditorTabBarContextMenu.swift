//
//  EditorTabBarContextMenu.swift
//  Dreamder
//
//  Created by Khan Winter on 6/4/22.
//

import SwiftUI
import Foundation

extension View {
    func tabBarContextMenu(item: CEWorkspaceFile, isTemporary: Bool) -> some View {
        modifier(EditorTabBarContextMenu(item: item, isTemporary: isTemporary))
    }
}

struct EditorTabBarContextMenu: ViewModifier {
    init(
        item: CEWorkspaceFile,
        isTemporary: Bool
    ) {
        self.item = item
        self.isTemporary = isTemporary
    }

    private var item: CEWorkspaceFile
    private var isTemporary: Bool

    func body(content: Content) -> some View {
        content.contextMenu(menuItems: {
            EditorTabBarContextMenuItems(item: item, isTemporary: isTemporary)
        })
    }
}

struct EditorTabBarContextMenuItems: View {
    @Environment(WorkspaceDocument.self) private var workspace

    @Environment(Editor.self) private var tabs

    @Environment(EditorManager.self) private var editorManager

    let item: CEWorkspaceFile
    static let pinTitle = "Pin Tab"
    static let unpinTitle = "Unpin Tab"

    static func pinToggleTitle(isPinned: Bool) -> String {
        isPinned ? unpinTitle : pinTitle
    }

    let isTemporary: Bool

    private var menuActions: EditorTabBarItemActions {
        EditorTabBarItemActions(item: item, editor: tabs, editorManager: editorManager, workspace: workspace)
    }

    // swiftlint:disable:next function_body_length
    var body: some View {
        let actions = menuActions
        Group {
            Button("Close Tab", action: actions.closeTab)
                .keymapShortcut(.closeTab)

            Button("Close Other Tabs", action: actions.closeOtherTabs)

            Button("Close Tabs to the Left", action: actions.closeTabsToTheLeft)
            .disabled(tabs.tabs.first?.file == item)

            Button("Close Tabs to the Right", action: actions.closeTabsToTheRight)
            // Disable this option when current tab is the last one.
            .disabled(tabs.tabs.last?.file == item)

            Button("Close Unmodified Tabs", action: actions.closeUnmodifiedTabs)

            Button("Close All", action: actions.editorActions.closeAll)

            Button(Self.pinToggleTitle(isPinned: tabs.isPinned(item)), action: actions.togglePinned)

            if isTemporary {
                Button("Keep Open", action: actions.keepOpen)
            }
        }

        Divider()

        Group {
            Button("Copy Path", action: actions.copyPath)

            Button("Copy Relative Path", action: actions.copyRelativePath)
        }

        Divider()

        Group {
            Button("Show in Finder", action: actions.showInFinder)

            Button("Reveal in Project Navigator", action: actions.revealInProjectNavigator)
        }

        Divider()

        Button("Split Up", action: actions.moveToNewSplit(.top))
        Button("Split Down", action: actions.moveToNewSplit(.bottom))
        Button("Split Left", action: actions.moveToNewSplit(.leading))
        Button("Split Right", action: actions.moveToNewSplit(.trailing))

        if editorManager.isInSplitter(tabs) {
            Divider()

            Button("Unsplit", action: actions.editorActions.unsplit)
            if editorManager.flattenedEditors.count > 2 {
                Button("Unsplit All", action: actions.editorActions.unsplitAll)
            }
            Button("Change Splitter Orientation", action: actions.editorActions.changeSplitterOrientation)
        }
    }
}

struct EditorTabBarItemActions {
    let item: CEWorkspaceFile
    let editor: Editor
    let editorManager: EditorManager
    let workspace: WorkspaceDocument
    var pasteboard: any PasteboardAccess = SystemPasteboard()
    var revealInFinder: @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    var editorActions: EditorTabBarEditorActions {
        EditorTabBarEditorActions(editor: editor, editorManager: editorManager, workspace: workspace)
    }

    func closeTab() {
        withAnimation {
            editor.closeTab(file: item)
        }
    }

    func closeOtherTabs() {
        withAnimation {
            editor.closeUnpinnedTabs { $0 != item }
        }
    }

    func closeTabsToTheLeft() {
        guard let index = editor.tabs.firstIndex(where: { $0.file == item }) else { return }
        let candidates = Set(editor.tabs[..<index].map(\.file.id))
        withAnimation {
            editor.closeUnpinnedTabs { candidates.contains($0.id) }
        }
    }

    func closeTabsToTheRight() {
        guard let index = editor.tabs.firstIndex(where: { $0.file == item }), index + 1 < editor.tabs.count else {
            return
        }
        let candidates = Set(editor.tabs[(index + 1)...].map(\.file.id))
        withAnimation {
            editor.closeUnpinnedTabs { candidates.contains($0.id) }
        }
    }

    func closeUnmodifiedTabs() {
        withAnimation {
            editor.closeUnpinnedTabs { $0.fileDocument?.isDocumentEdited != true }
        }
    }

    func togglePinned() {
        editor.togglePinned(file: item)
    }

    func keepOpen() {
        editor.temporaryTab = nil
    }

    func showInFinder() {
        revealInFinder([item.url])
    }

    func revealInProjectNavigator() {
        workspace.listenerModel.highlightedFileItem = item
    }

    func moveToNewSplit(_ edge: Edge) -> @MainActor () -> Void {
        { editorManager.moveTabToNewSplit(item, from: editor, edge: edge, workspace: workspace) }
    }

    // MARK: - Actions

    /// Copies the absolute path of the given `FileItem`
    /// - Parameter item: The `FileItem` to use.
    func copyPath() {
        pasteboard.replaceContents(withText: item.url.standardizedFileURL.path)
    }

    /// Copies the relative path from the workspace folder to the given file item to the pasteboard.
    /// - Parameter item: The `FileItem` to use.
    func copyRelativePath() {
        guard let rootPath = workspace.workspaceFileManager?.folderUrl else {
            return
        }
        let destinationComponents = item.url.standardizedFileURL.pathComponents
        let baseComponents = rootPath.standardizedFileURL.pathComponents

        // Find common prefix length
        var prefixCount = 0
        while prefixCount < min(destinationComponents.count, baseComponents.count)
                && destinationComponents[prefixCount] == baseComponents[prefixCount] {
            prefixCount += 1
        }
        // Build the relative path
        let upPath = String(repeating: "../", count: baseComponents.count - prefixCount)
        let downPath = destinationComponents[prefixCount...].joined(separator: "/")

        // Copy it to the clipboard
        pasteboard.replaceContents(withText: upPath + downPath)
    }
}
