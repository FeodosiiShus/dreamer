import Foundation
import OrderedCollections
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct EditorSplitsTests {
    private func file(_ name: String) -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(filePath: "/fake/\(name)"))
    }

    private func makeEditor(_ names: [String] = [], selected: String? = nil) -> Editor {
        let files = OrderedSet(names.map { file($0) })
        guard let selected else { return Editor(files: files) }
        return Editor(files: files, selectedTab: EditorInstance(workspace: nil, file: file(selected)))
    }

    private func makeManager(_ names: [String], selected: String? = nil) -> (manager: EditorManager, primary: Editor) {
        let manager = EditorManager()
        let primary = makeEditor(names, selected: selected)
        manager.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(primary)]))
        manager.activeEditor = primary
        return (manager, primary)
    }

    private func paths(_ editor: Editor) -> [String] {
        editor.tabs.map { $0.file.url.lastPathComponent }
    }

    private func root(_ manager: EditorManager) -> SplitViewData? {
        manager.editorLayout.splitData
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

    private func makeNestedManager() throws -> (manager: EditorManager, primary: Editor, first: Editor, second: Editor) {
        let (manager, primary) = makeManager(["a", "b"], selected: "a")
        let first = try #require(manager.splitActiveEditor(.trailing, workspace: nil))
        first.tabs.append(EditorInstance(workspace: nil, file: file("x")))
        let second = try #require(manager.splitActiveEditor(.bottom, workspace: nil))
        return (manager, primary, first, second)
    }

    @Test
    func splitCopiesOnlyTheSelectedTabAndActivatesTheNewEditor() throws {
        let (manager, primary) = makeManager(["a", "b", "c"], selected: "b")

        let new = try #require(manager.splitActiveEditor(.trailing, workspace: nil))

        #expect(paths(new) == ["b"])
        #expect(paths(primary) == ["a", "b", "c"])
        #expect(manager.activeEditor === new)
        #expect(manager.flattenedEditors == [primary, new])
        #expect(new.parent === primary.parent)
        expectWeights(try #require(root(manager)).weights, [0.5, 0.5])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func splitOfAnEditorWithoutTabsCreatesAnEmptyEditor() throws {
        let (manager, primary) = makeManager([])

        let new = try #require(manager.splitActiveEditor(.bottom, workspace: nil))

        #expect(new.tabs.isEmpty)
        #expect(manager.flattenedEditors == [primary, new])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func splitTargetsTheGivenEditorEvenWhenAnotherEditorIsActive() throws {
        let manager = EditorManager()
        let a = makeEditor(["a"])
        let b = makeEditor(["b"])
        manager.editorLayout = .horizontal(SplitViewData(.horizontal, editorLayouts: [.one(a), .one(b)]))
        manager.activeEditor = b

        let new = try #require(manager.split(a, .bottom, workspace: nil))

        #expect(manager.flattenedEditors == [a, new, b])
        #expect(manager.activeEditor === new)
        let data = try #require(root(manager))
        guard case .vertical(let nested) = data.editorLayouts[0] else {
            Issue.record("expected nested vertical layout, got \(data.editorLayouts)")
            return
        }
        #expect(nested.editorLayouts == [.one(a), .one(new)])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func splitOfAnEditorOutsideAnyLayoutReturnsNil() {
        let manager = EditorManager()

        #expect(manager.split(makeEditor(["a"]), .trailing, workspace: nil) == nil)
    }

    @Test
    func weightsFollowSplitsAndCloses() throws {
        let (manager, primary) = makeManager(["a"])
        let second = try #require(manager.splitActiveEditor(.trailing, workspace: nil))
        expectWeights(try #require(root(manager)).weights, [0.5, 0.5])

        let third = try #require(manager.splitActiveEditor(.trailing, workspace: nil))
        expectWeights(try #require(root(manager)).weights, [0.5, 0.25, 0.25])
        expectWeightInvariant(manager.editorLayout)

        manager.closeEditor(third)

        #expect(manager.flattenedEditors == [primary, second])
        expectWeights(try #require(root(manager)).weights, [0.5, 0.5])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func closingTheEmptyPrimaryEditorRetainsTheOtherEditors() throws {
        let (manager, primary) = makeManager(["a"])
        let second = try #require(manager.splitActiveEditor(.trailing, workspace: nil))
        let third = try #require(manager.splitActiveEditor(.trailing, workspace: nil))
        #expect(manager.flattenedEditors.count == 3)

        primary.closeTab(file: file("a"))
        #expect(primary.tabs.isEmpty)
        manager.closeEditor(primary)

        #expect(manager.flattenedEditors == [second, third])
        #expect(manager.activeEditor === third)
        expectWeights(try #require(root(manager)).weights, [0.75, 0.25])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func previousAndNextSplitEditorAreCyclic() throws {
        let (manager, primary) = makeManager(["a"])
        let secondary = try #require(manager.splitActiveEditor(.trailing, workspace: nil))

        #expect(manager.flattenedEditors == [primary, secondary])
        #expect(manager.previousSplitEditor(before: primary) === secondary)
        #expect(manager.nextSplitEditor(after: secondary) === primary)
        #expect(manager.nextSplitEditor(after: primary) === secondary)
        #expect(manager.previousSplitEditor(before: secondary) === primary)
    }

    @Test
    func splitEditorNavigationCyclesThroughNestedLayoutsInDepthFirstOrder() throws {
        let (manager, primary, first, second) = try makeNestedManager()

        #expect(manager.flattenedEditors == [primary, first, second])
        #expect(manager.nextSplitEditor(after: primary) === first)
        #expect(manager.nextSplitEditor(after: first) === second)
        #expect(manager.nextSplitEditor(after: second) === primary)
        #expect(manager.previousSplitEditor(before: primary) === second)
        #expect(manager.previousSplitEditor(before: second) === first)
    }

    @Test
    func splitEditorNavigationOfASingleEditorReturnsItAndUnknownEditorsReturnNil() {
        let (manager, primary) = makeManager(["a"])

        #expect(manager.nextSplitEditor(after: primary) === primary)
        #expect(manager.previousSplitEditor(before: primary) === primary)
        #expect(manager.nextSplitEditor(after: makeEditor()) == nil)
        #expect(manager.previousSplitEditor(before: makeEditor()) == nil)
    }

    @Test
    func isInSplitterIsTrueOnlyWhileAnEditorSharesItsContainer() throws {
        let (manager, primary) = makeManager(["a"])
        #expect(manager.isInSplitter(primary) == false)
        #expect(manager.isInSplitter(makeEditor()) == false)

        let secondary = try #require(manager.splitActiveEditor(.trailing, workspace: nil))
        #expect(manager.isInSplitter(primary))
        #expect(manager.isInSplitter(secondary))

        manager.closeEditor(secondary)
        #expect(manager.isInSplitter(primary) == false)
    }

    @Test
    func unsplitMergesSiblingTabsIntoTheSurvivorAndSkipsFilesAlreadyOpen() throws {
        let (manager, primary) = makeManager(["a", "b"], selected: "a")
        let secondary = try #require(manager.splitActiveEditor(.trailing, workspace: nil))
        secondary.tabs.append(EditorInstance(workspace: nil, file: file("c")))
        #expect(paths(secondary) == ["a", "c"])

        #expect(manager.unsplit(primary))

        #expect(paths(primary) == ["a", "b", "c"])
        #expect(primary.selectedTab?.file == file("a"))
        #expect(manager.flattenedEditors == [primary])
        #expect(manager.activeEditor === primary)
        #expect(secondary.parent == nil)
        let data = try #require(root(manager))
        #expect(data.editorLayouts == [.one(primary)])
        #expect(primary.parent === data)
        expectWeights(data.weights, [1])
        #expect(manager.isInSplitter(primary) == false)
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func unsplitFromTheSecondaryEditorKeepsItsOwnSelectionAndTabOrder() throws {
        let (manager, primary) = makeManager(["a", "b"], selected: "a")
        let secondary = try #require(manager.splitActiveEditor(.trailing, workspace: nil))

        #expect(manager.unsplit(secondary))

        #expect(paths(secondary) == ["a", "b"])
        #expect(secondary.selectedTab?.file == file("a"))
        #expect(manager.flattenedEditors == [secondary])
        #expect(manager.activeEditor === secondary)
        #expect(primary.parent == nil)
    }

    @Test
    func unsplitOutsideASplitterDoesNothing() {
        let (manager, primary) = makeManager(["a"])

        #expect(manager.unsplit(primary) == false)
        #expect(manager.unsplit(makeEditor(["z"])) == false)

        #expect(manager.flattenedEditors == [primary])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func unsplitCollapsesOnlyTheEditorsImmediateSplitter() throws {
        let (manager, primary, first, second) = try makeNestedManager()
        #expect(paths(first) == ["a", "x"])
        #expect(paths(second) == ["x"])

        #expect(manager.unsplit(first))

        #expect(manager.flattenedEditors == [primary, first])
        #expect(paths(first) == ["a", "x"])
        #expect(paths(primary) == ["a", "b"])
        #expect(second.parent == nil)
        #expect(first.parent === primary.parent)
        #expect(manager.activeEditor === first)
        expectWeights(try #require(root(manager)).weights, [0.5, 0.5])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func unsplitAllLeavesOneEditorWithTheUnionOfTabs() throws {
        let (manager, primary, first, second) = try makeNestedManager()
        #expect(manager.activeEditor === second)

        manager.unsplitAll()

        #expect(manager.flattenedEditors == [second])
        #expect(Set(paths(second)) == ["a", "b", "x"])
        #expect(second.tabs.count == 3)
        #expect(second.selectedTab?.file == file("x"))
        #expect(manager.activeEditor === second)
        #expect(manager.isInSplitter(second) == false)
        #expect(primary.parent == nil)
        #expect(first.parent == nil)
        let data = try #require(root(manager))
        #expect(data.editorLayouts == [.one(second)])
        expectWeights(data.weights, [1])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func unsplitAllOutsideASplitterDoesNothing() {
        let (manager, primary) = makeManager(["a", "b"])

        manager.unsplitAll()

        #expect(manager.flattenedEditors == [primary])
        #expect(paths(primary) == ["a", "b"])
    }

    @Test
    func changeOrientationFlipsOnlyTheParentAxisOfTheEditor() throws {
        let (manager, primary, first, second) = try makeNestedManager()
        let data = try #require(root(manager))
        expectWeights(data.weights, [0.5, 0.5])

        #expect(manager.changeSplitterOrientation(of: first))

        let nested = try #require(data.editorLayouts[1].splitData)
        guard case .horizontal = data.editorLayouts[1] else {
            Issue.record("expected the nested layout to be horizontal, got \(data.editorLayouts[1])")
            return
        }
        #expect(nested.axis == .horizontal)
        #expect(data.axis == .horizontal)
        #expect(nested.editorLayouts == [.one(first), .one(second)])
        #expect(manager.flattenedEditors == [primary, first, second])
        expectWeights(data.weights, [0.5, 0.5])
        expectWeights(nested.weights, [0.5, 0.5])

        #expect(manager.changeSplitterOrientation(of: second))
        #expect(nested.axis == .vertical)
        guard case .vertical = data.editorLayouts[1] else {
            Issue.record("expected the nested layout to be vertical again, got \(data.editorLayouts[1])")
            return
        }
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func changeOrientationOfTheRootSplitterRewrapsTheLayoutAndLeavesNestedSplittersAlone() throws {
        let (manager, primary, first, second) = try makeNestedManager()
        let data = try #require(root(manager))

        #expect(manager.changeSplitterOrientation(of: primary))

        guard case .vertical(let flipped) = manager.editorLayout else {
            Issue.record("expected a vertical root layout, got \(manager.editorLayout)")
            return
        }
        #expect(flipped === data)
        #expect(data.axis == .vertical)
        let nested = try #require(data.editorLayouts[1].splitData)
        #expect(nested.axis == .vertical)
        #expect(manager.flattenedEditors == [primary, first, second])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func changeOrientationOutsideASplitterDoesNothing() {
        let (manager, primary) = makeManager(["a"])

        #expect(manager.changeSplitterOrientation(of: primary) == false)

        #expect(root(manager)?.axis == .horizontal)
        guard case .horizontal = manager.editorLayout else {
            Issue.record("expected a horizontal root layout, got \(manager.editorLayout)")
            return
        }
    }

    @Test
    func moveTabToNewSplitMovesTheTabAndActivatesTheNewEditor() throws {
        let (manager, primary) = makeManager(["a", "b"], selected: "a")

        let new = try #require(
            manager.moveTabToNewSplit(file("b"), from: primary, edge: .trailing, workspace: nil)
        )

        #expect(paths(new) == ["b"])
        #expect(paths(primary) == ["a"])
        #expect(manager.activeEditor === new)
        #expect(manager.flattenedEditors == [primary, new])
        expectWeightInvariant(manager.editorLayout)
    }

    @Test
    func moveTabToNewSplitOfAnEditorOutsideAnyLayoutReturnsNil() {
        let manager = EditorManager()
        let orphan = makeEditor(["a"])

        #expect(manager.moveTabToNewSplit(file("a"), from: orphan, edge: .top, workspace: nil) == nil)
        #expect(paths(orphan) == ["a"])
    }
}
