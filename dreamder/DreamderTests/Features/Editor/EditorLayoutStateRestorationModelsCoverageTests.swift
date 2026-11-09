import AppKit
import Foundation
import OrderedCollections
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorLayoutStateRestorationModelsCoverageTests {
    private struct Source {
        let workspace: WorkspaceDocument
        let manager: EditorManager
    }

    private struct ForcedFailure: Error {}

    private func makeSource(in directory: URL, names: [String] = ["a.txt", "b.txt", "c.txt"]) throws -> Source {
        for name in names {
            try name.write(to: directory.appending(path: name), atomically: true, encoding: .utf8)
        }
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        let manager = try #require(workspace.editorManager)
        return Source(workspace: workspace, manager: manager)
    }

    private func file(_ name: String, in workspace: WorkspaceDocument) throws -> CEWorkspaceFile {
        let fileManager = try #require(workspace.workspaceFileManager)
        let children = try #require(fileManager.childrenOfFile(fileManager.workspaceItem))
        return try #require(children.first(where: { $0.name == name }))
    }

    private func discardState(of workspace: WorkspaceDocument) {
        UserDefaults.standard.removeObject(forKey: "workspaceState-\(workspace.fileURL?.absoluteString ?? "")")
    }

    private func store(_ layout: EditorLayout, active: UUID, in workspace: WorkspaceDocument) throws {
        let data = try JSONEncoder().encode(EditorRestorationState(activeEditor: active, groups: layout))
        workspace.addToWorkspaceState(key: .openTabs, value: data)
    }

    private func tabNames(_ editor: Editor) -> [String] {
        editor.tabs.map { $0.file.name }
    }

    @Test
    func restoresASavedSplitLayoutThroughTheProductionOpenPath() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir)
            defer { discardState(of: source.workspace) }
            let a = try file("a.txt", in: source.workspace)
            let b = try file("b.txt", in: source.workspace)
            let c = try file("c.txt", in: source.workspace)
            let first = Editor(files: OrderedSet([a, b]), selectedTab: EditorInstance(workspace: nil, file: a))
            let second = Editor(files: OrderedSet([a, c]), selectedTab: EditorInstance(workspace: nil, file: c))
            let third = Editor(files: OrderedSet([c]))
            let nested = SplitViewData(.vertical, editorLayouts: [.one(second), .one(third)])
            let root = SplitViewData(.horizontal, editorLayouts: [.one(first), .vertical(nested)], weights: [0.3, 0.7])
            source.manager.editorLayout = .horizontal(root)
            source.manager.activeEditor = third
            source.manager.saveRestorationState(source.workspace)

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restoredManager = try #require(restoredWorkspace.editorManager)

            let editors = restoredManager.flattenedEditors
            #expect(editors.count == 3)
            let byID = Dictionary(uniqueKeysWithValues: editors.map { ($0.id, $0) })
            let restoredFirst = try #require(byID[first.id])
            let restoredSecond = try #require(byID[second.id])
            let restoredThird = try #require(byID[third.id])
            #expect(tabNames(restoredFirst) == ["a.txt", "b.txt"])
            #expect(tabNames(restoredSecond) == ["a.txt", "c.txt"])
            #expect(tabNames(restoredThird) == ["c.txt"])
            #expect(restoredFirst.selectedTab?.file.name == "a.txt")
            #expect(restoredSecond.selectedTab?.file.name == "c.txt")
            #expect(restoredThird.selectedTab?.file.name == "c.txt")
            #expect(restoredManager.activeEditor === restoredThird)
            #expect(editors.allSatisfy { $0.workspace === restoredWorkspace })

            let rootData = try #require(restoredManager.editorLayout.splitData)
            #expect(rootData.axis == .horizontal)
            #expect(abs(rootData.weights[0] - 0.3) < 1e-9)
            #expect(abs(rootData.weights[1] - 0.7) < 1e-9)
            guard case .vertical(let restoredNested) = rootData.editorLayouts[1] else {
                Issue.record("expected the nested layout to stay vertical")
                return
            }
            #expect(restoredNested.editorLayouts.count == 2)

            let restoredFileManager = try #require(restoredWorkspace.workspaceFileManager)
            let restoredA = try #require(restoredFileManager.getFile(a.url.path(percentEncoded: false)))
            #expect(restoredFirst.tabs.first?.file === restoredA)
            #expect(restoredSecond.tabs.first?.file === restoredA)
            #expect(restoredA.fileDocument != nil)

            let loadedDocuments = DreamderDocumentController.shared.documents.filter {
                $0.fileURL?.lastPathComponent == "a.txt"
                    && $0.fileURL?.deletingLastPathComponent().lastPathComponent == dir.lastPathComponent
            }
            #expect(loadedDocuments.count == 1)
        }
    }

    @Test
    func restoresASingleEditorLayout() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir)
            defer { discardState(of: source.workspace) }
            let a = try file("a.txt", in: source.workspace)
            let solo = Editor(files: OrderedSet([a]))
            source.manager.editorLayout = .one(solo)
            source.manager.activeEditor = solo
            source.manager.saveRestorationState(source.workspace)

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restoredManager = try #require(restoredWorkspace.editorManager)

            guard case .one(let restored) = restoredManager.editorLayout else {
                Issue.record("expected a single editor layout")
                return
            }
            #expect(restored.id == solo.id)
            #expect(tabNames(restored) == ["a.txt"])
            #expect(restored.workspace === restoredWorkspace)
            #expect(restoredManager.activeEditor === restored)
        }
    }

    @Test
    func tabsOutsideTheWorkspaceAreDroppedAndAnUnresolvableSelectionIsCleared() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir)
            defer { discardState(of: source.workspace) }
            let a = try file("a.txt", in: source.workspace)
            let outside = CEWorkspaceFile(url: URL(filePath: "/fake/outside.txt"))
            let elsewhere = CEWorkspaceFile(url: URL(filePath: "/fake/elsewhere.txt"))
            let editor = Editor(
                files: OrderedSet([a, outside]),
                selectedTab: EditorInstance(workspace: nil, file: elsewhere)
            )
            source.manager.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(editor)]))
            source.manager.activeEditor = editor
            source.manager.saveRestorationState(source.workspace)

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restored = try #require(restoredWorkspace.editorManager?.flattenedEditors.first)

            #expect(restored.id == editor.id)
            #expect(tabNames(restored) == ["a.txt"])
            #expect(restored.selectedTab == nil)
        }
    }

    @Test
    func anUnknownActiveEditorFallsBackToTheFirstEditor() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir)
            defer { discardState(of: source.workspace) }
            let a = try file("a.txt", in: source.workspace)
            let b = try file("b.txt", in: source.workspace)
            let first = Editor(files: OrderedSet([a]))
            let second = Editor(files: OrderedSet([b]))
            let layout = EditorLayout.horizontal(
                SplitViewData(.horizontal, editorLayouts: [.one(first), .one(second)])
            )
            try store(layout, active: UUID(), in: source.workspace)

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restoredManager = try #require(restoredWorkspace.editorManager)

            #expect(restoredManager.flattenedEditors.count == 2)
            #expect(restoredManager.activeEditor.id == first.id)
        }
    }

    @Test
    func anEmptySavedLayoutRestoresACleanEditor() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir)
            defer { discardState(of: source.workspace) }
            try store(.horizontal(SplitViewData(.horizontal)), active: UUID(), in: source.workspace)

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restoredManager = try #require(restoredWorkspace.editorManager)

            let editors = restoredManager.flattenedEditors
            #expect(editors.count == 1)
            let only = try #require(editors.first)
            #expect(only.tabs.isEmpty)
            #expect(only.workspace === restoredWorkspace)
            #expect(restoredManager.activeEditor === only)
        }
    }

    @Test
    func corruptSavedDataKeepsTheCleanEditorAndStillAttachesTheWorkspace() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir)
            defer { discardState(of: source.workspace) }
            source.workspace.addToWorkspaceState(key: .openTabs, value: Data("not json".utf8))

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restoredManager = try #require(restoredWorkspace.editorManager)

            let editors = restoredManager.flattenedEditors
            #expect(editors.count == 1)
            #expect(editors.first?.tabs.isEmpty == true)
            #expect(editors.first?.workspace === restoredWorkspace)
        }
    }

    @Test
    func savedStateThatIsNotDataIsIgnored() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir)
            defer { discardState(of: source.workspace) }
            source.workspace.addToWorkspaceState(key: .openTabs, value: "text")

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restoredManager = try #require(restoredWorkspace.editorManager)

            #expect(restoredManager.flattenedEditors.count == 1)
            #expect(restoredManager.flattenedEditors.first?.workspace === restoredWorkspace)
        }
    }

    @Test
    func anUnreadableTabAbortsTheRestoreAndKeepsTheCleanEditor() throws {
        try withTempDir { dir in
            let source = try makeSource(in: dir, names: ["locked.txt"])
            defer { discardState(of: source.workspace) }
            let locked = try file("locked.txt", in: source.workspace)
            let editor = Editor(files: OrderedSet([locked]))
            source.manager.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(editor)]))
            source.manager.activeEditor = editor
            source.manager.saveRestorationState(source.workspace)
            let lockedPath = dir.appending(path: "locked.txt").path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedPath)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: lockedPath) }

            let restoredWorkspace = try HostedViewFixture.makeWorkspace(in: dir)
            let restoredManager = try #require(restoredWorkspace.editorManager)

            let editors = restoredManager.flattenedEditors
            #expect(editors.count == 1)
            #expect(editors.first?.id != editor.id)
            #expect(editors.first?.tabs.isEmpty == true)
        }
    }

    @Test
    func restoreWithoutAFileManagerKeepsTheDecodedLayout() throws {
        try withTempDir { dir in
            let workspace = WorkspaceDocument()
            workspace.fileURL = dir
            defer { discardState(of: workspace) }
            let first = Editor(files: OrderedSet([CEWorkspaceFile(url: dir.appending(path: "one.txt"))]))
            let second = Editor(files: OrderedSet([CEWorkspaceFile(url: dir.appending(path: "two.txt"))]))
            let source = EditorManager()
            source.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(first), .one(second)]))
            source.activeEditor = second
            source.saveRestorationState(workspace)

            let restored = EditorManager()
            restored.restoreFromState(workspace)

            let editors = restored.flattenedEditors
            #expect(editors.map(\.id) == [first.id, second.id])
            #expect(editors.map { $0.tabs.map { $0.file.url.lastPathComponent } } == [["one.txt"], ["two.txt"]])
            #expect(restored.activeEditor === editors[1])
            #expect(editors.allSatisfy { $0.workspace === workspace })
        }
    }

    @Test
    func restoreWithoutSavedStateOnlyAttachesTheWorkspace() throws {
        try withTempDir { dir in
            let workspace = WorkspaceDocument()
            workspace.fileURL = dir
            defer { discardState(of: workspace) }
            let manager = EditorManager()
            let before = manager.activeEditor

            manager.restoreFromState(workspace)

            #expect(manager.activeEditor === before)
            #expect(before.workspace === workspace)
        }
    }

    @Test
    func aFailingEncoderClearsThePreviouslySavedState() throws {
        try withTempDir { dir in
            let workspace = WorkspaceDocument()
            workspace.fileURL = dir
            defer { discardState(of: workspace) }
            let manager = EditorManager()
            manager.saveRestorationState(workspace)
            #expect(workspace.getFromWorkspaceState(.openTabs) is Data)

            manager.saveRestorationState(workspace) { _ in throw ForcedFailure() }

            #expect(workspace.getFromWorkspaceState(.openTabs) == nil)
        }
    }
}
