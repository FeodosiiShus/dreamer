import Foundation
import Synchronization
import Testing
@testable import Dreamder

@MainActor
private final class TrustConfirmation {
    private(set) var asked: [URL] = []
    var answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    func confirm(_ root: URL) async -> Bool {
        asked.append(root)
        return answer
    }
}

private final class RestartSleepGate: Sendable {
    private let calls = Mutex(0)

    func shouldReturnImmediately() -> Bool {
        calls.withLock { count in
            count += 1
            return count <= 2
        }
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TaskManagerTrustTests {
    private let fixture: TasksCoverageFixture
    private let leases = PooledDefaultsLeases()
    private let settings: CEWorkspaceSettingsData

    init() throws {
        fixture = try TasksCoverageFixture()
        settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
    }

    private func makeManager(
        root: URL,
        confirmation: TrustConfirmation,
        pretrusted: Bool = false
    ) throws -> TaskManager {
        let trust = WorkspaceTrust(defaults: try leases.make(), confirm: { await confirmation.confirm($0) })
        if pretrusted {
            trust.trust(root)
        }
        return TaskManager(
            workspaceSettings: settings,
            workspaceURL: root,
            discovery: nil,
            selectionDefaults: try leases.make(),
            settings: fixture.settingsStore,
            trust: trust
        )
    }

    @Test
    func aDeclinedWorkspaceNeverRunsItsTasks() async throws {
        try await withTempDir { directory in
            let confirmation = TrustConfirmation(answer: false)
            let manager = try makeManager(root: directory, confirmation: confirmation)
            let task = fixture.makeTask(command: "echo declined-$((1+1))")

            await manager.runTask(task: task)

            #expect(confirmation.asked.count == 1)
            #expect(manager.activeTasks.isEmpty)
            #expect(manager.lastRunTask == nil)
        }
    }

    @Test
    func aDeclinedWorkspaceIsAskedAgainOnTheNextRun() async throws {
        try await withTempDir { directory in
            let confirmation = TrustConfirmation(answer: false)
            let manager = try makeManager(root: directory, confirmation: confirmation)
            let task = fixture.makeTask(command: "true")

            await manager.runTask(task: task)
            await manager.runTask(task: task)

            #expect(confirmation.asked.count == 2)
            #expect(manager.activeTasks.isEmpty)
        }
    }

    @Test
    func aConfirmedWorkspaceRunsAndIsNotAskedAgain() async throws {
        try await withTempDir { directory in
            let confirmation = TrustConfirmation(answer: true)
            let manager = try makeManager(root: directory, confirmation: confirmation)
            let task = fixture.makeTask(command: "echo confirmed-$((1+1))")

            await manager.runTask(task: task)
            let activeTask = try #require(manager.activeTasks[task.id])
            try await eventually { manager.taskStatus(taskID: task.id) == .finished }
            try await fixture.waitForOutput(try #require(activeTask.output), containing: "confirmed-2")
            await manager.runTask(task: task)

            #expect(confirmation.asked == [directory])
            #expect(manager.lastRunTask === task)
        }
    }

    @Test
    func aTrustedWorkspaceRunsWithoutAnyQuestion() async throws {
        try await withTempDir { directory in
            let confirmation = TrustConfirmation(answer: false)
            let manager = try makeManager(root: directory, confirmation: confirmation, pretrusted: true)
            let task = fixture.makeTask(command: "echo trusted-$((1+1))")

            await manager.runTask(task: task)

            let activeTask = try #require(manager.activeTasks[task.id])
            try await fixture.waitForOutput(try #require(activeTask.output), containing: "trusted-2")
            #expect(confirmation.asked.isEmpty)
        }
    }

    @Test
    func theSelectedTaskOfADeclinedWorkspaceDoesNotStart() async throws {
        try await withTempDir { directory in
            let confirmation = TrustConfirmation(answer: false)
            let manager = try makeManager(root: directory, confirmation: confirmation)
            let task = fixture.makeTask(command: "echo declined-$((1+1))")
            settings.tasks = [task]
            manager.selectedTaskID = task.id

            manager.executeActiveTask()

            try await eventually { !confirmation.asked.isEmpty }
            #expect(manager.activeTasks.isEmpty)
        }
    }

    @Test
    func restartingATaskThatIgnoresSigtermEscalatesToSigkill() async throws {
        try await withTempDir { directory in
            let confirmation = TrustConfirmation(answer: false)
            let manager = try makeManager(root: directory, confirmation: confirmation, pretrusted: true)
            let command = """
            trap '' HUP TERM; echo ready-$((40+2)); i=0; while [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
            """
            let task = fixture.makeTask(command: command)
            await manager.runTask(task: task)
            let activeTask = try #require(manager.activeTasks[task.id])
            let output = try #require(activeTask.output)
            try await fixture.waitUntilReady(output, timeout: .seconds(20))
            let firstRunID = activeTask.activeTaskID
            let gate = RestartSleepGate()
            activeTask.sleep = { _ in
                if gate.shouldReturnImmediately() { return }
                try await Task.sleep(for: .seconds(3600))
            }
            defer { activeTask.forceTerminate() }

            await manager.runTask(task: task)

            #expect(activeTask.activeTaskID != firstRunID)
            #expect(activeTask.status == .running)
            try await fixture.waitUntilReady(output, occurrences: 2, timeout: .seconds(20))
        }
    }
}
