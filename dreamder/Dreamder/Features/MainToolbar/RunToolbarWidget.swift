import SwiftUI

struct RunToolbarWidget: View {
    @Environment(WorkspaceDocument.self) private var workspace
    let taskManager: TaskManager

    @State private var isHoveringSelector = false
    @State private var menuAnchor = MainToolbarMenuAnchor()

    private var isRunning: Bool {
        guard let id = taskManager.selectedTaskID else { return false }
        return taskManager.activeTasks[id]?.status == .running
    }

    private var selectedTask: CETask? {
        guard let id = taskManager.selectedTaskID else { return taskManager.availableTasks.first }
        return taskManager.availableTasks.first { $0.id == id }
    }

    private var taskName: String {
        guard let task = selectedTask else { return "No Tasks" }
        return task.name.isEmpty ? "Untitled Task" : task.name
    }

    var body: some View {
        HStack(spacing: 2) {
            taskSelector
            MainToolbarIconButton(
                icon: "run/run",
                help: "Run",
                isEnabled: !taskManager.availableTasks.isEmpty,
                action: run
            )
            MainToolbarIconButton(
                icon: "run/stop",
                help: "Stop",
                isEnabled: isRunning,
                action: { taskManager.terminateActiveTask() }
            )
        }
    }

    private var taskSelector: some View {
        HStack(spacing: 4) {
            Text(taskName)
                .font(Islands.uiFont)
                .foregroundColor(Islands.foreground)
                .lineLimit(1)
            Image("general/chevronDown")
                .resizable()
                .interpolation(.high)
                .frame(width: 12, height: 12)
        }
        .padding(.horizontal, 6)
        .frame(
            minWidth: 84,
            maxWidth: 180,
            minHeight: Islands.toolbarControlHeight,
            maxHeight: Islands.toolbarControlHeight,
            alignment: .leading
        )
        .background {
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(isHoveringSelector ? Islands.actionHover : Color.clear)
        }
        .background(MainToolbarMenuAnchorView(anchor: menuAnchor))
        .contentShape(Rectangle())
        .onTapGesture {
            menuAnchor.present(MainToolbarMenuActions.shared.taskMenu(taskManager: taskManager))
        }
        .onHover { isHoveringSelector = $0 }
        .help("Select Run Configuration")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Run Configuration")
        .accessibilityValue(taskName)
        .accessibilityAddTraits(.isButton)
    }

    private func run() {
        if taskManager.selectedTaskID == nil {
            taskManager.selectedTaskID = taskManager.availableTasks.first?.id
        }
        taskManager.executeActiveTask()
        workspace.utilityAreaModel?.selectedTab = .debugConsole
        workspace.toolWindowManager.show(.run)
        taskManager.taskShowingOutput = taskManager.selectedTaskID
    }
}
