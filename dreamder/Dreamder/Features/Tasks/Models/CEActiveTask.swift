//
//  CEActiveTask.swift
//  DreamderTests
//
//  Created by Tommy Ludwig on 24.06.24.
//

import SwiftUI
import Observation
import SwiftTerm

/// Stores the state of a task once it's executed
@Observable
class CEActiveTask: Identifiable, Hashable {
    /// The current progress of the task.
    var output: CEActiveTaskTerminalView?

    @ObservationIgnored var hasOutputBeenConfigured: Bool = false
    @ObservationIgnored var openFileLink: (@MainActor (ConsoleFileLinkTarget) -> Void)?

    /// The status of the task.
    private(set) var status: CETaskStatus = .notRunning

    /// The name of the associated task.
    let task: CETask

    /// Prevents tasks overwriting each other.
    /// Say a user cancels one task, then runs it immediately, the cancel message should show and then the
    /// starting message should show. If we don't add this modifier the starting message will be deleted.
    var activeTaskID: UUID = UUID()

    var taskId: String {
        task.id.uuidString + "-" + activeTaskID.uuidString
    }

    var workspaceURL: URL?

    @ObservationIgnored let settings: Settings
    @ObservationIgnored var terminationGrace: Duration = .seconds(5)
    @ObservationIgnored var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    init(task: CETask, settings: Settings = SettingsScope.current ?? .shared) {
        self.task = task
        self.settings = settings
    }

    @MainActor
    func run(workspaceURL: URL?, shell: Shell? = nil) {
        self.workspaceURL = workspaceURL
        self.activeTaskID = UUID() // generate a new ID for this run

        createStatusTaskNotification()
        updateTaskStatus(to: .running)

        let view = output ?? CEActiveTaskTerminalView(activeTask: self)
        view.startProcess(workspaceURL: workspaceURL, shell: shell)

        output = view
    }

    @MainActor
    func handleProcessFinished(terminationStatus: Int32) {
        // Shells add 128 to non-zero exit codes.
        var terminationStatus = terminationStatus
        if terminationStatus > 128 {
            terminationStatus -= 128
        }

        switch terminationStatus {
        case 0:
            output?.newline()
            output?.sendOutputMessage("Finished running \(task.name).")
            output?.newline()

            updateTaskStatus(to: .finished)
            updateTaskNotification(
                title: "Finished Running \(task.name)",
                message: "",
                isLoading: false
            )
        case 2, 9, 15: // SIGINT or SIGTERM
            output?.newline()
            output?.sendOutputMessage("\(task.name) cancelled.")
            output?.newline()

            updateTaskStatus(to: .notRunning)
            updateTaskNotification(
                title: "\(task.name) cancelled",
                message: "",
                isLoading: false
            )
        case 17: // SIGSTOP
            updateTaskStatus(to: .stopped)
        default:
            output?.newline()
            output?.sendOutputMessage("Failed to run \(task.name)")
            output?.newline()

            updateTaskStatus(to: .failed)
            updateTaskNotification(
                title: "Failed Running \(task.name)",
                message: "",
                isLoading: false
            )
        }

        deleteStatusTaskNotification()
    }

    @MainActor
    func suspend() {
        if let shellPID = output?.runningPID(), status == .running {
            ProcessTree.send(SIGSTOP, to: shellPID)
            updateTaskStatus(to: .stopped)
        }
    }

    @MainActor
    func resume() {
        if let shellPID = output?.runningPID(), status == .stopped {
            ProcessTree.send(SIGCONT, to: shellPID)
            updateTaskStatus(to: .running)
        }
    }

    @MainActor
    func terminate() {
        guard let shellPID = output?.runningPID() else { return }
        ProcessTree.send(SIGTERM, to: shellPID)
        resume()
    }

    @MainActor
    func forceTerminate() {
        guard let shellPID = output?.runningPID() else { return }
        ProcessTree.send(SIGKILL, to: shellPID)
        resume()
    }

    @MainActor
    func interrupt() {
        guard let shellPID = output?.runningPID() else { return }
        ProcessTree.send(SIGINT, to: shellPID)
        resume()
    }

    var isActive: Bool {
        status == .running || status == .stopped
    }

    @MainActor
    func terminateAndWait() async {
        guard isActive else { return }
        terminate()
        if await waitUntilInactive(within: terminationGrace) { return }
        forceTerminate()
        _ = await waitUntilInactive(within: terminationGrace)
    }

    @MainActor
    private func waitUntilInactive(within timeout: Duration) async -> Bool {
        let sleeper = self.sleep
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.becameInactive() }
            group.addTask {
                try? await sleeper(timeout)
                return false
            }
            let finished = await group.next() == true
            group.cancelAll()
            return finished
        }
    }

    @MainActor
    private func becameInactive() async -> Bool {
        for await active in Observations({ self.isActive }) where !active {
            return true
        }
        return false
    }

    func waitForExit() async {
        guard let shellPID = output?.runningPID() else { return }
        await Self.waitForProcessGroup(shellPID)
    }

    @concurrent
    private nonisolated static func waitForProcessGroup(_ processIdentifier: pid_t) async {
        var info = siginfo_t()
        waitid(P_PGID, UInt32(processIdentifier), &info, WEXITED | WNOWAIT)
    }

    @MainActor
    func clearOutput() {
        output?.terminal.resetToInitialState()
        output?.feed(text: "")
    }

    private func createStatusTaskNotification() {
        let userInfo: [String: Any] = [
            "id": taskId,
            "action": "createWithPriority",
            "title": "Running \(self.task.name)",
            "message": "Running your task: \(self.task.name).",
            "isLoading": true,
            "workspace": workspaceURL as Any
        ]

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
    }

    private func deleteStatusTaskNotification() {
        let deleteInfo: [String: Any] = [
            "id": taskId,
            "action": "deleteWithDelay",
            "delay": 3.0,
            "workspace": workspaceURL as Any
        ]

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: deleteInfo)
    }

    private func updateTaskNotification(title: String? = nil, message: String? = nil, isLoading: Bool? = nil) {
        var userInfo: [String: Any] = [
            "id": taskId,
            "action": "update",
            "workspace": workspaceURL as Any
        ]
        if let title {
            userInfo["title"] = title
        }
        if let message {
            userInfo["message"] = message
        }
        if let isLoading {
            userInfo["isLoading"] = isLoading
        }

        NotificationCenter.default.post(name: .taskNotification, object: nil, userInfo: userInfo)
    }

    @MainActor
    func updateTaskStatus(to taskStatus: CETaskStatus) {
        self.status = taskStatus
    }

    static func == (lhs: CEActiveTask, rhs: CEActiveTask) -> Bool {
        return lhs.output == rhs.output &&
        lhs.status == rhs.status &&
        lhs.output?.process.shellPid == rhs.output?.process.shellPid &&
        lhs.task == rhs.task
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(output)
        hasher.combine(status)
        hasher.combine(task)
    }
}
