import Foundation

struct RunConfigurationSection: Identifiable {
    static let workspaceTitle = "Workspace"

    let id: String
    let title: String
    let subtitle: String?
    let kind: TaskSourceKind?
    let tasks: [CETask]

    var isDiscovered: Bool {
        kind != nil
    }

    init(userTasks: [CETask]) {
        id = CETask.workspaceSource
        title = Self.workspaceTitle
        subtitle = nil
        kind = nil
        tasks = userTasks
    }

    init(group: DiscoveredTaskGroup) {
        id = group.id
        title = group.title
        subtitle = group.manifest
        kind = group.kind
        tasks = group.tasks.map { discovered in
            CETask(
                name: discovered.name,
                workingDirectory: discovered.workingDirectory,
                command: discovered.command,
                source: group.id
            )
        }
    }

    private init(copying section: RunConfigurationSection, tasks: [CETask]) {
        id = section.id
        title = section.title
        subtitle = section.subtitle
        kind = section.kind
        self.tasks = tasks
    }

    func replacingTasks(_ replacement: [CETask]) -> RunConfigurationSection {
        RunConfigurationSection(copying: self, tasks: replacement)
    }

    static func commandKey(for task: CETask) -> String {
        let directory = task.workingDirectory == "." ? "" : task.workingDirectory
        return directory + "\u{0}" + task.command
    }
}
