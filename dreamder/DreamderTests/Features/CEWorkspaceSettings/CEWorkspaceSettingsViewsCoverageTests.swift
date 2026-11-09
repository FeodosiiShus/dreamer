import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct CEWorkspaceSettingsViewsCoverageTests {
    private func makeList(
        settings: CEWorkspaceSettingsData,
        selection: CEWorkspaceSettingsCoverageSelection
    ) -> CEWorkspaceSettingsTaskListView {
        @Bindable var bindable = selection
        return CEWorkspaceSettingsTaskListView(
            settings: settings,
            selectedTaskID: $bindable.taskID,
            showAddTaskSheet: $bindable.showsSheet
        )
    }

    private func sampleTasks() -> [CETask] {
        [
            CETask(name: "Build", target: "My Mac", command: "make build"),
            CETask(name: "Test", target: "My Mac", workingDirectory: "/tmp", command: "make test")
        ]
    }

    @Test
    func editSelectsTheTaskAndOpensTheSheet() {
        let selection = CEWorkspaceSettingsCoverageSelection()
        let tasks = sampleTasks()
        let settings = CEWorkspaceSettingsData()
        settings.tasks = tasks
        let list = makeList(settings: settings, selection: selection)

        list.edit(tasks[1])

        #expect(selection.taskID == tasks[1].id)
        #expect(selection.showsSheet)

        list.edit(tasks[0])

        #expect(selection.taskID == tasks[0].id)
    }

    @Test
    func deleteRemovesThePersistedTaskAndItsActiveRun() async throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.workspaceSettingsManager)
            let taskManager = try #require(workspace.taskManager)
            let keep = CETask(name: "Keep", command: "true")
            let drop = CETask(name: "Drop", command: "true")
            manager.settings.tasks = [keep, drop]
            try manager.savePreferences()
            taskManager.activeTasks[drop.id] = CEActiveTask(task: drop)
            taskManager.activeTasks[keep.id] = CEActiveTask(task: keep)

            CEWorkspaceSettingsTaskListView.delete(drop, in: manager.settings, manager, taskManager)

            #expect(manager.settings.tasks.map(\.id) == [keep.id])
            #expect(taskManager.activeTasks[drop.id] == nil)
            #expect(taskManager.activeTasks[keep.id] != nil)
            let reloaded = CEWorkspaceSettings(workspaceURL: directory)
            defer { reloaded.cleanUp() }
            #expect(reloaded.settings.tasks.map(\.name) == ["Keep"])
        }
    }

    @Test
    func deletingTheLastTaskRemovesTheSettingsFile() async throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.workspaceSettingsManager)
            let taskManager = try #require(workspace.taskManager)
            let only = CETask(name: "Only", command: "true")
            manager.settings.tasks = [only]
            try manager.savePreferences()
            #expect(FileManager.default.fileExists(atPath: manager.settingsURL.path(percentEncoded: false)))

            CEWorkspaceSettingsTaskListView.delete(only, in: manager.settings, manager, taskManager)

            #expect(manager.settings.tasks.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: manager.settingsURL.path(percentEncoded: false)))
        }
    }

    @Test
    func taskRowActionsEditAndDeleteTheirTask() async throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.workspaceSettingsManager)
            let taskManager = try #require(workspace.taskManager)
            let keep = CETask(name: "Keep", command: "true")
            let drop = CETask(name: "Drop", command: "true")
            manager.settings.tasks = [keep, drop]
            try manager.savePreferences()
            var edited: [UUID] = []
            let row = CEWorkspaceSettingsTaskListView.TaskRow(
                task: drop,
                settings: manager.settings,
                workspaceSettings: manager,
                taskManager: taskManager,
                onEdit: { edited.append($0.id) }
            )

            row.edit()

            #expect(edited == [drop.id])
            #expect(manager.settings.tasks.count == 2)

            row.delete()

            #expect(manager.settings.tasks.map(\.id) == [keep.id])
        }
    }

    @Test
    func taskListRendersTheEmptyAndPopulatedVariants() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.workspaceSettingsManager)
            let list = makeList(settings: manager.settings, selection: CEWorkspaceSettingsCoverageSelection())
            let hosted = try CEWorkspaceSettingsCoverageFixture.host(workspace, size: NSSize(width: 420, height: 160)) {
                VStack { list }
            }
            defer { hosted.close() }
            try await hosted.settle()
            #expect(hosted.renders())
            let empty = hosted.snapshot()

            manager.settings.tasks = sampleTasks()
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))
        }
    }

    @Test
    func contextMenuItemsInvokeTheirCallbacks() throws {
        var edits = 0
        var deletes = 0
        let menu = CEWorkspaceSettingsCoverageFixture.menu {
            CEWorkspaceSettingsTaskListView.TaskContextMenu(
                onEdit: { edits += 1 },
                onDelete: { deletes += 1 }
            )
        }

        #expect(menu.items.map(\.title) == ["Edit", "Delete"])

        menu.performActionForItem(at: 0)
        #expect(edits == 1)
        #expect(deletes == 0)

        menu.performActionForItem(at: 1)
        #expect(edits == 1)
        #expect(deletes == 1)
    }

    @Test
    func settingsViewShowsTheProjectNameAndRendersTaskVariants() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.workspaceSettingsManager)
            manager.settings.project.projectName = "Demo Project"
            let hosted = try CEWorkspaceSettingsCoverageFixture.host(workspace) {
                CEWorkspaceSettingsView(dismiss: {})
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(hosted.views(of: NSTextField.self).contains { $0.stringValue == "Demo Project" })
            let empty = hosted.snapshot()

            manager.settings.tasks = sampleTasks()
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(empty, hosted.snapshot()))
        }
    }

    @Test
    func beginAddingTaskClearsTheSelectionAndOpensTheSheet() {
        let state = CEWorkspaceSettingsSheetState(selectedTaskID: UUID(), showsAddTaskSheet: false)

        state.beginAddingTask()

        #expect(state.selectedTaskID == nil)
        #expect(state.showsAddTaskSheet)
    }

    @Test
    func sheetStateStartsClosedWithoutSelection() {
        let state = CEWorkspaceSettingsSheetState()

        #expect(state.selectedTaskID == nil)
        #expect(!state.showsAddTaskSheet)
    }

    @Test
    func sheetStateKeepsTheInitialSelection() {
        let id = UUID()
        let state = CEWorkspaceSettingsSheetState(selectedTaskID: id, showsAddTaskSheet: true)

        #expect(state.selectedTaskID == id)
        #expect(state.showsAddTaskSheet)
    }

    @Test
    func settingsViewRendersTheAddTaskAndDoneControlsWithoutOpeningASheet() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let hosted = try CEWorkspaceSettingsCoverageFixture.host(workspace) {
                CEWorkspaceSettingsView(dismiss: {})
            }
            defer { hosted.close() }
            try await hosted.settle()

            #expect(hosted.renders())
            #expect(hosted.window.attachedSheet == nil)
        }
    }

    @Test
    func selectedExistingTaskPresentsTheEditSheet() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.workspaceSettingsManager)
            let tasks = sampleTasks()
            manager.settings.tasks = tasks
            let hosted = try CEWorkspaceSettingsCoverageFixture.host(workspace) {
                CEWorkspaceSettingsView(dismiss: {}, selectedTaskID: tasks[1].id, showAddTaskSheet: true)
            }
            defer {
                CEWorkspaceSettingsCoverageFixture.endSheets(of: hosted)
                hosted.close()
            }

            try await eventually(timeout: .seconds(30)) { hosted.window.attachedSheet != nil }
        }
    }

    @Test
    func selectedUnknownTaskFallsBackToTheAddSheet() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let hosted = try CEWorkspaceSettingsCoverageFixture.host(workspace) {
                CEWorkspaceSettingsView(dismiss: {}, selectedTaskID: UUID(), showAddTaskSheet: true)
            }
            defer {
                CEWorkspaceSettingsCoverageFixture.endSheets(of: hosted)
                hosted.close()
            }

            try await eventually(timeout: .seconds(30)) { hosted.window.attachedSheet != nil }
        }
    }
}
