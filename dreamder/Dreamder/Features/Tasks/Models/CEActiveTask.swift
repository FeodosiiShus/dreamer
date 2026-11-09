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
    @ObservationIgnored private var isStopRequested = false
    @ObservationIgnored var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    init(task: CETask, settings: Settings = SettingsScope.current ?? .shared) {
        self.task = task
        self.settings = settings
    }

    @MainActor
    func run(workspaceURL: URL?, shell: Shell? = nil) {
        self.workspaceURL = workspaceURL
        self.activeTaskID = UUID() // generate a new ID for this run
        self.isStopRequested = false

        createStatusTaskNotification()
        updateTaskStatus(to: .running)

        let view = output ?? CEActiveTaskTerminalView(activeTask: self)
        output = view
        if !view.startProcess(workspaceURL: workspaceURL, shell: shell) {
            recordFailure()
            deleteStatusTaskNotification()
        }
    }

    nonisolated enum Outcome: Equatable {
        case finished
        case cancelled
        case failed

        private static let cancellationSignals: Set<Int32> = [SIGINT, SIGTERM, SIGKILL, SIGHUP]
        private static let shellSignalOffset: Int32 = 128

        init(exit: ProcessExit, stopRequested: Bool) {
            switch exit {
            case let .exited(code) where code == 0:
                self = .finished
            case let .exited(code) where Self.cancellationSignals.contains(code - Self.shellSignalOffset):
                self = .cancelled
            case let .signaled(signal) where Self.cancellationSignals.contains(signal):
                self = .cancelled
            case .exited where stopRequested:
                self = .cancelled
            default:
                self = .failed
            }
        }
    }

    @MainActor
    func handleProcessFinished(exit: ProcessExit) {
        switch Outcome(exit: exit, stopRequested: isStopRequested) {
        case .finished:
            output?.newline()
            output?.sendOutputMessage("Finished running \(task.name).")
            output?.newline()

            updateTaskStatus(to: .finished)
            updateTaskNotification(
                title: "Finished Running \(task.name)",
                message: "",
                isLoading: false
            )
        case .cancelled:
            output?.newline()
            output?.sendOutputMessage("\(task.name) cancelled.")
            output?.newline()

            updateTaskStatus(to: .notRunning)
            updateTaskNotification(
                title: "\(task.name) cancelled",
                message: "",
                isLoading: false
            )
        case .failed:
            output?.newline()
            output?.sendOutputMessage("Failed to run \(task.name)")
            output?.newline()

            recordFailure()
        }

        deleteStatusTaskNotification()
    }

    private func recordFailure() {
        updateTaskStatus(to: .failed)
        updateTaskNotification(
            title: "Failed Running \(task.name)",
            message: "",
            isLoading: false
        )
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
    func hangUp() {
        send(SIGHUP)
    }

    @MainActor
    func terminate() {
        send(SIGTERM)
    }

    @MainActor
    func forceTerminate() {
        send(SIGKILL)
    }

    @MainActor
    func interrupt() {
        send(SIGINT)
    }

    @MainActor
    private func send(_ signal: Int32) {
        guard let shellPID = output?.runningPID() else { return }
        isStopRequested = true
        ProcessTree.send(signal, to: shellPID)
        resume()
    }

    var isActive: Bool {
        status == .running || status == .stopped
    }

    @MainActor
    func terminateAndWait() async {
        let run = activeTaskID
        let escalation = [hangUp, terminate, forceTerminate]
        for signalProcess in escalation {
            guard !Task.isCancelled, isRunActive(run) else { return }
            signalProcess()
            if await waitUntilInactive(run: run, within: terminationGrace) { return }
        }
    }

    @MainActor
    func waitUntilInactive() async {
        _ = await becameInactive(run: activeTaskID)
    }

    @MainActor
    private func isRunActive(_ run: UUID) -> Bool {
        activeTaskID == run && isActive
    }

    @MainActor
    private func waitUntilInactive(run: UUID, within timeout: Duration) async -> Bool {
        let sleeper = self.sleep
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.becameInactive(run: run) }
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
    private func becameInactive(run: UUID) async -> Bool {
        for await active in Observations({ self.isRunActive(run) }) where !active {
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
