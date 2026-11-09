//
//  EnvironmentVariableListItem.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 01.07.24.
//

import SwiftUI

struct EnvironmentVariableListItem: View {
    @FocusState private var isKeyFocused: Bool

    @Binding var environmentVariable: CETask.EnvironmentVariable
    @Binding var selectedEnvID: UUID?

    /// State variables added to prevent an exception when deleting the item in the onChange event.
    @State var key: String
    @State var value: String

    var delete: (UUID) -> Void
    let isAppActive: @MainActor () -> Bool

    init(
        environmentVariable: Binding<CETask.EnvironmentVariable>,
        selectedEnvID: Binding<UUID?>,
        deleteHandler: @escaping (UUID) -> Void,
        isAppActive: @escaping @MainActor () -> Bool = { NSApp.isActive }
    ) {
        self.delete = deleteHandler
        self.isAppActive = isAppActive

        self._key = State(wrappedValue: environmentVariable.key.wrappedValue)
        self._value = State(wrappedValue: environmentVariable.value.wrappedValue)
        self._environmentVariable = environmentVariable
        self._selectedEnvID = selectedEnvID
    }
    var body: some View {
        HStack {
            TextField("", text: $key)
                .focused($isKeyFocused)
                .disableAutocorrection(true)
                .autocorrectionDisabled()
                .labelsHidden()
                .frame(width: 120)
                .onAppear(perform: focusKeyIfEmpty)
            Divider()
            TextField("", text: $value)
                .disableAutocorrection(true)
                .autocorrectionDisabled()
                .labelsHidden()
        }
        .onChange(of: isKeyFocused, keyFocusChanged)
        .onChange(of: key, keyChanged)
        .onChange(of: value, valueChanged)
    }

    func focusKeyIfEmpty() {
        if environmentVariable.key.isEmpty {
            isKeyFocused = true
        }
    }

    func keyFocusChanged(_ wasFocused: Bool, _ isFocused: Bool) {
        if isFocused {
            if selectedEnvID != environmentVariable.id {
                selectedEnvID = environmentVariable.id
            }
        } else {
            if key.isEmpty, isAppActive() {
                selectedEnvID = nil
                delete(environmentVariable.id)
            }
        }
    }

    func keyChanged(_ oldValue: String, _ newValue: String) {
        environmentVariable.key = newValue
    }

    func valueChanged(_ oldValue: String, _ newValue: String) {
        environmentVariable.value = newValue
    }
}
