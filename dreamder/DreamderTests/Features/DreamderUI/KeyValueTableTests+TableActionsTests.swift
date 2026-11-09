import AppKit
import Observation
import SwiftUI
import Testing
@testable import Dreamder

extension KeyValueTableTests {
    @Test
    func sheetCommitStoresTheDraftAndClosesTheEditorWhileCancelLeavesItemsAlone() {
        let box = KeyValueItemsBox(["a": "1"])
        let model = KeyValueTableModel()
        let item = KeyValueItem(key: "swift", value: "/usr/bin/sourcekit-lsp")
        model.editingItem = item
        let form = KeyValueForm(key: "Key", value: "Value", instruction: "Add an entry", validKeys: [])
        let sheet = KeyValueItemSheet(item, form: form, header: EmptyView(), model: model, items: itemsBinding(box))

        sheet.cancel()
        #expect(box.items == ["a": "1"])
        #expect(model.editingItem == item)

        sheet.commit()
        #expect(box.items == ["a": "1", "swift": "/usr/bin/sourcekit-lsp"])
        #expect(model.editingItem == nil)
    }

    @Test
    func tableActionsEditRemoveAndOfferTheContextMenuForTheSelection() throws {
        let box = KeyValueItemsBox(["b": "2", "a": "1", "c": "3"])
        let model = sampleModel()
        let table = KeyValueTable(
            items: itemsBinding(box),
            keyColumnName: "Key",
            valueColumnName: "Value",
            newItemInstruction: "Add an entry",
            model: model
        )
        let row = try #require(model.tableItems.first { $0.key == "b" })

        table.edit([row.id])
        #expect(model.editingItem == row)

        let menu = table.menuContent(for: [row.id])
        #expect(menu.selected == [row.id])
        #expect(menu.items == box.items)

        model.selection = [row.id]
        table.removeSelected()
        #expect(box.items == ["a": "1", "c": "3"])
        #expect(model.selection.isEmpty)
    }

    @Test
    func tableDimsTheRemoveButtonOnlyWithoutASelection() async throws {
        let box = KeyValueItemsBox(["b": "2", "a": "1"])
        let size = NSSize(width: 480, height: 320)
        let emptyModel = KeyValueTableModel()
        let selectedModel = KeyValueTableModel()
        let empty = HostedViewFixture.host(size: size) {
            KeyValueTableHarness(box: box, model: emptyModel, validKeys: [], trailing: EmptyView())
        }
        defer { empty.close() }
        let selected = HostedViewFixture.host(size: size) {
            KeyValueTableHarness(box: box, model: selectedModel, validKeys: [], trailing: EmptyView())
        }
        defer { selected.close() }
        try await eventually(timeout: .seconds(30)) { selectedModel.tableItems.count == 2 }

        selectedModel.selection = Set(selectedModel.tableItems.prefix(1).map(\.id))
        try await empty.settle()
        try await selected.settle()

        #expect(!selectedModel.selection.isEmpty)
        #expect(HostedView.pixelsDiffer(empty.snapshot(), selected.snapshot()))
    }
}
