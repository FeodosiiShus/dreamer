import Combine
import SwiftUI

struct RunToolbarWidget: View {
    @EnvironmentObject private var workspace: WorkspaceDocument
    @ObservedObject var taskManager: TaskManager

    @State private var isHoveringSelector = false
    @State private var menuAnchor = MainToolbarMenuAnchor()
    @State private var isRunning = false
    @State private var statusListener: AnyCancellable?

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
        .onAppear(perform: updateRunningState)
        .onChange(of: taskManager.selectedTaskID) { _, _ in updateRunningState() }
        .onChange(of: taskManager.activeTasks) { _, _ in updateRunningState() }
        .onDisappear { statusListener?.cancel() }
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

    private func updateRunningState() {
        statusListener?.cancel()
        statusListener = nil
        guard let id = taskManager.selectedTaskID, let activeTask = taskManager.activeTasks[id] else {
            isRunning = false
            return
        }
        isRunning = activeTask.status == .running
        statusListener = activeTask.$status
            .receive(on: RunLoop.main)
            .sink { status in
                isRunning = status == .running
            }
    }
}
