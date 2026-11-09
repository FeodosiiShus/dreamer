//
//  AddCETaskView.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 01.07.24.
//

import SwiftUI

struct AddCETaskView: View {
    @Environment(\.dismiss)
    var dismiss

    @Environment(CEWorkspaceSettings.self) private var workspaceSettingsManager
    @State private var newTask = CETask(target: "My Mac")

    var body: some View {
        AddCETaskContent(
            task: newTask,
            settings: workspaceSettingsManager,
            dismiss: dismiss.callAsFunction
        )
    }
}

struct AddCETaskContent: View {
    let task: CETask
    let settings: CEWorkspaceSettings
    let dismiss: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CETaskFormView(task: task)
            Divider()
            HStack {
                Button(action: dismiss) {
                    Text("Cancel")
                        .frame(minWidth: 56)
                }
                Spacer()
                Button(action: save) {
                    Text("Save")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(task.isInvalid)
            }
            .padding()
        }
        .accessibilityIdentifier("AddTaskView")
    }

    func save() {
        settings.settings.tasks.append(task)
        try? settings.savePreferences()
        dismiss()
    }
}
