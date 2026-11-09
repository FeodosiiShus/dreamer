import Foundation
@testable import Dreamder

@MainActor
final class ActiveTaskGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

@MainActor
final class CompletionFlag {
    private(set) var isSet = false

    func set() {
        isSet = true
    }
}

@MainActor
final class ScriptedActiveTask: CEActiveTask {
    let terminationGate = ActiveTaskGate()
    private(set) var runCount = 0
    private(set) var terminateAndWaitCount = 0
    private(set) var peakConcurrentTerminations = 0
    private var concurrentTerminations = 0

    override func run(workspaceURL: URL?, shell: Shell?) {
        runCount += 1
        updateTaskStatus(to: .running)
    }

    override func terminateAndWait() async {
        terminateAndWaitCount += 1
        concurrentTerminations += 1
        peakConcurrentTerminations = max(peakConcurrentTerminations, concurrentTerminations)
        await terminationGate.wait()
        concurrentTerminations -= 1
        updateTaskStatus(to: .notRunning)
    }
}
