import Foundation
import OrderedCollections
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
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

    private func expectWeights(_ actual: [CGFloat], _ expected: [CGFloat]) {
        #expect(actual.count == expected.count)
        for (value, target) in zip(actual, expected) {
            #expect(abs(value - target) < 1e-9)
        }
    }

    private func expectWeightInvariant(_ layout: EditorLayout) {
        guard let data = layout.splitData else { return }
        #expect(data.weights.count == data.editorLayouts.count)
        #expect(data.weights.allSatisfy { $0 > 0 })
        if !data.editorLayouts.isEmpty {
            #expect(abs(data.weights.reduce(0, +) - 1) < 1e-9)
        }
        data.editorLayouts.forEach(expectWeightInvariant)
    }

    private func leafJSON(_ id: UUID) -> String {
        #"{"type":"one","tabs":{"tabs":[],"selectedTab":null,"id":"\#(id.uuidString)"}}"#
    }

    private func splitJSON(axis: String, children: [UUID], weightsJSON: String?) -> String {
        let weights = weightsJSON.map { #","weights":\#($0)"# } ?? ""
        let layouts = children.map(leafJSON).joined(separator: ",")
        return #"{"type":"\#(axis)","tabs":{"axis":"\#(axis)","editorLayouts":[\#(layouts)]\#(weights)}}"#
    }

    @Test
    func newSplitDataHasEqualWeightsPerChild() {
        let data = SplitViewData(
            .horizontal,
            editorLayouts: [.one(makeEditor()), .one(makeEditor()), .one(makeEditor())]
        )

        expectWeights(data.weights, [1.0 / 3, 1.0 / 3, 1.0 / 3])
        #expect(SplitViewData(.vertical).weights.isEmpty)
    }

    @Test
    func initNormalizesGivenWeightsAndFallsBackToEqualOnInvalidInput() {
        let layouts: [EditorLayout] = [.one(makeEditor()), .one(makeEditor())]

        expectWeights(SplitViewData(.horizontal, editorLayouts: layouts, weights: [3, 1]).weights, [0.75, 0.25])
        expectWeights(SplitViewData(.horizontal, editorLayouts: layouts, weights: [1]).weights, [0.5, 0.5])
        expectWeights(SplitViewData(.horizontal, editorLayouts: layouts, weights: [1, 0]).weights, [0.5, 0.5])
        expectWeights(SplitViewData(.horizontal, editorLayouts: layouts, weights: [1, -2]).weights, [0.5, 0.5])
        expectWeights(SplitViewData(.horizontal, editorLayouts: layouts, weights: [1, .nan]).weights, [0.5, 0.5])
        expectWeights(SplitViewData(.horizontal, editorLayouts: layouts, weights: [1, .infinity]).weights, [0.5, 0.5])
    }

    @Test
    func mutatingEditorLayoutsDirectlyResetsMismatchedWeightsToEqual() {
        let data = SplitViewData(
            .horizontal,
            editorLayouts: [.one(makeEditor()), .one(makeEditor())],
            weights: [0.9, 0.1]
        )

        data.editorLayouts.append(.one(makeEditor()))

        expectWeights(data.weights, [1.0 / 3, 1.0 / 3, 1.0 / 3])
    }

    @Test
    func splitAlongTheContainerAxisInsertsAfterAndGivesTheNewPaneHalfOfTheSplitPanesWeight() {
        for (axis, edge) in [(Axis.horizontal, Edge.trailing), (.vertical, .bottom)] {
            let a = makeEditor()
            let b = makeEditor()
            let new = makeEditor()
            let data = SplitViewData(axis, editorLayouts: [.one(a), .one(b)], weights: [0.6, 0.4])

            data.split(edge, at: 0, new: new)

            #expect(data.editorLayouts == [.one(a), .one(new), .one(b)])
            expectWeights(data.weights, [0.3, 0.3, 0.4])
            #expect(new.parent === data)
            expectWeightInvariant(EditorLayout.container(for: data))
        }
    }

    @Test
    func splitAgainstTheContainerAxisInsertsBeforeAndGivesTheNewPaneHalfOfTheSplitPanesWeight() {
        for (axis, edge) in [(Axis.horizontal, Edge.leading), (.vertical, .top)] {
            let a = makeEditor()
            let b = makeEditor()
            let new = makeEditor()
            let data = SplitViewData(axis, editorLayouts: [.one(a), .one(b)], weights: [0.6, 0.4])

            data.split(edge, at: 1, new: new)

            #expect(data.editorLayouts == [.one(a), .one(new), .one(b)])
            expectWeights(data.weights, [0.6, 0.2, 0.2])
            #expect(new.parent === data)
            expectWeightInvariant(EditorLayout.container(for: data))
        }
    }

    @Test
    func horizontalSplitTopAndBottomWrapThePaneInANestedVerticalSplitKeepingItsWeight() {
        let a = makeEditor()
        let b = makeEditor()
        let top = makeEditor()
        let bottom = makeEditor()
        let data = SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b)], weights: [0.6, 0.4])

        data.split(.top, at: 0, new: top)
        data.split(.bottom, at: 1, new: bottom)

        expectWeights(data.weights, [0.6, 0.4])
        guard case .vertical(let first) = data.editorLayouts[0],
              case .vertical(let second) = data.editorLayouts[1] else {
            Issue.record("expected nested vertical layouts, got \(data.editorLayouts)")
            return
        }
        #expect(first.axis == .vertical)
        #expect(first.editorLayouts == [.one(top), .one(a)])
        expectWeights(first.weights, [0.5, 0.5])
        #expect(second.editorLayouts == [.one(b), .one(bottom)])
        expectWeights(second.weights, [0.5, 0.5])
        #expect(top.parent === first)
        #expect(a.parent === first)
        #expect(b.parent === second)
        #expect(bottom.parent === second)
        expectWeightInvariant(EditorLayout.container(for: data))
    }

    @Test
    func verticalSplitLeadingAndTrailingWrapThePaneInANestedHorizontalSplitKeepingItsWeight() {
        let a = makeEditor()
        let b = makeEditor()
        let leading = makeEditor()
        let trailing = makeEditor()
        let data = SplitViewData(.vertical, editorLayouts: [.one(a), .one(b)], weights: [0.6, 0.4])

        data.split(.leading, at: 0, new: leading)
        data.split(.trailing, at: 1, new: trailing)

        expectWeights(data.weights, [0.6, 0.4])
        guard case .horizontal(let first) = data.editorLayouts[0],
              case .horizontal(let second) = data.editorLayouts[1] else {
            Issue.record("expected nested horizontal layouts, got \(data.editorLayouts)")
            return
        }
        #expect(first.axis == .horizontal)
        #expect(first.editorLayouts == [.one(leading), .one(a)])
        expectWeights(first.weights, [0.5, 0.5])
        #expect(second.editorLayouts == [.one(b), .one(trailing)])
        expectWeights(second.weights, [0.5, 0.5])
        #expect(leading.parent === first)
        #expect(trailing.parent === second)
        expectWeightInvariant(EditorLayout.container(for: data))
    }

    @Test
    func splitAtAnInvalidIndexChangesNothing() {
        let a = makeEditor()
        let new = makeEditor()
        let data = SplitViewData(.horizontal, editorLayouts: [.one(a)])

        data.split(.trailing, at: 1, new: new)
        data.split(.top, at: -1, new: new)

        #expect(data.editorLayouts == [.one(a)])
        expectWeights(data.weights, [1])
        #expect(new.parent == nil)
    }

    @Test
    func repeatedSplitsKeepTheWeightInvariant() {
        let root = SplitViewData(.horizontal, editorLayouts: [.one(makeEditor())])
        let edges: [Edge] = [.trailing, .bottom, .leading, .top, .trailing, .trailing, .bottom]

        for edge in edges {
            let leaves = EditorLayout.horizontal(root).getFlattened(parent: root)
            guard let target = leaves.last, let parent = target.parent, let index = parent.indexOfEditor(target) else {
                Issue.record("missing split target")
                return
            }
            parent.split(edge, at: index, new: makeEditor())
            expectWeightInvariant(.horizontal(root))
        }
    }

    @Test
    func closingAnEditorReturnsItsWeightToThePreviousNeighbour() {
        let a = makeEditor()
        let b = makeEditor()
        let c = makeEditor()
        let data = SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b), .one(c)], weights: [0.2, 0.3, 0.5])

        data.closeEditor(with: b.id)

        #expect(data.editorLayouts == [.one(a), .one(c)])
        expectWeights(data.weights, [0.5, 0.5])
    }

    @Test
    func closingTheFirstEditorReturnsItsWeightToTheNextNeighbour() {
        let a = makeEditor()
        let b = makeEditor()
        let c = makeEditor()
        let data = SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b), .one(c)], weights: [0.2, 0.3, 0.5])

        data.closeEditor(with: a.id)

        #expect(data.editorLayouts == [.one(b), .one(c)])
        expectWeights(data.weights, [0.5, 0.5])
    }

    @Test
    func closingTheLastEditorReturnsItsWeightToThePreviousNeighbour() {
        let a = makeEditor()
        let b = makeEditor()
        let c = makeEditor()
        let data = SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b), .one(c)], weights: [0.2, 0.3, 0.5])

        data.closeEditor(with: c.id)

        #expect(data.editorLayouts == [.one(a), .one(b)])
        expectWeights(data.weights, [0.2, 0.8])
    }

    @Test
    func closingTheOnlyEditorEmptiesLayoutsAndWeightsAndUnknownIdsAreIgnored() {
        let a = makeEditor()
        let data = SplitViewData(.horizontal, editorLayouts: [.one(a)])

        data.closeEditor(with: UUID())
        expectWeights(data.weights, [1])

        data.closeEditor(with: a.id)
        #expect(data.editorLayouts.isEmpty)
        #expect(data.weights.isEmpty)
    }

    @Test
    func flattenKeepsWeightsConsistentWhenCollapsingSingleChildSplits() {
        let root = SplitViewData(.horizontal)
        let a = makeEditor()
        let b = makeEditor()
        let wrapper = SplitViewData(.vertical, editorLayouts: [.one(a)])
        let outer = SplitViewData(.horizontal, editorLayouts: [.vertical(wrapper), .one(b)], weights: [0.7, 0.3])
        var layout = EditorLayout.horizontal(outer)

        layout.flatten(parent: root)

        #expect(outer.editorLayouts == [.one(a), .one(b)])
        expectWeights(outer.weights, [0.7, 0.3])
        expectWeightInvariant(layout)
    }

    @Test
    func getFlattenedDescendsThroughASingleChildSplitHoldingASplit() {
        let root = SplitViewData(.horizontal)
        let a = makeEditor()
        let b = makeEditor()
        let layout = EditorLayout.vertical(SplitViewData(.vertical, editorLayouts: [
            .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b)]))
        ]))

        #expect(layout.getFlattened(parent: root).map(\.id) == [a.id, b.id])
    }

    @Test
    func containerForDataFollowsTheDataAxis() {
        let horizontal = SplitViewData(.horizontal)
        let vertical = SplitViewData(.vertical)

        #expect(EditorLayout.container(for: horizontal) == .horizontal(horizontal))
        #expect(EditorLayout.container(for: vertical) == .vertical(vertical))
        #expect(EditorLayout.one(makeEditor()).splitData == nil)
    }

    @Test
    func replaceChildFindsNestedSplitsAndReparentsLeaves() {
        let a = makeEditor()
        let b = makeEditor()
        let c = makeEditor()
        let inner = SplitViewData(.vertical, editorLayouts: [.one(b), .one(c)])
        let root = SplitViewData(.horizontal, editorLayouts: [.one(a), .vertical(inner)], weights: [0.3, 0.7])

        #expect(root.replaceChild(inner, with: .one(b)))

        #expect(root.editorLayouts == [.one(a), .one(b)])
        #expect(b.parent === root)
        expectWeights(root.weights, [0.3, 0.7])
        #expect(root.replaceChild(SplitViewData(.vertical), with: .one(a)) == false)
    }

    @Test
    func codableRoundTripPreservesWeights() throws {
        let first = makeEditor(["a.swift"])
        let second = makeEditor()
        let third = makeEditor()
        let inner = SplitViewData(.vertical, editorLayouts: [.one(second), .one(third)], weights: [0.25, 0.75])
        let original = EditorLayout.horizontal(
            SplitViewData(.horizontal, editorLayouts: [.one(first), .vertical(inner)], weights: [0.7, 0.3])
        )

        let decoded = try roundTrip(original)

        let outer = try #require(splitData(decoded))
        expectWeights(outer.weights, [0.7, 0.3])
        let decodedInner = try #require(outer.editorLayouts[1].splitData)
        expectWeights(decodedInner.weights, [0.25, 0.75])
        expectWeightInvariant(decoded)
    }

    @Test
    func encodedSplitContainsOneWeightPerChild() throws {
        let layout = EditorLayout.horizontal(
            SplitViewData(.horizontal, editorLayouts: [.one(makeEditor()), .one(makeEditor())], weights: [3, 1])
        )

        let data = try JSONEncoder().encode(layout)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tabs = try #require(root["tabs"] as? [String: Any])
        let weights = try #require(tabs["weights"] as? [Double])

        #expect(weights.count == 2)
        #expect(abs(weights[0] - 0.75) < 1e-9)
        #expect(abs(weights[1] - 0.25) < 1e-9)
    }

    @Test
    func decodingLegacyStateWithoutWeightsRestoresEqualWeights() throws {
        let two = splitJSON(axis: "horizontal", children: [UUID(), UUID()], weightsJSON: nil)
        let three = splitJSON(axis: "vertical", children: [UUID(), UUID(), UUID()], weightsJSON: nil)

        let decodedTwo = try JSONDecoder().decode(EditorLayout.self, from: Data(two.utf8))
        let decodedThree = try JSONDecoder().decode(EditorLayout.self, from: Data(three.utf8))

        expectWeights(try #require(decodedTwo.splitData).weights, [0.5, 0.5])
        expectWeights(try #require(decodedThree.splitData).weights, [1.0 / 3, 1.0 / 3, 1.0 / 3])
    }

    @Test
    func decodingMismatchedOrInvalidWeightsFallsBackToEqualWeights() throws {
        let ids = [UUID(), UUID()]
        for weights in ["[0.9]", "[0.2,0.3,0.5]", "[0.5,-0.5]", "[0,1]", "\"oops\""] {
            let json = splitJSON(axis: "horizontal", children: ids, weightsJSON: weights)

            let decoded = try JSONDecoder().decode(EditorLayout.self, from: Data(json.utf8))

            expectWeights(try #require(decoded.splitData).weights, [0.5, 0.5])
        }
    }

    @Test
    func decodingNormalizesStoredWeightsToSumOne() throws {
        let json = splitJSON(axis: "horizontal", children: [UUID(), UUID()], weightsJSON: "[3,1]")

        let decoded = try JSONDecoder().decode(EditorLayout.self, from: Data(json.utf8))

        expectWeights(try #require(decoded.splitData).weights, [0.75, 0.25])
    }
}
