import SwiftUI

struct RunToolbarWidget: View {
    @Environment(WorkspaceDocument.self) private var workspace
    let taskManager: TaskManager

    @State private var menuAnchor: MainToolbarMenuAnchor

    init(taskManager: TaskManager, menuAnchor: MainToolbarMenuAnchor = MainToolbarMenuAnchor()) {
        self.taskManager = taskManager
        _menuAnchor = State(initialValue: menuAnchor)
    }

    static func isRunning(_ taskManager: TaskManager) -> Bool {
        guard let id = taskManager.selectedTaskID else { return false }
        return taskManager.activeTasks[id]?.status == .running
    }

    static func taskName(of taskManager: TaskManager) -> String {
        let selected: CETask?
        if let id = taskManager.selectedTaskID {
            selected = taskManager.availableTasks.first { $0.id == id }
        } else {
            selected = taskManager.availableTasks.first
        }
        guard let task = selected else { return "No Tasks" }
        return task.name.isEmpty ? "Untitled Task" : task.name
    }

    static func runButton(taskManager: TaskManager, workspace: WorkspaceDocument) -> MainToolbarIconButton {
        MainToolbarIconButton(
            icon: "run/run",
            help: "Run",
            isEnabled: !taskManager.availableTasks.isEmpty,
            action: { run(taskManager: taskManager, workspace: workspace) }
        )
    }

    static func stopButton(taskManager: TaskManager) -> MainToolbarIconButton {
        MainToolbarIconButton(
            icon: "run/stop",
            help: "Stop",
            isEnabled: isRunning(taskManager),
            action: { taskManager.terminateActiveTask() }
        )
    }

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                RunTaskSelector(taskManager: taskManager, menuAnchor: menuAnchor)
                Self.runButton(taskManager: taskManager, workspace: workspace)
                Self.stopButton(taskManager: taskManager)
            }
        }
        .fixedSize()
    }

    static func run(taskManager: TaskManager, workspace: WorkspaceDocument) {
        if taskManager.selectedTaskID == nil {
            taskManager.selectedTaskID = taskManager.availableTasks.first?.id
        }
        taskManager.executeActiveTask()
        workspace.toolWindowManager.show(.run)
        taskManager.taskShowingOutput = taskManager.selectedTaskID
    }

    static func presentMenu(on anchor: MainToolbarMenuAnchor, taskManager: TaskManager) {
        anchor.present(MainToolbarMenuActions.shared.taskMenu(taskManager: taskManager))
    }
}

struct RunTaskSelector: View {
    let taskManager: TaskManager
    let menuAnchor: MainToolbarMenuAnchor

    @State private var hover: MainToolbarHoverState

    init(
        taskManager: TaskManager,
        menuAnchor: MainToolbarMenuAnchor,
        hover: MainToolbarHoverState = MainToolbarHoverState()
    ) {
        self.taskManager = taskManager
        self.menuAnchor = menuAnchor
        _hover = State(initialValue: hover)
    }

    func showMenu() {
        RunToolbarWidget.presentMenu(on: menuAnchor, taskManager: taskManager)
    }

    private var taskName: String {
        RunToolbarWidget.taskName(of: taskManager)
    }

    var body: some View {
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
        .padding(.horizontal, 10)
        .frame(
            minWidth: 84,
            maxWidth: 180,
            minHeight: Islands.toolbarControlHeight,
            maxHeight: Islands.toolbarControlHeight,
            alignment: .leading
        )
        .mainToolbarGlass(isHovering: hover.isHovering)
        .background(MainToolbarMenuAnchorView(anchor: menuAnchor))
        .contentShape(Capsule())
        .onTapGesture(perform: showMenu)
        .onHover(perform: hover.setHovering)
        .help("Select Run Configuration")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Run Configuration")
        .accessibilityValue(taskName)
        .accessibilityAddTraits(.isButton)
    }
}
