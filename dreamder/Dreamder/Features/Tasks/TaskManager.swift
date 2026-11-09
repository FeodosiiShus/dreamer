//
//  TaskManager.swift
//  DreamderTests
//
//  Created by Tommy Ludwig on 24.06.24.
//

import SwiftUI
import Observation

/// This class handles the execution of tasks
@MainActor
@Observable
class TaskManager {
    var activeTasks: [UUID: CEActiveTask] = [:]
    var selectedTaskID: UUID? {
        didSet {
            guard !isApplyingFallbackSelection else { return }
            selectionIsFallback = false
            persistSelection()
        }
    }
    var taskShowingOutput: UUID?
    private(set) var discoveredSections: [RunConfigurationSection] = []
    var lastRunTask: CETask?

    let workspaceSettings: CEWorkspaceSettingsData

    private var workspaceURL: URL?
    @ObservationIgnored private var settingsTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    private let discovery: TaskDiscovery?
    private let selectionDefaults: UserDefaults
    private let settings: Settings
    private let trust: WorkspaceTrust
    @ObservationIgnored private var persistedSelectionID: UUID?
    @ObservationIgnored private var selectionIsFallback = true
    @ObservationIgnored private var isApplyingFallbackSelection = false
    @ObservationIgnored private var runsInFlight: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var shutdownTimeout: Duration = .seconds(2)
    let terminations = TaskEscalations()

    init(
        workspaceSettings: CEWorkspaceSettingsData,
        workspaceURL: URL?,
        discovery: TaskDiscovery? = nil,
        selectionDefaults: UserDefaults = .standard,
        settings: Settings = SettingsScope.current ?? .shared,
        trust: WorkspaceTrust = .shared
    ) {
        self.workspaceURL = workspaceURL
        self.workspaceSettings = workspaceSettings
        self.selectionDefaults = selectionDefaults
        self.settings = settings
        self.trust = trust
        self.discovery = discovery ?? workspaceURL.map { root in
            TaskDiscovery(rootURL: root, isExcluded: { url in
                ExcludedDirectories.rules(covering: url).isExcluded(url)
            })
        }
        persistedSelectionID = Self.selectionKey(for: workspaceURL)
            .flatMap { selectionDefaults.string(forKey: $0) }
            .flatMap { UUID(uuidString: $0) }
        startObservingSettings()
        updateSelectedTaskID()
        startDiscovery()
    }

    isolated deinit {
        settingsTask?.cancel()
        discoveryTask?.cancel()
        terminations.cancelEscalationsWithoutProcess()
    }

    private static func selectionKey(for workspaceURL: URL?) -> String? {
        workspaceURL.map { "dreamder.selectedTask." + $0.standardizedFileURL.path(percentEncoded: false) }
    }

    private func persistSelection() {
        guard let key = Self.selectionKey(for: workspaceURL) else { return }
        persistedSelectionID = selectedTaskID
        if let selectedTaskID {
            selectionDefaults.set(selectedTaskID.uuidString, forKey: key)
        } else {
            selectionDefaults.removeObject(forKey: key)
        }
    }

    private func startDiscovery() {
        guard discovery != nil else { return }
        discoveryTask = Task { [weak self] in
            await self?.refreshDiscoveredTasks()
        }
    }

    func refreshDiscoveredTasks() async {
        guard let discovery else { return }
        applyDiscoveredGroups(await discovery.discover())
    }

    func applyDiscoveredGroups(_ groups: [DiscoveredTaskGroup]) {
        discoveredSections = groups.map(RunConfigurationSection.init(group:))
        updateSelectedTaskID()
    }

    private func startObservingSettings() {
        let workspaceSettings = workspaceSettings
        settingsTask = Task { [weak self] in
            let changes = Observations { workspaceSettings.tasks }
            for await _ in changes {
                guard let self else { return }
                self.updateSelectedTaskID()
            }
        }
    }

    var selectedTask: CETask? {
        if let selectedTaskID {
            return availableTasks.first { $0.id == selectedTaskID }
        }
        return fallbackSelectionID.flatMap { id in availableTasks.first { $0.id == id } }
    }

    var availableTasks: [CETask] {
        runConfigurationSections.flatMap(\.tasks)
    }

    var runConfigurationSections: [RunConfigurationSection] {
        let userTasks = workspaceSettings.tasks
        var sections: [RunConfigurationSection] = []
        if !userTasks.isEmpty {
            sections.append(RunConfigurationSection(userTasks: userTasks))
        }
        let taken = Set(userTasks.map { RunConfigurationSection.commandKey(for: $0) })
        for section in discoveredSections {
            let remaining = section.tasks.filter { !taken.contains(RunConfigurationSection.commandKey(for: $0)) }
            if !remaining.isEmpty {
                sections.append(section.replacingTasks(remaining))
            }
        }
        return sections
    }

    var hasRunningTasks: Bool {
        activeTasks.values.contains { $0.status == .running }
    }

    func taskStatus(taskID: UUID) -> CETaskStatus {
        return self.activeTasks[taskID]?.status ?? .notRunning
    }

