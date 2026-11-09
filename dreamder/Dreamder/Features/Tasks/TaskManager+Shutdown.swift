import Foundation

extension TaskManager {
    var hasActiveTasks: Bool {
        activeTasks.values.contains { $0.isActive }
    }

    @discardableResult
    func terminateAllTasks() -> Task<Void, Never> {
        let escalations = activeTasks.values.map { terminations.begin(for: $0) }
        return Task {
            for escalation in escalations {
                await escalation.value
            }
        }
    }

    func shutDownTasks() async {
        stopAllTasks()
        let live = activeTasks.values.filter { $0.isActive }
        try? await withTimeout(
            duration: shutdownTimeout,
            onTimeout: {
                for activeTask in live {
                    await activeTask.forceTerminate()
                }
            },
            operation: {
                for activeTask in live {
                    await activeTask.waitUntilInactive()
                }
            }
        )
    }
}
