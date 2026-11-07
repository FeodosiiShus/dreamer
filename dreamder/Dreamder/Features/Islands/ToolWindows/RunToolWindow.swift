import SwiftUI

struct RunToolWindow: View {
    @Environment(TaskManager.self) private var taskManager
    @Environment(ToolWindowManager.self) private var toolWindowManager

    init() {}

    private var activeTasks: [CEActiveTask] {
        taskManager.activeTasks.values.sorted {
            $0.task.name.localizedStandardCompare($1.task.name) == .orderedAscending
        }
    }

    private var selectedActiveTask: CEActiveTask? {
        if let id = taskManager.taskShowingOutput, let activeTask = taskManager.activeTasks[id] {
            return activeTask
        }
        return activeTasks.first
    }

    private var runnableTask: CETask? {
        if let id = taskManager.selectedTaskID,
           let task = taskManager.availableTasks.first(where: { $0.id == id }) {
            return task
        }
        return taskManager.availableTasks.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Run") {
                ForEach(activeTasks, id: \.task.id) { activeTask in
                    ToolWindowTab(
                        title: activeTask.task.name.isEmpty ? "Task" : activeTask.task.name,
                        icon: "run/run",
                        isSelected: activeTask.task.id == selectedActiveTask?.task.id,
                        onClose: {
                            taskManager.deleteTask(taskID: activeTask.task.id)
                        },
                        action: {
                            taskManager.taskShowingOutput = activeTask.task.id
                        }
                    )
                }
            } actions: {
                if let activeTask = selectedActiveTask {
                    RunTaskActions(activeTask: activeTask)
                }
                ToolWindowActionButton(icon: "general/hide", help: "Hide") {
                    toolWindowManager.hide(.bottom)
                }
            }

            outputContent
        }
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
        .onChange(of: Set(taskManager.activeTasks.keys), initial: true) {
            let newTasks = taskManager.activeTasks
            if let output = taskManager.taskShowingOutput, newTasks[output] != nil {
                return
            }
            let firstTask = newTasks.values
                .sorted { $0.task.name.localizedStandardCompare($1.task.name) == .orderedAscending }
                .first
            taskManager.taskShowingOutput = firstTask?.task.id
        }
    }

    @ViewBuilder private var outputContent: some View {
        if let activeTask = selectedActiveTask {
            TaskOutputView(activeTask: activeTask)
                .id(activeTask.task.id)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Text("Nothing to run")
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.secondaryForeground)

                if let task = runnableTask {
                    Button {
                        Task {
                            await taskManager.runTask(task: task)
                        }
                    } label: {
                        Image("run/run")
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Run \(task.name)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RunTaskActions: View {
    let activeTask: CEActiveTask
    @Environment(TaskManager.self) private var taskManager

    var body: some View {
        HStack(spacing: 2) {
            ToolWindowActionButton(icon: "run/restart", help: "Rerun") {
                Task {
                    await taskManager.runTask(task: activeTask.task)
                }
            }

            ToolWindowActionButton(icon: "run/stop", help: "Stop") {
                taskManager.terminateTask(taskID: activeTask.task.id)
            }
            .disabled(activeTask.status != .running && activeTask.status != .stopped)

            ToolWindowActionButton(icon: "general/delete", help: "Clear") {
                activeTask.clearOutput()
            }
        }
    }
}
