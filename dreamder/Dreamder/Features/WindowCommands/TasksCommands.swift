//
//  TasksCommands.swift
//  Dreamder
//
//  Created by Khan Winter on 7/8/25.
//

import SwiftUI

struct TasksCommands: Commands {
    @UpdatingWindowController var windowController: DreamderWindowController?

    var taskManager: TaskManager? {
        windowController?.workspace?.taskManager
    }

    var body: some Commands {
        CommandMenu("Tasks") {
            MenuContent(
                taskManager: taskManager,
                toolWindowManager: windowController?.workspace?.toolWindowManager,
                hasWindowController: windowController != nil,
                settingsTarget: windowController
            )
        }
    }

    static func openSettings(target: Any?) {
        NSApp.sendAction(
            #selector(DreamderWindowController.openWorkspaceSettings(_:)),
            to: target,
            from: nil
        )
    }
}

extension TasksCommands {
    struct MenuContent: View {
        let taskManager: TaskManager?
        let toolWindowManager: ToolWindowManager?
        let hasWindowController: Bool
        var settingsTarget: Any?

        var body: some View {
            RunButtons(taskManager: taskManager, toolWindowManager: toolWindowManager)

            Divider()

            Menu {
                ChooseTaskButtons(taskManager: taskManager, settingsTarget: settingsTarget)
            } label: {
                Text("Choose Task...")
            }
            .disabled(taskManager?.availableTasks.isEmpty == true)

            ManageTasksButton(isEnabled: hasWindowController, target: settingsTarget)
        }
    }

    struct RunButtons: View {
        let taskManager: TaskManager?
        let toolWindowManager: ToolWindowManager?

        private var activeTaskStatus: CETaskStatus {
            guard let taskManager else { return .notRunning }
            return taskManager.activeTasks[taskManager.selectedTaskID ?? UUID()]?.status ?? .notRunning
        }

        var body: some View {
            let selectedTaskName: String = if let selectedTask = taskManager?.selectedTask {
                "\"" + selectedTask.name + "\""
            } else {
                "(No Selected Task)"
            }

            Button("Run \(selectedTaskName)", systemImage: "play.fill") {
                taskManager?.executeActiveTask()
                showOutput()
            }
            .keymapShortcut(.runTask)
            .disabled(taskManager?.selectedTaskID == nil)

            Button("Stop \(selectedTaskName)", systemImage: "stop.fill") {
                taskManager?.terminateActiveTask()
            }
            .keymapShortcut(.stopTask)
            .disabled(activeTaskStatus != .running)

            Button("Show \(selectedTaskName) Output") {
                showOutput()
            }
            .keymapShortcut(.showTaskOutput)
            // Disable when there's no output yet
            .disabled(taskManager?.activeTasks[taskManager?.selectedTaskID ?? UUID()] == nil)
        }

        private func showOutput() {
            guard let toolWindowManager else {
                return
            }
            toolWindowManager.show(.run)
            taskManager?.taskShowingOutput = taskManager?.selectedTaskID
        }
    }

    struct ChooseTaskButtons: View {
        let taskManager: TaskManager?
        var settingsTarget: Any?

        var body: some View {
            if let taskManager {
                ForEach(taskManager.availableTasks) { task in
                    Button(task.name) {
                        taskManager.selectedTaskID = task.id
                    }
                }
            }

            if taskManager?.availableTasks.isEmpty ?? true {
                Button("Create Tasks") {
                    TasksCommands.openSettings(target: settingsTarget)
                }
            }
        }
    }

    struct ManageTasksButton: View {
        let isEnabled: Bool
        var target: Any?

        var body: some View {
            Button("Manage Tasks...") {
                TasksCommands.openSettings(target: target)
            }
            .keymapShortcut(.manageTasks)
            .disabled(!isEnabled)
        }
    }
}
