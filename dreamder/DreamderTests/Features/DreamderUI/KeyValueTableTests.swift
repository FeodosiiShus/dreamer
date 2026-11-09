import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

@Observable
@MainActor
final class KeyValueItemsBox {
    var items: [String: String]

    init(_ items: [String: String]) {
        self.items = items
    }
}

@MainActor
struct KeyValueTableHarness<Trailing: View>: View {
    let box: KeyValueItemsBox
    let model: KeyValueTableModel
    let validKeys: [String]
    let trailing: Trailing

    var body: some View {
        @Bindable var box = box
        KeyValueTable(
            items: $box.items,
            validKeys: validKeys,
            keyColumnName: "Key",
            valueColumnName: "Value",
            newItemInstruction: "Add an entry",
            model: model,
            actionBarTrailing: { trailing }
        )
    }
}

@MainActor
@Suite(.uiGate)
struct KeyValueTableTests {
    func sampleModel(_ entries: [String: String] = ["b": "2", "a": "1", "c": "3"]) -> KeyValueTableModel {
        let model = KeyValueTableModel()
        model.reload(from: entries)
        return model
    }

    func itemsBinding(_ box: KeyValueItemsBox) -> Binding<[String: String]> {
        Bindable(box).items
    }

    @Test func reloadSortsRowsByKey() {
        let model = sampleModel()
        #expect(model.tableItems.map(\.key) == ["a", "b", "c"])
        #expect(model.tableItems.map(\.value) == ["1", "2", "3"])
    }

    @Test func reloadReplacesPreviousRows() {
        let model = sampleModel()
        model.reload(from: ["z": "26"])
        #expect(model.tableItems.map(\.key) == ["z"])
        model.reload(from: [:])
        #expect(model.tableItems.isEmpty)
    }

    @Test func beginAddingOpensAnEmptyItem() {
        let model = sampleModel()
        model.beginAdding()
        #expect(model.editingItem?.key == "")
        #expect(model.editingItem?.value == "")
    }

    @Test func beginEditingOpensTheMatchingRow() throws {
        let model = sampleModel()
        let row = try #require(model.tableItems.first { $0.key == "b" })
        model.beginEditing(ids: [row.id])
        #expect(model.editingItem == row)
    }

    @Test func beginEditingIgnoresEmptyAndUnknownSelections() {
        let model = sampleModel()
        model.beginEditing(ids: [])
        #expect(model.editingItem == nil)
        model.beginEditing(ids: [UUID()])
        #expect(model.editingItem == nil)
    }

    @Test func removeDeletesOnlyTheGivenRows() throws {
        let model = sampleModel()
        var items = ["b": "2", "a": "1", "c": "3"]
        let first = try #require(model.tableItems.first { $0.key == "a" })
        let last = try #require(model.tableItems.first { $0.key == "c" })
        model.remove(ids: [first.id, last.id], from: &items)
        #expect(items == ["b": "2"])
    }

    @Test func removeIgnoresUnknownIdentifiers() {
        let model = sampleModel()
        var items = ["a": "1"]
        model.remove(ids: [UUID()], from: &items)
        #expect(items == ["a": "1"])
    }

    @Test func removeSelectionDeletesSelectedRowsAndClearsSelection() throws {
        let model = sampleModel()
        var items = ["b": "2", "a": "1", "c": "3"]
        let row = try #require(model.tableItems.first { $0.key == "b" })
        model.selection = [row.id]
        model.removeSelection(from: &items)
        #expect(items == ["a": "1", "c": "3"])
        #expect(model.selection.isEmpty)
    }

    @Test func commitStoresACompleteDraftAndClosesTheSheet() {
        let model = sampleModel()
        model.beginAdding()
        let draft = KeyValueItemDraft(item: KeyValueItem(key: "k", value: "v"))
        var items = ["a": "1"]
        model.commit(draft, into: &items)
        #expect(items == ["a": "1", "k": "v"])
        #expect(model.editingItem == nil)
    }

    @Test func commitOverwritesAnExistingKey() {
        let model = sampleModel()
        let draft = KeyValueItemDraft(item: KeyValueItem(key: "a", value: "changed"))
        var items = ["a": "1"]
        model.commit(draft, into: &items)
        #expect(items == ["a": "changed"])
    }

    @Test(arguments: [("", ""), ("k", ""), ("", "v")])
    func commitIgnoresIncompleteDrafts(key: String, value: String) {
        let model = sampleModel()
        model.beginAdding()
        let draft = KeyValueItemDraft(item: KeyValueItem(key: key, value: value))
        var items = ["a": "1"]
        model.commit(draft, into: &items)
        #expect(items == ["a": "1"])
        #expect(model.editingItem != nil)
    }

    @Test func draftIsCompleteOnlyWithKeyAndValue() {
        let draft = KeyValueItemDraft(item: KeyValueItem(key: "", value: ""))
        #expect(!draft.isComplete)
        draft.key = "k"
        #expect(!draft.isComplete)
        draft.value = "v"
        #expect(draft.isComplete)
        draft.key = ""
        #expect(!draft.isComplete)
    }

