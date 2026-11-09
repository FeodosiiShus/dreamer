//
//  EditCETaskView.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 01.07.24.
//

import SwiftUI

struct EditCETaskView: View {
    @Environment(\.dismiss)
    var dismiss

    @Environment(CEWorkspaceSettings.self) private var workspaceSettingsManager
    @Environment(TaskManager.self) private var taskManager
    let task: CETask

    let selectedTaskIndex: Int

    var body: some View {
        EditCETaskContent(
            task: task,
            settings: workspaceSettingsManager,
            taskManager: taskManager,
            dismiss: dismiss.callAsFunction
        )
    }
}

struct EditCETaskContent: View {
    let task: CETask
    let settings: CEWorkspaceSettings
    let taskManager: TaskManager
    let dismiss: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CETaskFormView(task: task)
            Divider()
            HStack {
                Button(role: .destructive, action: delete) {
                    Text("Delete")
                        .foregroundStyle(.red)
                        .frame(minWidth: 56)
                }

                Spacer()

                Button(action: done) {
                    Text("Done")
                        .frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(task.isInvalid)
            }
            .padding()
        }
    }

    func delete() {
        do {
            settings.settings.tasks.removeAll(where: {
                $0.id == task.id
            })
            try settings.savePreferences()
            taskManager.deleteTask(taskID: task.id)
            dismiss()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func done() {
        do {
            try settings.savePreferences()
            dismiss()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
