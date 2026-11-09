import SwiftUI

struct RunConfigurationActions {
    let taskManager: TaskManager
    let workspaceSettings: CEWorkspaceSettings?

    func select(_ task: CETask) {
        taskManager.selectedTaskID = task.id
    }

    @discardableResult
    func run(_ task: CETask) -> Task<Void, Never> {
        select(task)
        return Task {
            await taskManager.runTask(task: task)
            taskManager.taskShowingOutput = task.id
        }
    }

    func save(_ task: CETask) {
        guard taskManager.saveDiscoveredTask(task) != nil else { return }
        try? workspaceSettings?.savePreferences()
    }
}

struct RunConfigurationsListView: View {
    let taskManager: TaskManager

    @Environment(WorkspaceDocument.self) private var workspace: WorkspaceDocument?

    private var actions: RunConfigurationActions {
        RunConfigurationActions(taskManager: taskManager, workspaceSettings: workspace?.workspaceSettingsManager)
    }

    var body: some View {
        let selectedID = taskManager.selectedTask?.id
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(taskManager.runConfigurationSections) { section in
                    RunConfigurationSectionHeader(section: section)
                    ForEach(section.tasks) { task in
                        RunConfigurationRow(
                            task: task,
                            isSelected: task.id == selectedID,
                            isDiscovered: section.isDiscovered,
                            status: taskManager.taskStatus(taskID: task.id),
                            actions: actions
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("run-configurations")
    }
}

struct RunConfigurationSectionHeader: View {
    let section: RunConfigurationSection

    var body: some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(Islands.smallFont)
                .fontWeight(.semibold)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.listRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

@Observable
final class RunConfigurationHoverState {
    private(set) var isHovering: Bool

    init(isHovering: Bool = false) {
        self.isHovering = isHovering
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }
}

struct RunConfigurationRow: View {
    let task: CETask
    let isSelected: Bool
    let isDiscovered: Bool
    let status: CETaskStatus
    let actions: RunConfigurationActions

    @State private var hoverState: RunConfigurationHoverState

    init(
        task: CETask,
        isSelected: Bool,
        isDiscovered: Bool,
        status: CETaskStatus,
        actions: RunConfigurationActions,
        hoverState: RunConfigurationHoverState = RunConfigurationHoverState()
    ) {
        self.task = task
        self.isSelected = isSelected
        self.isDiscovered = isDiscovered
        self.status = status
        self.actions = actions
        _hoverState = State(initialValue: hoverState)
    }

    private var title: String {
        task.name.isEmpty ? "Untitled Task" : task.name
    }

    func select() {
        actions.select(task)
    }

    func save() {
        actions.save(task)
    }

    func run() {
        actions.run(task)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image("run/run")
                .resizable()
                .frame(width: 16, height: 16)
                .opacity(status == .running ? 1 : 0.6)
            Text(title)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isDiscovered {
                Button(action: save, label: {
                    Image("general/add")
                        .resizable()
                        .frame(width: 16, height: 16)
                })
                .buttonStyle(.plain)
                .help("Save to Workspace Settings")
                .accessibilityLabel("Save \(title)")
            }
            Button(action: run, label: {
                Image("run/run")
                    .resizable()
                    .frame(width: 16, height: 16)
            })
            .buttonStyle(.plain)
            .help("Run \(title)")
            .accessibilityLabel("Run \(title)")
        }
        .padding(.horizontal, 12)
        .padding(.leading, 8)
        .frame(height: Islands.listRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(isSelected ? Islands.selection : (hoverState.isHovering ? Islands.hover : .clear))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover(perform: hoverState.setHovering)
    }
}
