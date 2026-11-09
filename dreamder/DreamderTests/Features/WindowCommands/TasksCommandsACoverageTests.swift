import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TasksCommandsACoverageTests {
    @MainActor
    private final class RecordingTaskManager: TaskManager {
        private(set) var executeCalls = 0
        private(set) var terminateCalls = 0

        override func executeActiveTask() {
            executeCalls += 1
        }

        override func terminateActiveTask() {
            terminateCalls += 1
        }
    }

    private func makeManager(taskNames: [String]) throws -> RecordingTaskManager {
        let settings = try JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        settings.tasks = taskNames.map { CETask(name: $0, command: "true") }
        return RecordingTaskManager(workspaceSettings: settings, workspaceURL: nil)
    }

    @Test
    func runButtonExecutesTheSelectedTaskAndShowsItsOutput() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            workspace.toolWindowManager.hideAll()
            let manager = try makeManager(taskNames: ["Build"])
            let task = try #require(manager.availableTasks.first)
            manager.selectedTaskID = task.id
            let menu = CommandsACoverageSupport.host {
                TasksCommands.RunButtons(taskManager: manager, toolWindowManager: workspace.toolWindowManager)
            }
            defer { menu.close() }

            #expect(menu.titles == ["Run \"Build\"", "Stop \"Build\"", "Show \"Build\" Output"])
            try menu.click(0)

            #expect(manager.executeCalls == 1)
            #expect(workspace.toolWindowManager.isVisible(.run))
            #expect(manager.taskShowingOutput == task.id)
        }
    }

    @Test
    func runButtonWithoutAToolWindowManagerStillExecutesTheTask() throws {
        let manager = try makeManager(taskNames: ["Build"])
        manager.selectedTaskID = manager.availableTasks.first?.id
        let menu = CommandsACoverageSupport.host {
            TasksCommands.RunButtons(taskManager: manager, toolWindowManager: nil)
        }
        defer { menu.close() }

        try menu.click(0)

        #expect(manager.executeCalls == 1)
        #expect(manager.taskShowingOutput == nil)
    }

    @Test
    func stopAndShowOutputAreDisabledUntilTheTaskHasOutput() throws {
        let manager = try makeManager(taskNames: ["Build"])
        manager.selectedTaskID = manager.availableTasks.first?.id
        let menu = CommandsACoverageSupport.host {
            TasksCommands.RunButtons(taskManager: manager, toolWindowManager: nil)
        }
        defer { menu.close() }

        let states = menu.enabledStates
        try menu.click(1)
        try menu.click(2)

        #expect(states == [true, false, false])
        #expect(manager.terminateCalls == 0)
        #expect(manager.taskShowingOutput == nil)
    }

    @Test
    func stopButtonTerminatesARunningTaskAndShowOutputRevealsIt() throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            workspace.toolWindowManager.hideAll()
            let manager = try makeManager(taskNames: ["Serve"])
            let task = try #require(manager.availableTasks.first)
            manager.selectedTaskID = task.id
            let activeTask = CEActiveTask(task: task)
            activeTask.updateTaskStatus(to: .running)
            manager.activeTasks[task.id] = activeTask
            let menu = CommandsACoverageSupport.host {
                TasksCommands.RunButtons(taskManager: manager, toolWindowManager: workspace.toolWindowManager)
            }
            defer { menu.close() }

            #expect(menu.enabledStates == [true, true, true])
            try menu.click(1)
            try menu.click(2)

            #expect(manager.terminateCalls == 1)
            #expect(workspace.toolWindowManager.isVisible(.run))
            #expect(manager.taskShowingOutput == task.id)
        }
    }

    @Test
    func buttonsAreDisabledWithoutATaskManager() {
        let menu = CommandsACoverageSupport.host {
            TasksCommands.RunButtons(taskManager: nil, toolWindowManager: nil)
        }
        defer { menu.close() }

        #expect(menu.titles == [
            "Run (No Selected Task)",
            "Stop (No Selected Task)",
            "Show (No Selected Task) Output"
        ])
        #expect(menu.enabledStates == [false, false, false])
    }

    @Test
    func chooseTaskButtonsSelectTheTask() throws {
        let manager = try makeManager(taskNames: ["Build", "Test"])
        let second = try #require(manager.availableTasks.last)
        let menu = CommandsACoverageSupport.host {
            TasksCommands.ChooseTaskButtons(taskManager: manager)
        }
        defer { menu.close() }

        #expect(menu.titles == ["Build", "Test"])
        try menu.click(1)

        #expect(manager.selectedTaskID == second.id)
    }

    @Test
    func createTasksOpensTheWorkspaceSettingsWhenThereAreNoTasks() throws {
        let manager = try makeManager(taskNames: [])
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            TasksCommands.ChooseTaskButtons(taskManager: manager, settingsTarget: recorder)
        }
        defer { menu.close() }

        #expect(menu.titles == ["Create Tasks"])
        try menu.click(0)

        #expect(recorder.received == ["openWorkspaceSettings(_:)"])
    }

    @Test
    func createTasksIsOfferedWithoutATaskManager() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            TasksCommands.ChooseTaskButtons(taskManager: nil, settingsTarget: recorder)
        }
        defer { menu.close() }

        try menu.click(0)

        #expect(recorder.received == ["openWorkspaceSettings(_:)"])
    }

    @Test
    func manageTasksOpensTheWorkspaceSettingsWhenEnabled() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            TasksCommands.ManageTasksButton(isEnabled: true, target: recorder)
        }
        defer { menu.close() }

        try menu.click(0)

        #expect(recorder.received == ["openWorkspaceSettings(_:)"])
    }

    @Test
    func manageTasksIsDisabledWithoutAWindowController() throws {
        let recorder = CommandsACoverageRecorder()
        let menu = CommandsACoverageSupport.host {
            TasksCommands.ManageTasksButton(isEnabled: false, target: recorder)
        }
        defer { menu.close() }

        try menu.click(0)

        #expect(menu.enabledStates == [false])
        #expect(recorder.received.isEmpty)
    }

    @Test
    func menuContentListsRunItemsChooserAndManageTasks() throws {
        let manager = try makeManager(taskNames: ["Build"])
        manager.selectedTaskID = manager.availableTasks.first?.id
        let withTasks = CommandsACoverageSupport.host {
            TasksCommands.MenuContent(
                taskManager: manager,
                toolWindowManager: nil,
                hasWindowController: true
            )
        }
        let withoutTasks = CommandsACoverageSupport.host {
            TasksCommands.MenuContent(taskManager: nil, toolWindowManager: nil, hasWindowController: false)
        }
        defer {
            withTasks.close()
            withoutTasks.close()
        }

        #expect(withTasks.titles == [
            "Run \"Build\"",
            "Stop \"Build\"",
            "Show \"Build\" Output",
            "Choose Task...",
            "Manage Tasks..."
        ])
        #expect(withTasks.enabledStates == [true, false, false, true, true])
        #expect(withoutTasks.titles.last == "Manage Tasks...")
        #expect(withoutTasks.enabledStates.last == false)
    }

    @Test
    func buttonsAreDisabledWhenTheTaskManagerHasNoSelectedTask() throws {
        let manager = try makeManager(taskNames: [])
        #expect(manager.selectedTaskID == nil)
        let menu = CommandsACoverageSupport.host {
            TasksCommands.RunButtons(taskManager: manager, toolWindowManager: nil)
        }
        defer { menu.close() }

        #expect(menu.titles == [
            "Run (No Selected Task)",
            "Stop (No Selected Task)",
            "Show (No Selected Task) Output"
        ])
        #expect(menu.enabledStates == [false, false, false])
    }

    @Test
    func commandBodyBuildsWithoutAWindowController() {
        let commands = TasksCommands()

        #expect(commands.taskManager == nil)
        _ = commands.body
    }
}
