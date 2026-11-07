import Foundation
import OrderedCollections
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite
struct EditorLayoutTests {
    private func file(_ name: String) -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(filePath: "/fake/\(name)"))
    }

    private func makeEditor(_ names: [String] = [], selected: String? = nil) -> Editor {
        let files = OrderedSet(names.map { file($0) })
        guard let selected else { return Editor(files: files) }
        return Editor(files: files, selectedTab: EditorInstance(workspace: nil, file: file(selected)))
    }

    private func tabPaths(_ editor: Editor) -> [String] {
        editor.tabs.map { $0.file.url.path(percentEncoded: false) }
    }

    private func splitData(_ layout: EditorLayout) -> SplitViewData? {
        switch layout {
        case .one: nil
        case .vertical(let data), .horizontal(let data): data
        }
    }

    private func singleEditor(_ layout: EditorLayout) -> Editor? {
        if case .one(let editor) = layout { editor } else { nil }
    }

    private func roundTrip(_ layout: EditorLayout) throws -> EditorLayout {
        try JSONDecoder().decode(EditorLayout.self, from: JSONEncoder().encode(layout))
    }

    @Test
    func findSomeEditorReturnsTheSingleEditor() {
        let editor = makeEditor()

        #expect(EditorLayout.one(editor).findSomeEditor() === editor)
        #expect(EditorLayout.one(editor).findSomeEditor(except: makeEditor()) === editor)
    }

    @Test
    func findSomeEditorReturnsNilWhenTheOnlyEditorIsExcluded() {
        let editor = makeEditor()

        #expect(EditorLayout.one(editor).findSomeEditor(except: editor) == nil)
        #expect(EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [.one(editor)]))
            .findSomeEditor(except: editor) == nil)
        #expect(EditorLayout.vertical(SplitViewData(.vertical, editorLayouts: [
            .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(editor)]))
        ])).findSomeEditor(except: editor) == nil)
    }

    @Test
    func findSomeEditorInSplitPrefersTheFirstAndSkipsTheExcluded() {
        let first = makeEditor()
        let second = makeEditor()
        let layout = EditorLayout.horizontal(
            SplitViewData(.horizontal, editorLayouts: [.one(first), .one(second)])
        )

        #expect(layout.findSomeEditor() === first)
        #expect(layout.findSomeEditor(except: first) === second)
        #expect(layout.findSomeEditor(except: second) === first)
    }

    @Test
    func findSomeEditorDescendsIntoNestedSplits() {
        let a = makeEditor()
        let b = makeEditor()
        let c = makeEditor()
        let layout = EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(a), .one(b)])),
            .one(c)
        ]))

        #expect(layout.findSomeEditor() === a)
        #expect(layout.findSomeEditor(except: a) === b)
        #expect(layout.findSomeEditor(except: c) === a)
    }

    @Test
    func findSomeEditorInAnEmptySplitIsNil() {
        let layout = EditorLayout.horizontal(SplitViewData(.horizontal))

        #expect(layout.findSomeEditor() == nil)
        #expect(layout.findSomeEditor(except: makeEditor()) == nil)
    }

    @Test
    func findEditorByIdSearchesNestedSplits() {
        let a = makeEditor()
        let b = makeEditor()
        let layout = EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [
            .one(a),
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(b)]))
        ]))

        #expect(layout.find(editor: a.id) === a)
        #expect(layout.find(editor: b.id) === b)
        #expect(layout.find(editor: UUID()) == nil)
        #expect(EditorLayout.one(a).find(editor: b.id) == nil)
    }

    @Test
    func gatherOpenFilesUnionsTabsOfAllEditorsWithoutDuplicates() {
        let a = makeEditor(["one.swift", "shared.swift"])
        let b = makeEditor(["shared.swift", "two.swift"])
        let c = makeEditor()
        let layout = EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [
            .one(a),
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(b), .one(c)]))
        ]))

        let paths = Set(layout.gatherOpenFiles().map { $0.url.path(percentEncoded: false) })

        #expect(paths == ["/fake/one.swift", "/fake/shared.swift", "/fake/two.swift"])
        #expect(layout.gatherOpenFiles().count == 3)
        #expect(EditorLayout.one(c).gatherOpenFiles().isEmpty)
    }

    @Test
    func closeAllTabsOfAFileRemovesItFromEveryEditorAndMovesSelection() {
        let a = makeEditor(["f1", "f2"])
        let b = makeEditor(["f2", "f3"])
        let c = makeEditor(["f1"])
        let layout = EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [
            .one(a),
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(b), .one(c)]))
        ]))

        layout.closeAllTabs(of: file("f2"))

        #expect(tabPaths(a) == ["/fake/f1"])
        #expect(a.selectedTab?.file.url.lastPathComponent == "f1")
        #expect(tabPaths(b) == ["/fake/f3"])
        #expect(b.selectedTab?.file.url.lastPathComponent == "f3")
        #expect(tabPaths(c) == ["/fake/f1"])
    }

    @Test
    func closingTheLastTabClearsTheSelection() {
        let a = makeEditor(["f1", "f2"], selected: "f1")
        let c = makeEditor(["f1"])
        let layout = EditorLayout.vertical(SplitViewData(.vertical, editorLayouts: [.one(a), .one(c)]))

        layout.closeAllTabs(of: file("f1"))

        #expect(tabPaths(a) == ["/fake/f2"])
        #expect(c.tabs.isEmpty)
        #expect(c.selectedTab == nil)
    }

    @Test
    func isEmptyIsTrueOnlyForSplitsWithoutEditors() {
        let editor = makeEditor()
        let emptyInner = SplitViewData(.vertical)

        #expect(EditorLayout.one(editor).isEmpty == false)
        #expect(EditorLayout.horizontal(SplitViewData(.horizontal)).isEmpty)
        #expect(EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [.vertical(emptyInner)])).isEmpty)
        #expect(
            EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [.vertical(emptyInner), .one(editor)]))
                .isEmpty == false
        )
    }

    @Test
    func getFlattenedListsEditorsInDepthFirstOrder() {
        let root = SplitViewData(.horizontal)
        let a = makeEditor()
        let b = makeEditor()
        let c = makeEditor()
        let d = makeEditor()
        let layout = EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [
            .one(a),
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(b), .one(c)])),
            .one(d)
        ]))

        #expect(layout.getFlattened(parent: root).map(\.id) == [a.id, b.id, c.id, d.id])
    }

    @Test
    func getFlattenedHandlesSingleEditorAndSingleChildAndEmptySplit() {
        let root = SplitViewData(.horizontal)
        let editor = makeEditor()

        #expect(EditorLayout.one(editor).getFlattened(parent: root).map(\.id) == [editor.id])
        #expect(
            EditorLayout.vertical(SplitViewData(.vertical, editorLayouts: [.one(editor)]))
                .getFlattened(parent: root).map(\.id) == [editor.id]
        )
        #expect(EditorLayout.horizontal(SplitViewData(.horizontal)).getFlattened(parent: root).isEmpty)
    }

    @Test
    func flattenReplacesASingleEditorSplitWithItsEditorAndReparentsIt() {
        let root = SplitViewData(.horizontal)
        let editor = makeEditor()
        let inner = SplitViewData(.vertical, editorLayouts: [.one(editor)])
        var layout = EditorLayout.vertical(inner)
        #expect(editor.parent === inner)

        layout.flatten(parent: root)

        #expect(layout == .one(editor))
        #expect(editor.parent === root)
    }

    @Test
    func flattenCollapsesSingleEditorSplitsInsideALargerSplit() throws {
        let root = SplitViewData(.horizontal)
        let a = makeEditor()
        let b = makeEditor()
        let wrapper = SplitViewData(.vertical, editorLayouts: [.one(a)])
        let outer = SplitViewData(.horizontal, editorLayouts: [.vertical(wrapper), .one(b)])
        var layout = EditorLayout.horizontal(outer)

        layout.flatten(parent: root)

        let flattened = try #require(splitData(layout))
        #expect(flattened === outer)
        #expect(flattened.editorLayouts == [.one(a), .one(b)])
        #expect(a.parent === outer)
        #expect(b.parent === outer)
    }

    @Test
    func flattenLeavesLayoutsWithSeveralEditorsUntouched() {
        let root = SplitViewData(.horizontal)
        let a = makeEditor()
        let b = makeEditor()
        let data = SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b)])
        var layout = EditorLayout.horizontal(data)

        layout.flatten(parent: root)

        #expect(splitData(layout) === data)
        #expect(data.editorLayouts == [.one(a), .one(b)])
        #expect(a.parent === data)
        #expect(layout.getFlattened(parent: root).map(\.id) == [a.id, b.id])
    }

    @Test
    func equalityComparesEditorIdsAndLayoutKinds() {
        let a = makeEditor()
        let b = makeEditor()

        #expect(EditorLayout.one(a) == .one(a))
        #expect(EditorLayout.one(a) != .one(b))
        #expect(
            EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a)]))
                == .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a)]))
        )
        #expect(
            EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a)]))
                != .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(b)]))
        )
        #expect(
            EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a)]))
                != .vertical(SplitViewData(.vertical, editorLayouts: [.one(a)]))
        )
        #expect(EditorLayout.one(a) != .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a)])))
    }

    @Test
    func editorGetEditorLayoutReturnsItsDirectLayoutInTheParent() {
        let a = makeEditor()
        let b = makeEditor()
        let parent = SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b)])
        let orphan = makeEditor()

        #expect(a.getEditorLayout() == .one(a))
        #expect(b.getEditorLayout() == .one(b))
        #expect(orphan.getEditorLayout() == nil)
        #expect(parent.getEditorLayout(with: UUID()) == nil)
    }

    @Test
    func closingAnEditorRemovesItFromItsParentOnly() {
        let a = makeEditor()
        let b = makeEditor()
        let parent = SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b)])

        a.close()

        #expect(parent.editorLayouts == [.one(b)])
        #expect(a.getEditorLayout() == nil)
        #expect(parent.getEditorLayout(with: a.id) == nil)
        #expect(parent.getEditorLayout(with: b.id) == .one(b))
    }

    @Test
    func codableRoundTripPreservesStructureAxesTabsAndSelection() throws {
        let first = makeEditor(["a.swift", "b.swift"], selected: "b.swift")
        let second = makeEditor(["c.swift"])
        let third = makeEditor()
        let original = EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [
            .one(first),
            .vertical(SplitViewData(.vertical, editorLayouts: [.one(second), .one(third)]))
        ]))

        let decoded = try roundTrip(original)

        #expect(decoded == original)
        let outer = try #require(splitData(decoded))
        guard case .horizontal = decoded else {
            Issue.record("expected horizontal layout, got \(decoded)")
            return
        }
        #expect(outer.axis == .horizontal)
        try #require(outer.editorLayouts.count == 2)

        let decodedFirst = try #require(singleEditor(outer.editorLayouts[0]))
        #expect(decodedFirst.id == first.id)
        #expect(tabPaths(decodedFirst) == ["/fake/a.swift", "/fake/b.swift"])
        #expect(decodedFirst.selectedTab?.file.url == URL(filePath: "/fake/b.swift"))
        #expect(decodedFirst.parent === outer)

        guard case .vertical(let inner) = outer.editorLayouts[1] else {
            Issue.record("expected vertical layout, got \(outer.editorLayouts[1])")
            return
        }
        #expect(inner.axis == .vertical)
        let decodedSecond = try #require(singleEditor(inner.editorLayouts[0]))
        let decodedThird = try #require(singleEditor(inner.editorLayouts[1]))
        #expect(decodedSecond.id == second.id)
        #expect(tabPaths(decodedSecond) == ["/fake/c.swift"])
        #expect(decodedSecond.selectedTab?.file.url == URL(filePath: "/fake/c.swift"))
        #expect(decodedThird.id == third.id)
        #expect(decodedThird.tabs.isEmpty)
        #expect(decodedThird.selectedTab == nil)
        #expect(decodedSecond.parent === inner)
        #expect(decodedFirst.workspace == nil)
    }

    @Test
    func encodedLayoutUsesTypeAxisAndTabURLStrings() throws {
        let editor = makeEditor(["a.swift", "b.swift"], selected: "b.swift")
        let layout = EditorLayout.vertical(SplitViewData(.vertical, editorLayouts: [.one(editor)]))

        let data = try JSONEncoder().encode(layout)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tabs = try #require(root["tabs"] as? [String: Any])
        let children = try #require(tabs["editorLayouts"] as? [[String: Any]])
        let child = try #require(children.first)
        let editorObject = try #require(child["tabs"] as? [String: Any])

        #expect(root["type"] as? String == "vertical")
        #expect(tabs["axis"] as? String == "vertical")
        #expect(children.count == 1)
        #expect(child["type"] as? String == "one")
        #expect(editorObject["tabs"] as? [String] == ["file:///fake/a.swift", "file:///fake/b.swift"])
        #expect(editorObject["selectedTab"] as? String == "file:///fake/b.swift")
        #expect(editorObject["id"] as? String == editor.id.uuidString)
    }

    @Test
    func splitTypeAndAxisAreStoredIndependently() throws {
        let editor = makeEditor()
        let layout = EditorLayout.horizontal(SplitViewData(.vertical, editorLayouts: [.one(editor)]))

        let decoded = try roundTrip(layout)

        guard case .horizontal(let data) = decoded else {
            Issue.record("expected horizontal layout, got \(decoded)")
            return
        }
        #expect(data.axis == .vertical)
    }

    @Test
    func decodingEditorWithoutSelectedTabSelectsTheFirstTab() throws {
        let id = UUID()
        let json = """
        {"type":"one","tabs":{"tabs":["file:///fake/a.swift","file:///fake/b.swift"],"selectedTab":null,"id":"\(id.uuidString)"}}
        """

        let layout = try JSONDecoder().decode(EditorLayout.self, from: Data(json.utf8))

        let editor = try #require(singleEditor(layout))
        #expect(editor.id == id)
        #expect(tabPaths(editor) == ["/fake/a.swift", "/fake/b.swift"])
        #expect(editor.selectedTab?.file.url == URL(filePath: "/fake/a.swift"))
    }

    @Test
    func decodingEditorWithoutTabsHasNoSelection() throws {
        let id = UUID()
        let json = "{\"tabs\":[],\"id\":\"\(id.uuidString)\"}"

        let editor = try JSONDecoder().decode(Editor.self, from: Data(json.utf8))

        #expect(editor.id == id)
        #expect(editor.tabs.isEmpty)
        #expect(editor.selectedTab == nil)
        #expect(editor.parent == nil)
    }

    @Test
    func decodingRejectsUnknownLayoutTypeAndMissingEditorId() {
        let unknownType = #"{"type":"diagonal","tabs":{}}"#
        let missingId = #"{"type":"one","tabs":{"tabs":[],"selectedTab":null}}"#
        let missingAxis = #"{"type":"horizontal","tabs":{"editorLayouts":[]}}"#

        for json in [unknownType, missingId, missingAxis] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(EditorLayout.self, from: Data(json.utf8))
            }
        }
    }

    @Test
    func restorationStateRoundTripKeepsActiveEditorAndGroups() throws {
        let a = makeEditor(["a.swift"])
        let b = makeEditor(["b.swift", "c.swift"], selected: "c.swift")
        let groups = EditorLayout.horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b)]))
        let state = EditorRestorationState(activeEditor: b.id, groups: groups)

        let decoded = try JSONDecoder().decode(EditorRestorationState.self, from: JSONEncoder().encode(state))

        #expect(decoded.activeEditor == b.id)
        #expect(decoded.groups == groups)
        let restoredB = try #require(decoded.groups.find(editor: b.id))
        #expect(tabPaths(restoredB) == ["/fake/b.swift", "/fake/c.swift"])
        #expect(restoredB.selectedTab?.file.url == URL(filePath: "/fake/c.swift"))
    }
}
