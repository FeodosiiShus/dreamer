import Foundation

@MainActor
final class TaskEscalations {
    private struct Entry {
        let activeTask: CEActiveTask
        let escalation: Task<Void, Never>
    }

    private var pending: [UUID: Entry] = [:]

    var pendingCount: Int {
        pending.count
    }

    func begin(for activeTask: CEActiveTask) -> Task<Void, Never> {
        let key = UUID()
        let escalation = Task { [weak self] in
            await activeTask.terminateAndWait()
            self?.pending[key] = nil
        }
        pending[key] = Entry(activeTask: activeTask, escalation: escalation)
        return escalation
    }

    func cancelEscalationsWithoutProcess() {
        for entry in pending.values where entry.activeTask.output?.runningPID() == nil {
            entry.escalation.cancel()
        }
        pending = [:]
    }
}