    @Test func contextMenuOffersEditAndRemoveThatActOnTheSelectedRows() throws {
        let model = sampleModel()
        let box = KeyValueItemsBox(["b": "2", "a": "1", "c": "3"])
        let row = try #require(model.tableItems.first { $0.key == "a" })
        let menu = NSHostingMenu(rootView: KeyValueContextMenu(model: model, items: itemsBinding(box), selected: [row.id]))
        menu.update()
        #expect(menu.items.map(\.title) == ["Edit", "Remove"])

        menu.performActionForItem(at: 0)
        #expect(model.editingItem == row)

        menu.performActionForItem(at: 1)
        #expect(box.items == ["b": "2", "c": "3"])
    }

    @Test func tableLoadsRowsOnAppearAndFollowsTheItemsBinding() async throws {
        let box = KeyValueItemsBox(["b": "2", "a": "1"])
        let model = KeyValueTableModel()
        let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
            KeyValueTableHarness(box: box, model: model, validKeys: [], trailing: EmptyView())
        }
        defer { hosted.close() }

        try await eventually(timeout: .seconds(30)) { model.tableItems.map(\.key) == ["a", "b"] }

        box.items["c"] = "3"
        try await eventually(timeout: .seconds(30)) { model.tableItems.map(\.key) == ["a", "b", "c"] }
        #expect(hosted.renders())
    }

    @Test func tableRendersTrailingActionBarContent() async throws {
        let box = KeyValueItemsBox([:])
        let plain = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
            KeyValueTableHarness(box: box, model: KeyValueTableModel(), validKeys: ["x"], trailing: EmptyView())
        }
        defer { plain.close() }
        let trailing = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
            KeyValueTableHarness(box: box, model: KeyValueTableModel(), validKeys: ["x"], trailing: Text("Restore Defaults"))
        }
        defer { trailing.close() }
        try await plain.settle()
        try await trailing.settle()
        #expect(HostedView.pixelsDiffer(plain.snapshot(), trailing.snapshot()))
    }

    @Test func omittedHeaderAndTrailingContentRenderAsNothing() async throws {
        let box = KeyValueItemsBox([:])
        let defaults = KeyValueTable(
            items: itemsBinding(box),
            keyColumnName: "Key",
            valueColumnName: "Value",
            newItemInstruction: "Add an entry"
        )
        let explicit = KeyValueTable(
            items: itemsBinding(box),
            keyColumnName: "Key",
            valueColumnName: "Value",
            newItemInstruction: "Add an entry",
            newItemHeader: { EmptyView() },
            actionBarTrailing: { EmptyView() }
        )
        let model = KeyValueTableModel()
        let item = KeyValueItem(key: "", value: "")
        let size = NSSize(width: 520, height: 320)
        let defaultTable = HostedViewFixture.host(size: size) { defaults }
        defer { defaultTable.close() }
        let explicitTable = HostedViewFixture.host(size: size) { explicit }
        defer { explicitTable.close() }
        let defaultSheet = HostedViewFixture.host(size: size) {
            KeyValueItemSheet(item, form: defaults.form, header: defaults.newItemHeader(), model: model, items: itemsBinding(box))
        }
        defer { defaultSheet.close() }
        let explicitSheet = HostedViewFixture.host(size: size) {
            KeyValueItemSheet(item, form: explicit.form, header: explicit.newItemHeader(), model: model, items: itemsBinding(box))
        }
        defer { explicitSheet.close() }

        try await defaultTable.settle()
        try await explicitTable.settle()
        try await defaultSheet.settle()
        try await explicitSheet.settle()
        #expect(defaults.form.validKeys.isEmpty)
        #expect(!HostedView.pixelsDiffer(defaultTable.snapshot(), explicitTable.snapshot()))
        #expect(!HostedView.pixelsDiffer(defaultSheet.snapshot(), explicitSheet.snapshot()))
    }

    @Test func sheetRendersEveryVariant() async throws {
        let box = KeyValueItemsBox([:])
        let model = KeyValueTableModel()
        let free = KeyValueForm(key: "Key", value: "Value", instruction: "Add an entry", validKeys: [])
        let picked = KeyValueForm(key: "Key", value: "Value", instruction: "Add an entry", validKeys: ["swift", "rust"])
        let item = KeyValueItem(key: "swift", value: "/usr/bin/sourcekit-lsp")

        let plain = HostedViewFixture.host(size: NSSize(width: 520, height: 320)) {
            KeyValueItemSheet(KeyValueItem(key: "", value: ""), form: free, header: EmptyView(), model: model, items: itemsBinding(box))
        }
        defer { plain.close() }
        let withPicker = HostedViewFixture.host(size: NSSize(width: 520, height: 320)) {
            KeyValueItemSheet(item, form: picked, header: Text("Custom header"), model: model, items: itemsBinding(box))
        }
        defer { withPicker.close() }

        try await plain.settle()
        try await withPicker.settle()
        #expect(plain.renders())
        #expect(withPicker.renders())
        #expect(HostedView.pixelsDiffer(plain.snapshot(), withPicker.snapshot()))
    }
}
