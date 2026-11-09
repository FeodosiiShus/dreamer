//
//  CEWorkspaceSettingsTaskListView.swift
//  Dreamder
//
//  Created by Tommy Ludwig on 01.07.24.
//

import SwiftUI

struct CEWorkspaceSettingsTaskListView: View {
    @Environment(CEWorkspaceSettings.self) private var workspaceSettingsManager
    @Environment(TaskManager.self) private var taskManager

    let settings: CEWorkspaceSettingsData

    @Binding var selectedTaskID: UUID?
    @Binding var showAddTaskSheet: Bool

    var body: some View {
        if settings.tasks.isEmpty {
            Text("No tasks")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(settings.tasks) { task in
                TaskRow(
                    task: task,
                    settings: settings,
                    workspaceSettings: workspaceSettingsManager,
                    taskManager: taskManager,
                    onEdit: edit
                )
            }
        }
    }

    func edit(_ task: CETask) {
        selectedTaskID = task.id
        showAddTaskSheet = true
    }

    static func delete(
        _ task: CETask,
        in settings: CEWorkspaceSettingsData,
        _ workspaceSettings: CEWorkspaceSettings,
        _ taskManager: TaskManager
    ) {
        settings.tasks.removeAll { $0.id == task.id }
        try? workspaceSettings.savePreferences()
        taskManager.deleteTask(taskID: task.id)
    }

    struct TaskRow: View {
        let task: CETask
        let settings: CEWorkspaceSettingsData
        let workspaceSettings: CEWorkspaceSettings
        let taskManager: TaskManager
        let onEdit: (CETask) -> Void

        func edit() {
            onEdit(task)
        }

        func delete() {
            CEWorkspaceSettingsTaskListView.delete(task, in: settings, workspaceSettings, taskManager)
        }

        var body: some View {
            TaskTile(task: task)
                .contentShape(Rectangle())
                .onTapGesture(perform: edit)
                .contextMenu {
                    TaskContextMenu(onEdit: edit, onDelete: delete)
                }
        }
    }

    struct TaskContextMenu: View {
        let onEdit: () -> Void
        let onDelete: () -> Void

        var body: some View {
            Button(action: onEdit) {
                Text("Edit")
            }
            Button(action: onDelete) {
                Text("Delete")
            }
        }
    }

    // Every task as to be observed individually
    private struct TaskTile: View {
        let task: CETask
        var body: some View {
            HStack {
                Text(task.name)
                Spacer()
                Group {
                    Text(task.command)
                    Image(systemName: "chevron.right")
                }
                .font(.system(.body, design: .monospaced))
            }
        }
    }
}