    private var fallbackSelectionID: UUID? {
        let tasks = availableTasks
        if let persistedSelectionID, tasks.contains(where: { $0.id == persistedSelectionID }) {
            return persistedSelectionID
        }
        return tasks.first?.id
    }

    func updateSelectedTaskID() {
        let tasks = availableTasks
        if let selectedTaskID, tasks.contains(where: { $0.id == selectedTaskID }), !selectionIsFallback { return }
        isApplyingFallbackSelection = true
        selectedTaskID = fallbackSelectionID
        isApplyingFallbackSelection = false
        selectionIsFallback = true
    }

    func executeActiveTask() {
        guard let task = availableTasks.first(where: { $0.id == selectedTaskID }) else { return }
        Task {
            await runTask(task: task)
        }
    }

    private func isAllowedToRun() async -> Bool {
        guard let workspaceURL else { return true }
        return await trust.requestTrust(for: workspaceURL)
    }

    func runTask(task: CETask) async {
        guard await isAllowedToRun() else { return }
        lastRunTask = task
        if let inFlight = runsInFlight[task.id] {
            await inFlight.value
            return
        }
        let run = Task { await self.start(task) }
        runsInFlight[task.id] = run
        await run.value
    }

    private func start(_ task: CETask) async {
        defer { runsInFlight[task.id] = nil }
        if let activeTask = activeTasks[task.id] {
            await activeTask.terminateAndWait()
            guard activeTasks[task.id] === activeTask else { return }
            activeTask.run(workspaceURL: workspaceURL)
        } else {
            let runningTask = CEActiveTask(task: task, settings: settings)
            runningTask.run(workspaceURL: workspaceURL)
            activeTasks[task.id] = runningTask
        }
    }

    func terminateActiveTask() {
        guard let taskID = selectedTaskID else {
            return
        }

        terminateTask(taskID: taskID)
    }

    /// Suspends the task associated with the given task ID.
    ///
    /// Suspending a task means that the task's execution is paused.
    /// The task will not run or consume CPU time until it is resumed.
    /// If there is no task associated with the given ID, or if the task is not currently running,
    /// this method does nothing.
    ///
    /// - Parameter taskID: The ID of the task to suspend.
    func suspendTask(taskID: UUID) {
        if let activeTask = activeTasks[taskID] {
            activeTask.suspend()
        }
    }

    /// Resumes the task associated with the given task ID.
    ///
    /// If there is no task associated with the given ID, or if the task is not currently suspended,
    /// this method does nothing.
    ///
    /// - Parameter taskID: The ID of the task to resume.
    func resumeTask(taskID: UUID) {
        if let activeTask = activeTasks[taskID] {
            activeTask.resume()
        }
    }

    /// Terminates the task associated with the given task ID.
    ///
    /// Terminating a task sends a SIGTERM signal to the process, which is a request to the process to stop execution.
    /// Most processes will stop when they receive a SIGTERM signal.
    /// However, a process can choose to ignore this signal.
    ///
    /// If there is no task associated with the given ID,
    /// or if the task is not currently running, this method does nothing.
    ///
    /// - Parameter taskID: The ID of the task to terminate.
    @discardableResult
    func terminateTask(taskID: UUID) -> Task<Void, Never>? {
        guard let activeTask = activeTasks[taskID] else { return nil }
        return terminations.begin(for: activeTask)
    }

    /// Interrupts the task associated with the given task ID.
    ///
    /// Interrupting a task sends a SIGINT signal to the process, which is a request to the process to stop execution.
    /// This is the same signal that is sent when you press Ctrl+C in a terminal.
    /// It's a polite request to the process to stop what it's doing and terminate.
    /// However, the process can choose to ignore this signal or handle it in a custom way.
    ///
    /// If there is no task associated with the given ID, or if the task is not currently running,
    /// this method does nothing.
    ///
    /// - Parameter taskID: The ID of the task to interrupt.
    func interruptTask(taskID: UUID) {
        if let activeTask = activeTasks[taskID] {
            activeTask.interrupt()
        }
    }

    func stopAllTasks() {
        for (id, _) in activeTasks {
            interruptTask(taskID: id)
        }
    }

    @discardableResult
    func rerunLastTask() -> Task<Void, Never>? {
        guard let lastRunTask else { return nil }
        return Task {
            await runTask(task: lastRunTask)
        }
    }

    @discardableResult
    func saveDiscoveredTask(_ task: CETask) -> CETask? {
        guard task.source != CETask.workspaceSource else { return nil }
        let existingNames = Set(workspaceSettings.tasks.map(\.name))
        var name = task.name
        var suffix = 2
        while existingNames.contains(name) {
            name = "\(task.name) (\(suffix))"
            suffix += 1
        }
        let saved = CETask(
            name: name,
            target: "My Mac",
            workingDirectory: task.workingDirectory,
            command: task.command,
            environmentVariables: task.environmentVariables
        )
        let wasSelected = selectedTaskID == task.id
        workspaceSettings.tasks.append(saved)
        if wasSelected {
            selectedTaskID = saved.id
        }
        return saved
    }

    @discardableResult
    func deleteTask(taskID: UUID) -> Task<Void, Never>? {
        let termination = terminateTask(taskID: taskID)
        activeTasks.removeValue(forKey: taskID)
        return termination
    }
}
