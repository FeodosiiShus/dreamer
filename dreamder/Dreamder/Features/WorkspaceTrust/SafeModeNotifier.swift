import Foundation

@MainActor
struct SafeModeNotifier {
    static let title = "Project is in Safe Mode"
    static let actionTitle = "Trust Project\u{2026}"

    var notifications: @MainActor () -> NotificationManager
    var trust: @MainActor () -> WorkspaceTrust
    var restartServers: @MainActor (String) async -> Void

    static let live = SafeModeNotifier(
        notifications: { NotificationManager.shared },
        trust: { WorkspaceTrust.shared },
        restartServers: { await LSPService.shared.restartServers(inWorkspace: $0) }
    )

    func announce(workspacePath: String, executable: String) {
        let name = (executable as NSString).lastPathComponent
        notifications().post(
            iconSymbol: "lock.shield",
            title: Self.title,
            description: "Safe mode, limited functionality. \(name) from this project was not started. "
                + "Trust the project to use it.",
            actionButtonTitle: Self.actionTitle,
            action: { Task { @MainActor in await trustAndRestart(workspacePath: workspacePath) } },
            isSticky: true
        )
    }

    @discardableResult
    func trustAndRestart(workspacePath: String) async -> Bool {
        let granted = await trust().requestTrust(for: URL(fileURLWithPath: workspacePath, isDirectory: true))
        if granted {
            await restartServers(workspacePath)
        }
        return granted
    }
}
