import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class TabBarMenuRevealRecorder {
    var urls: [[URL]] = []
}

@MainActor
private struct TabBarMenuHarness {
    let workspace: WorkspaceDocument
    let manager: EditorManager
    let directory: URL
    let files: [CEWorkspaceFile]

    var editor: Editor {
        manager.activeEditor
    }

    var tabNames: [String] {
        editor.tabs.map(\.file.name)
    }

    static func make(in directory: URL, names: [String], loadsDocuments: Bool = true) throws -> Self {
        for name in names {
            try "content of \(name)\n".write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.editorManager)
        if !loadsDocuments {
            manager.activeEditor.workspace = nil
        }
        let files = try names.map { name in
            try #require(workspace.workspaceFileManager?.getFile(
                directory.appending(path: name).path(percentEncoded: false),
                createIfNotFound: true
            ))
        }
        files.forEach { manager.openTab(item: $0) }
        return Self(workspace: workspace, manager: manager, directory: directory, files: files)
    }

    func close() {
        workspace.close()
    }

    func itemActions(
        for item: CEWorkspaceFile,
        editor: Editor? = nil,
        pasteboard: InMemoryPasteboard = InMemoryPasteboard()
    ) -> EditorTabBarItemActions {
        EditorTabBarItemActions(
            item: item,
            editor: editor ?? self.editor,
            editorManager: manager,
            workspace: workspace,
            pasteboard: pasteboard
        )
    }

    func editorActions(for editor: Editor? = nil) -> EditorTabBarEditorActions {
        EditorTabBarEditorActions(editor: editor ?? self.editor, editorManager: manager, workspace: workspace)
    }

    func hostMenu(
        item: CEWorkspaceFile,
        editor: Editor,
        isTemporary: Bool,
        recorder: IdealSizeRecorder
    ) throws -> HostedView {
        try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 420, height: 900)) {
            VStack {
                EditorTabBarContextMenuItems(item: item, isTemporary: isTemporary)
            }
            .environment(editor)
            .recordingIdealSize(in: recorder)
        }
    }

    func menuHeight(item: CEWorkspaceFile, editor: Editor, isTemporary: Bool) async throws -> CGFloat {
        let recorder = IdealSizeRecorder()
        let hosted = try hostMenu(item: item, editor: editor, isTemporary: isTemporary, recorder: recorder)
        defer { hosted.close() }
        return try await hosted.idealSize(of: recorder).height
    }

    func accessoriesSize(
        editor: Editor,
        isHovering: Bool = false,
        controlActiveState: ControlActiveState = .inactive
    ) async throws -> CGSize {
        let recorder = IdealSizeRecorder()
        let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 420, height: 80)) {
            EditorTabBarTrailingAccessories(isHovering: isHovering)
                .environment(editor)
                .environment(\.controlActiveState, controlActiveState)
                .recordingIdealSize(in: recorder)
        }
        defer { hosted.close() }
        return try await hosted.idealSize(of: recorder)
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct EditorTabBarMenusTabBarCoverageTests {
    private static let names = ["alpha.txt", "bravo.txt", "charlie.txt"]

    @Test
    func closeTabClosesOnlyTheItem() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            #expect(harness.tabNames == Self.names)

            harness.itemActions(for: harness.files[1]).closeTab()

            #expect(harness.tabNames == ["alpha.txt", "charlie.txt"])
        }
    }

    @Test
    func closeOtherTabsKeepsOnlyTheItem() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }

            harness.itemActions(for: harness.files[1]).closeOtherTabs()

            #expect(harness.tabNames == ["bravo.txt"])
        }
    }

    @Test
    func closeTabsToTheRightClosesFollowingTabsOnly() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }

            harness.itemActions(for: harness.files[0]).closeTabsToTheRight()

            #expect(harness.tabNames == ["alpha.txt"])
        }
    }

    @Test
    func closeTabsToTheRightOfTheLastOrAnUnknownTabKeepsEverything() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let ghost = CEWorkspaceFile(url: directory.appending(path: "ghost.txt"))

            harness.itemActions(for: harness.files[2]).closeTabsToTheRight()
            #expect(harness.tabNames == Self.names)

            harness.itemActions(for: ghost).closeTabsToTheRight()
            #expect(harness.tabNames == Self.names)
        }
    }

    @Test
    func closeAllEmptiesTheEditor() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }

            harness.itemActions(for: harness.files[1]).editorActions.closeAll()

            #expect(harness.tabNames.isEmpty)
        }
    }

    @Test
    func closeOthersKeepsTheSelectedTab() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            #expect(harness.editor.selectedTab?.file.name == "charlie.txt")

            harness.editorActions().closeOthers()

            #expect(harness.tabNames == ["charlie.txt"])
        }
    }

    @Test
    func closeOthersWithoutASelectedTabDoesNothing() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let empty = Editor()

            harness.editorActions(for: empty).closeOthers()

            #expect(empty.tabs.isEmpty)
            #expect(harness.tabNames == Self.names)
        }
    }

    @Test
    func keepOpenClearsTheTemporaryTab() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            harness.editor.temporaryTab = harness.editor.tabs.first
            #expect(harness.editor.temporaryTab != nil)

            harness.itemActions(for: harness.files[0]).keepOpen()

            #expect(harness.editor.temporaryTab == nil)
        }
    }

    @Test
    func copyPathWritesTheStandardizedAbsolutePath() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let pasteboard = InMemoryPasteboard()
            let item = harness.files[1]

            harness.itemActions(for: item, pasteboard: pasteboard).copyPath()

            #expect(pasteboard.plainText == item.url.standardizedFileURL.path)
        }
    }

    @Test
    func copyRelativePathIsRelativeToTheWorkspaceFolder() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let pasteboard = InMemoryPasteboard()
            let nested = CEWorkspaceFile(url: directory.appending(path: "sub/deep/file.txt"))

            harness.itemActions(for: nested, pasteboard: pasteboard).copyRelativePath()
            #expect(pasteboard.plainText == "sub/deep/file.txt")

            harness.itemActions(for: harness.files[0], pasteboard: pasteboard).copyRelativePath()
            #expect(pasteboard.plainText == "alpha.txt")
        }
    }

    @Test
    func copyRelativePathClimbsOutOfTheWorkspaceFolder() throws {
        try withTempDir { directory in
            try withTempDir { sibling in
                let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
                defer { harness.close() }
                let pasteboard = InMemoryPasteboard()
                let outside = CEWorkspaceFile(url: sibling.appending(path: "outside.txt"))

                harness.itemActions(for: outside, pasteboard: pasteboard).copyRelativePath()

                #expect(pasteboard.plainText == "../\(sibling.lastPathComponent)/outside.txt")
            }
        }
    }

    @Test
    func copyRelativePathWithoutAWorkspaceFolderWritesNothing() throws {
        try withTempDir { directory in
            let pasteboard = InMemoryPasteboard()
            let workspace = WorkspaceDocument()
            let actions = EditorTabBarItemActions(
                item: CEWorkspaceFile(url: directory.appending(path: "lonely.txt")),
                editor: Editor(),
                editorManager: EditorManager(),
                workspace: workspace,
                pasteboard: pasteboard
            )

            actions.copyRelativePath()

            #expect(pasteboard.plainText == nil)
        }
    }

    @Test
    func showInFinderRevealsTheItemURL() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let recorder = TabBarMenuRevealRecorder()
            let item = harness.files[1]
            let actions = EditorTabBarItemActions(
                item: item,
                editor: harness.editor,
                editorManager: harness.manager,
                workspace: harness.workspace,
                revealInFinder: { [recorder] urls in recorder.urls.append(urls) }
            )

            actions.showInFinder()

            #expect(recorder.urls == [[item.url]])
        }
    }

    @Test
    func revealInProjectNavigatorHighlightsTheItem() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            #expect(harness.workspace.listenerModel.highlightedFileItem == nil)

            harness.itemActions(for: harness.files[2]).revealInProjectNavigator()

            #expect(harness.workspace.listenerModel.highlightedFileItem === harness.files[2])
        }
    }

    @Test
    func moveToNewSplitMovesTheTabIntoANewEditor() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: ["alpha.txt", "bravo.txt"])
            defer { harness.close() }
            let original = harness.editor

            harness.itemActions(for: harness.files[1]).moveToNewSplit(.trailing)()

            #expect(harness.manager.flattenedEditors.count == 2)
            #expect(harness.manager.activeEditor !== original)
            #expect(harness.manager.activeEditor.tabs.map(\.file.name) == ["bravo.txt"])
            #expect(original.tabs.map(\.file.name) == ["alpha.txt"])
        }
    }

    @Test
    func editorActionsSplitUnsplitAndRotateTheLayout() throws {
        try withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let original = harness.editor

            harness.editorActions().splitRight()
            #expect(harness.manager.flattenedEditors.count == 2)
            #expect(harness.editor !== original)

            harness.editorActions().splitDown()
            #expect(harness.manager.flattenedEditors.count == 3)
            #expect(harness.manager.isInSplitter(harness.editor))

            let axis = harness.editor.parent?.axis
            harness.editorActions().changeSplitterOrientation()
            #expect(harness.editor.parent?.axis != axis)

            harness.editorActions().unsplit()
            #expect(harness.manager.flattenedEditors.count == 2)

            harness.editorActions().unsplitAll()
            #expect(harness.manager.flattenedEditors.count == 1)
            #expect(harness.manager.isInSplitter(harness.editor) == false)
        }
    }

    @Test
    func contextMenuItemsGrowWithTemporaryTabAndSplitState() async throws {
        try await withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let item = harness.files[1]

            let permanent = try await harness.menuHeight(item: item, editor: harness.editor, isTemporary: false)
            let temporary = try await harness.menuHeight(item: item, editor: harness.editor, isTemporary: true)
            #expect(permanent > 0)
            #expect(temporary > permanent)

            harness.editorActions().splitRight()
            let twoEditors = try await harness.menuHeight(item: item, editor: harness.editor, isTemporary: false)
            #expect(twoEditors > permanent)

            harness.editorActions().splitDown()
            let threeEditors = try await harness.menuHeight(item: item, editor: harness.editor, isTemporary: false)
            #expect(threeEditors > twoEditors)
        }
    }

    @Test
    func contextMenuModifierAttachesToAnyView() async throws {
        try await withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let item = harness.files[0]
            let editor = harness.editor
            let hosted = try HostedViewFixture.hostInWorkspace(harness.workspace, size: NSSize(width: 200, height: 60)) {
                Text("tab")
                    .frame(width: 120, height: 30)
                    .tabBarContextMenu(item: item, isTemporary: true)
                    .environment(editor)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            #expect(hosted.renders())
        }
    }

    @Test
    func trailingAccessoriesShowMarkdownButtonsOnlyForMarkdownTabs() async throws {
        try await withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: ["code.txt", "notes.md"], loadsDocuments: false)
            defer { harness.close() }
            #expect(harness.editor.selectedTab?.file.name == "notes.md")
            let markdown = try await harness.accessoriesSize(editor: harness.editor)

            harness.editor.setSelectedTab(harness.files[0])
            let plain = try await harness.accessoriesSize(editor: harness.editor)

            #expect(plain.width > 0)
            #expect(markdown.width > plain.width)
        }
    }

    @Test
    func trailingAccessoriesRenderEveryActivityAndHoverState() async throws {
        try await withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: ["code.txt", "notes.md"], loadsDocuments: false)
            defer { harness.close() }

            let inactive = try await harness.accessoriesSize(editor: harness.editor)
            let key = try await harness.accessoriesSize(editor: harness.editor, controlActiveState: .key)
            harness.manager.isFocusingActiveEditor = true
            let focusing = try await harness.accessoriesSize(editor: harness.editor, controlActiveState: .key)
            harness.manager.isFocusingActiveEditor = false
            let hovering = try await harness.accessoriesSize(editor: harness.editor, isHovering: true)

            #expect(inactive.width > 0)
            #expect(key.width == inactive.width)
            #expect(focusing.width == inactive.width)
            #expect(hovering.width == inactive.width)
        }
    }

    @Test
    func trailingAccessoriesOfASplitEditorExposeTheUnsplitActions() async throws {
        try await withTempDir { directory in
            let harness = try TabBarMenuHarness.make(in: directory, names: Self.names)
            defer { harness.close() }
            let single = try await harness.accessoriesSize(editor: harness.editor)

            harness.editorActions().splitRight()
            harness.editorActions().splitDown()
            let split = try await harness.accessoriesSize(editor: harness.editor)

            #expect(split.width == single.width)
            #expect(harness.manager.flattenedEditors.count == 3)
        }
    }

    @Test
    func trailingAccessoryHoverStateIsSettable() {
        EditorTabBarTrailingAccessories().setHovering(true)
        EditorTabBarTrailingAccessories().setHovering(false)
    }
}
