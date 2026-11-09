//
//  KeyValueTable.swift
//  Dreamder
//
//  Created by Abe Malla on 5/16/24.
//

import SwiftUI

struct KeyValueItem: Identifiable, Equatable {
    let id: UUID
    let key: String
    let value: String

    init(key: String, value: String) {
        self.id = UUID()
        self.key = key
        self.value = value
    }
}

struct KeyValueForm {
    let key: String
    let value: String
    let instruction: String
    let validKeys: [String]
}

@Observable
final class KeyValueTableModel {
    var tableItems: [KeyValueItem] = []
    var selection: Set<UUID> = []
    var editingItem: KeyValueItem?

    func reload(from items: [String: String]) {
        tableItems = items
            .sorted { $0.key < $1.key }
            .map { KeyValueItem(key: $0.key, value: $0.value) }
    }

    func beginAdding() {
        editingItem = KeyValueItem(key: "", value: "")
    }

    func beginEditing(ids: Set<UUID>) {
        guard let id = ids.first, let item = tableItems.first(where: { $0.id == id }) else {
            return
        }
        editingItem = item
    }

    func remove(ids: Set<UUID>, from items: inout [String: String]) {
        for item in tableItems where ids.contains(item.id) {
            items.removeValue(forKey: item.key)
        }
    }

    func removeSelection(from items: inout [String: String]) {
        remove(ids: selection, from: &items)
        selection.removeAll()
    }

    func commit(_ draft: KeyValueItemDraft, into items: inout [String: String]) {
        guard draft.isComplete else {
            return
        }
        items[draft.key] = draft.value
        editingItem = nil
    }
}

@Observable
final class KeyValueItemDraft {
    var key: String
    var value: String

    init(item: KeyValueItem) {
        key = item.key
        value = item.value
    }

    var isComplete: Bool {
        !key.isEmpty && !value.isEmpty
    }
}

struct KeyValueContextMenu: View {
    let model: KeyValueTableModel
    @Binding var items: [String: String]
    let selected: Set<UUID>

    var body: some View {
        Button("Edit") { model.beginEditing(ids: selected) }
        Button("Remove") { model.remove(ids: selected, from: &items) }
    }
}

struct KeyValueItemSheet<HeaderView: View>: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var draft: KeyValueItemDraft

    let form: KeyValueForm
    let headerView: HeaderView
    let model: KeyValueTableModel
    @Binding var items: [String: String]

    init(
        _ item: KeyValueItem,
        form: KeyValueForm,
        header: HeaderView,
        model: KeyValueTableModel,
        items: Binding<[String: String]>
    ) {
        self.form = form
        self.headerView = header
        self.model = model
        self._items = items
        self._draft = State(initialValue: KeyValueItemDraft(item: item))
    }

    var body: some View {
        @Bindable var fields = draft
        VStack(spacing: 0) {
            Form {
                Section {
                    if form.validKeys.isEmpty {
                        TextField(form.key, text: $fields.key)
                            .textFieldStyle(.plain)
                    } else {
                        Picker(form.key, selection: $fields.key) {
                            ForEach(form.validKeys, id: \.self) { key in
                                Text(key).tag(key)
                            }
                            Divider()
                            Text("No Selection").tag("")
                        }
                    }
                    TextField(form.value, text: $fields.value)
                        .textFieldStyle(.plain)
                } header: {
                    if HeaderView.self == EmptyView.self {
                        Text(form.instruction)
                    } else {
                        headerView
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .onSubmit { model.commit(draft, into: &items) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { model.commit(draft, into: &items) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isComplete)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: 500)
    }
}

struct KeyValueTable<Header: View, ActionBarView: View>: View {
    @Binding var items: [String: String]

    let form: KeyValueForm
    let newItemHeader: () -> Header
    let actionBarTrailing: () -> ActionBarView

    @State private var model: KeyValueTableModel

    init(
        items: Binding<[String: String]>,
        validKeys: [String] = [],
        keyColumnName: String,
        valueColumnName: String,
        newItemInstruction: String,
        model: KeyValueTableModel = KeyValueTableModel(),
        @ViewBuilder newItemHeader: @escaping () -> Header = { EmptyView() },
        @ViewBuilder actionBarTrailing: @escaping () -> ActionBarView = { EmptyView() }
    ) {
        self._items = items
        self.form = KeyValueForm(
            key: keyColumnName,
            value: valueColumnName,
            instruction: newItemInstruction,
            validKeys: validKeys
        )
        self.newItemHeader = newItemHeader
        self.actionBarTrailing = actionBarTrailing
        self._model = State(initialValue: model)
    }

    var body: some View {
        Table(model.tableItems, selection: $model.selection) {
            TableColumn(form.key) { item in
                Text(item.key)
            }
            TableColumn(form.value) { item in
                Text(item.value)
            }
        }
        .contextMenu(
            forSelectionType: UUID.self,
            menu: { KeyValueContextMenu(model: model, items: $items, selected: $0) },
            primaryAction: { model.beginEditing(ids: $0) }
        )
        .actionBar {
            HStack(spacing: 2) {
                Button { model.beginAdding() } label: { Image(systemName: "plus") }

                Divider()
                    .frame(minHeight: 15)

                Button { model.removeSelection(from: &items) } label: { Image(systemName: "minus") }
                    .disabled(model.selection.isEmpty)
                    .opacity(model.selection.isEmpty ? 0.5 : 1)

                Spacer()

                actionBarTrailing()
            }
        }
        .sheet(item: $model.editingItem) { KeyValueItemSheet($0, form: form, header: newItemHeader(), model: model, items: $items) }
        .clipShape(.rect(cornerRadius: 6))
        .onAppear { model.reload(from: items) }
        .onChange(of: items) { _, newValue in model.reload(from: newValue) }
    }
}
