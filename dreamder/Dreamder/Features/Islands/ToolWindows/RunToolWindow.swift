import SwiftUI

struct RunToolWindowActions {
    let taskManager: TaskManager

    func select(_ activeTask: CEActiveTask) -> () -> Void {
        { taskManager.taskShowingOutput = activeTask.task.id }
    }

    func close(_ activeTask: CEActiveTask) -> () -> Void {
        { taskManager.deleteTask(taskID: activeTask.task.id) }
    }

    func run(_ task: CETask) -> () -> Void {
        {
            Task {
                await taskManager.runTask(task: task)
            }
        }
    }

    func stop(_ activeTask: CEActiveTask) -> () -> Void {
        { taskManager.terminateTask(taskID: activeTask.task.id) }
    }

    func clear(_ activeTask: CEActiveTask) -> () -> Void {
        { activeTask.clearOutput() }
    }
}

struct RunToolWindow: View {
    @Environment(TaskManager.self) private var taskManager
    @Environment(ToolWindowManager.self) private var toolWindowManager
    @Environment(WorkspaceDocument.self) private var workspace: WorkspaceDocument?

    @State private var showsConfigurations = false

    init() {}

    private var actions: RunToolWindowActions {
        RunToolWindowActions(taskManager: taskManager)
    }

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

    private var fileLinkOpener: (@MainActor (ConsoleFileLinkTarget) -> Void)? {
        guard let workspace else { return nil }
        return { [weak workspace] target in
            workspace.map {
                EditorLocationNavigation.open(
                    fileURL: target.url,
                    line: target.line,
                    column: target.column,
                    workspace: $0
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolWindowHeader(title: "Run") {
                ForEach(activeTasks, id: \.task.id) { activeTask in
                    ToolWindowTab(
                        title: activeTask.task.name.isEmpty ? "Task" : activeTask.task.name,
                        icon: "run/run",
                        isSelected: activeTask.task.id == selectedActiveTask?.task.id,
                        onClose: actions.close(activeTask),
                        action: actions.select(activeTask)
                    )
                }
            } actions: {
                ToolWindowActionButton(
                    icon: "general/menu",
                    help: "Run Configurations",
                    action: toggleConfigurations
                )
                if let activeTask = selectedActiveTask {
                    RunTaskActions(activeTask: activeTask)
                }
                ToolWindowActionButton(
                    icon: "general/hide",
                    help: "Hide",
                    action: toolWindowManager.hideCallback(for: .run)
                )
            }

            outputContent
        }
        .background(Color.clear)
        .task { await taskManager.refreshDiscoveredTasks() }
        .onChange(of: taskManager.taskShowingOutput) { showsConfigurations = false }
        .onChange(of: Set(taskManager.activeTasks.keys), initial: true) {
            let newTasks = taskManager.activeTasks
            for activeTask in newTasks.values {
                activeTask.openFileLink = fileLinkOpener
            }
            if let output = taskManager.taskShowingOutput, newTasks[output] != nil {
                return
            }
            let firstTask = newTasks.values
                .sorted { $0.task.name.localizedStandardCompare($1.task.name) == .orderedAscending }
                .first
            taskManager.taskShowingOutput = firstTask?.task.id
        }
    }

    func toggleConfigurations() {
        showsConfigurations.toggle()
    }

    @ViewBuilder private var outputContent: some View {
        if let activeTask = selectedActiveTask, !showsConfigurations {
            TaskOutputView(activeTask: activeTask)
                .id(activeTask.task.id)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if taskManager.runConfigurationSections.isEmpty {
            Text("Nothing to run")
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RunConfigurationsListView(taskManager: taskManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RunTaskActions: View {
    let activeTask: CEActiveTask
    @Environment(TaskManager.self) private var taskManager

    private var actions: RunToolWindowActions {
        RunToolWindowActions(taskManager: taskManager)
    }

    var body: some View {
        HStack(spacing: 2) {
            ToolWindowActionButton(icon: "run/restart", help: "Rerun", action: actions.run(activeTask.task))

            ToolWindowActionButton(icon: "run/stop", help: "Stop", action: actions.stop(activeTask))
                .disabled(activeTask.status != .running && activeTask.status != .stopped)

            ToolWindowActionButton(icon: "general/delete", help: "Clear", action: actions.clear(activeTask))
        }
    }
}
