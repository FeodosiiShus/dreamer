import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class ConfigurationsRecordingTaskManager: TaskManager {
    private(set) var ranTasks: [CETask] = []

    override func runTask(task: CETask) async {
        ranTasks.append(task)
    }
}

@MainActor
@Suite(.uiGate)
struct RunConfigurationsViewTests {
    private static let hostSize = NSSize(width: 420, height: 320)
    private let leases = PooledDefaultsLeases()

    private func writeManifests(in directory: URL) throws {
        let scripts = try JSONSerialization.data(withJSONObject: ["scripts": ["dev": "vite", "build": "vite build"]])
        try scripts.write(to: directory.appending(path: "package.json"))
        try Data("module demo\n".utf8).write(to: directory.appending(path: "go.mod"))
    }

    private func makeManager(
        in directory: URL,
        settings: CEWorkspaceSettingsData? = nil
    ) throws -> ConfigurationsRecordingTaskManager {
        let data = try settings ?? JSONDecoder().decode(CEWorkspaceSettingsData.self, from: Data("{}".utf8))
        let defaults = try leases.make()
        return ConfigurationsRecordingTaskManager(
            workspaceSettings: data,
            workspaceURL: directory,
            discovery: nil,
            selectionDefaults: defaults
        )
    }

    @Test
    func sectionsExposeTheirOriginAndTasks() async throws {
        try await withTempDir { directory in
            try writeManifests(in: directory)
            let manager = try makeManager(in: directory)
            manager.workspaceSettings.tasks = [CETask(name: "Mine", command: "true")]

            await manager.refreshDiscoveredTasks()

            let sections = manager.runConfigurationSections
            #expect(sections.map(\.title) == ["Workspace", "npm", "Go"])
            #expect(sections.map(\.isDiscovered) == [false, true, true])
            #expect(sections.map(\.id).count == Set(sections.map(\.id)).count)
            #expect(sections[0].subtitle == nil)
            #expect(sections[0].kind == nil)
            #expect(sections[1].subtitle == "package.json")
            #expect(sections[1].tasks.map(\.name) == ["npm run build", "npm run dev"])
            #expect(sections[2].subtitle == "go.mod")
            #expect(sections[2].tasks.map(\.command) == ["go run .", "go test ./..."])
            #expect(sections[2].tasks.allSatisfy { $0.source == sections[2].id })
        }
    }

    @Test
    func replacingTheTasksKeepsTheSectionMetadata() async throws {
        try await withTempDir { directory in
            try writeManifests(in: directory)
            let manager = try makeManager(in: directory)
            await manager.refreshDiscoveredTasks()
            let section = try #require(manager.runConfigurationSections.last)
            let only = try #require(section.tasks.first)

            let reduced = section.replacingTasks([only])

            #expect(reduced.id == section.id)
            #expect(reduced.title == section.title)
            #expect(reduced.subtitle == section.subtitle)
            #expect(reduced.kind == section.kind)
            #expect(reduced.tasks.map(\.id) == [only.id])
        }
    }

    @Test
    func commandKeysTreatTheRootDirectoryUniformly() {
        let root = CETask(name: "a", workingDirectory: "", command: "make")
        let dot = CETask(name: "b", workingDirectory: ".", command: "make")
        let nested = CETask(name: "c", workingDirectory: "web", command: "make")

        #expect(RunConfigurationSection.commandKey(for: root) == RunConfigurationSection.commandKey(for: dot))
        #expect(RunConfigurationSection.commandKey(for: root) != RunConfigurationSection.commandKey(for: nested))
    }

    @Test
    func actionsSelectAndRunTasksAndShowTheirOutput() async throws {
        try await withTempDir { directory in
            let manager = try makeManager(in: directory)
            let task = CETask(name: "Build", command: "make")
            manager.workspaceSettings.tasks = [task, CETask(name: "Other", command: "true")]
            let actions = RunConfigurationActions(taskManager: manager, workspaceSettings: nil)

            actions.select(task)
            #expect(manager.selectedTaskID == task.id)

            manager.selectedTaskID = nil
            await actions.run(task).value

            #expect(manager.selectedTaskID == task.id)
            #expect(manager.taskShowingOutput == task.id)
            #expect(manager.ranTasks.map(\.id) == [task.id])
        }
    }

    @Test
    func savingADiscoveredTaskPersistsItInTheWorkspaceSettings() async throws {
        try await withTempDir { directory in
            try writeManifests(in: directory)
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let manager = try makeManager(in: directory, settings: settings.settings)
            await manager.refreshDiscoveredTasks()
            let discovered = try #require(manager.availableTasks.first { $0.command == "go test ./..." })
            let actions = RunConfigurationActions(taskManager: manager, workspaceSettings: settings)

            actions.save(discovered)

            #expect(settings.settings.tasks.map(\.command) == ["go test ./..."])
            let written = try JSONDecoder().decode(
                CEWorkspaceSettingsData.self,
                from: Data(contentsOf: settings.settingsURL)
            )
            #expect(written.tasks.map(\.command) == ["go test ./..."])

            actions.save(try #require(settings.settings.tasks.first))
            #expect(settings.settings.tasks.count == 1)
        }
    }

    @Test
    func savingWithoutASettingsManagerStillCopiesTheTask() async throws {
        try await withTempDir { directory in
            try writeManifests(in: directory)
            let manager = try makeManager(in: directory)
            await manager.refreshDiscoveredTasks()
            let discovered = try #require(manager.availableTasks.first)

            RunConfigurationActions(taskManager: manager, workspaceSettings: nil).save(discovered)

            #expect(manager.workspaceSettings.tasks.count == 1)
        }
    }

    @Test
    func theListRendersEverySectionStateInTheWorkspace() async throws {
        try await withTempDir { empty in
            try await withTempDir { populated in
                try writeManifests(in: populated)
                let emptyWorkspace = try HostedViewFixture.makeWorkspace(in: empty)
                defer { emptyWorkspace.close() }
                let populatedWorkspace = try HostedViewFixture.makeWorkspace(in: populated)
                defer { populatedWorkspace.close() }
                let populatedManager = try #require(populatedWorkspace.taskManager)
                let emptyManager = try #require(emptyWorkspace.taskManager)
                try await eventually { !populatedManager.discoveredSections.isEmpty }
                populatedManager.workspaceSettings.tasks = [CETask(name: "Mine", command: "true")]

                let emptyHost = try HostedViewFixture.hostInWorkspace(emptyWorkspace, size: Self.hostSize) {
                    RunConfigurationsListView(taskManager: emptyManager)
                }
                defer { emptyHost.close() }
                let populatedHost = try HostedViewFixture.hostInWorkspace(populatedWorkspace, size: Self.hostSize) {
                    RunConfigurationsListView(taskManager: populatedManager)
                }
                defer { populatedHost.close() }
                try await emptyHost.settle(.milliseconds(100))
                try await populatedHost.settle(.milliseconds(100))
                let withoutTasks = emptyHost.snapshot()
                let unselected = populatedHost.snapshot()

                #expect(populatedHost.renders())
                #expect(HostedView.pixelsDiffer(withoutTasks, unselected))

                let discovered = try #require(populatedManager.availableTasks.first { $0.command == "npm run dev" })
                populatedManager.selectedTaskID = discovered.id
                try await populatedHost.settle(.milliseconds(100))
                let selected = populatedHost.snapshot()
                #expect(HostedView.pixelsDiffer(unselected, selected))

                let activeTask = CEActiveTask(task: discovered)
                activeTask.updateTaskStatus(to: .running)
                populatedManager.activeTasks[discovered.id] = activeTask
                try await populatedHost.settle(.milliseconds(100))
                #expect(HostedView.pixelsDiffer(selected, populatedHost.snapshot()))
            }
        }
    }

    @Test
    func theRunToolWindowShowsDiscoveredGroupsNextToUserTasks() async throws {
        try await withTempDir { empty in
            try await withTempDir { populated in
                try writeManifests(in: populated)
                let emptyWorkspace = try HostedViewFixture.makeWorkspace(in: empty)
                defer { emptyWorkspace.close() }
                let populatedWorkspace = try HostedViewFixture.makeWorkspace(in: populated)
                defer { populatedWorkspace.close() }
                let populatedManager = try #require(populatedWorkspace.taskManager)

                let emptyHost = try HostedViewFixture.hostInWorkspace(emptyWorkspace, size: Self.hostSize) {
                    RunToolWindow()
                }
                defer { emptyHost.close() }
                let populatedHost = try HostedViewFixture.hostInWorkspace(populatedWorkspace, size: Self.hostSize) {
                    RunToolWindow()
                }
                defer { populatedHost.close() }
                try await eventually { !populatedManager.discoveredSections.isEmpty }
                try await emptyHost.settle(.milliseconds(100))
                try await populatedHost.settle(.milliseconds(100))

                #expect(populatedManager.runConfigurationSections.map(\.title) == ["npm", "Go"])
                #expect(emptyHost.renders())
                #expect(populatedHost.renders())
                #expect(HostedView.pixelsDiffer(emptyHost.snapshot(), populatedHost.snapshot()))
            }
        }
    }

    @Test
    func consoleLinksOfActiveTasksOpenTheFileInTheWorkspaceEditor() async throws {
        try await withTempDir { directory in
            let source = directory.appending(path: "main.swift")
            try Data("print(1)\nprint(2)\n".utf8).write(to: source)
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let manager = try #require(workspace.taskManager)
            let activeTask = CEActiveTask(task: CETask(name: "Run", command: "true"))
            manager.activeTasks[activeTask.task.id] = activeTask

            let hosted = try HostedViewFixture.hostInWorkspace(workspace, size: Self.hostSize) { RunToolWindow() }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            let opener = try #require(activeTask.openFileLink)
            opener(ConsoleFileLinkTarget(url: source, line: 2, column: 3))

            let editor = try #require(workspace.editorManager?.activeEditor)
            #expect(editor.tabs.contains { $0.file.url.standardizedFileURL == source.standardizedFileURL })
        }
    }

    @Test
    func withoutAWorkspaceNoLinkOpenerIsInstalled() async throws {
        try await withTempDir { directory in
            let manager = try makeManager(in: directory)
            let activeTask = CEActiveTask(task: CETask(name: "Run", command: "true"))
            manager.activeTasks[activeTask.task.id] = activeTask

            let hosted = HostedViewFixture.host(size: Self.hostSize) {
                RunToolWindow()
                    .environment(manager as TaskManager)
                    .environment(ToolWindowManager())
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(100))

            #expect(activeTask.openFileLink == nil)
        }
    }

    @Test
    func rowActionsSelectRunAndSaveTheirTask() async throws {
        try await withTempDir { directory in
            try writeManifests(in: directory)
            let manager = try makeManager(in: directory)
            await manager.refreshDiscoveredTasks()
            let discovered = try #require(manager.availableTasks.first { $0.command == "go test ./..." })
            let row = RunConfigurationRow(
                task: discovered,
                isSelected: false,
                isDiscovered: true,
                status: .notRunning,
                actions: RunConfigurationActions(taskManager: manager, workspaceSettings: nil)
            )

            row.select()
            #expect(manager.selectedTaskID == discovered.id)

            manager.selectedTaskID = nil
            row.run()
            try await eventually(timeout: .seconds(30)) {
                manager.ranTasks.map(\.id) == [discovered.id] && manager.taskShowingOutput == discovered.id
            }
            #expect(manager.selectedTaskID == discovered.id)

            row.save()
            #expect(manager.workspaceSettings.tasks.map(\.command) == ["go test ./..."])
        }
    }

    @Test
    func hoverStateFollowsTheHoverEvents() {
        let state = RunConfigurationHoverState()
        #expect(!state.isHovering)

        state.setHovering(true)
        #expect(state.isHovering)

        state.setHovering(false)
        #expect(!state.isHovering)
    }

    @Test
    func rowsDrawTheHoverBackgroundAndShowUntitledTasksUnderTheirPlaceholderName() async throws {
        try await withTempDir { directory in
            let manager = try makeManager(in: directory)
            let actions = RunConfigurationActions(taskManager: manager, workspaceSettings: nil)
            let size = NSSize(width: 320, height: 40)

            @MainActor
            func snapshot(name: String, hovering: Bool, selected: Bool = false) async throws -> NSBitmapImageRep? {
                let hosted = HostedViewFixture.host(size: size) {
                    RunConfigurationRow(
                        task: CETask(name: name, command: "true"),
                        isSelected: selected,
                        isDiscovered: false,
                        status: .notRunning,
                        actions: actions,
                        hoverState: RunConfigurationHoverState(isHovering: hovering)
                    )
                }
                defer { hosted.close() }
                try await hosted.settle(.milliseconds(100))
                #expect(hosted.renders())
                return hosted.snapshot()
            }

            let idle = try await snapshot(name: "Build", hovering: false)
            let hovered = try await snapshot(name: "Build", hovering: true)
            let selected = try await snapshot(name: "Build", hovering: true, selected: true)
            let untitled = try await snapshot(name: "", hovering: false)
            let placeholder = try await snapshot(name: "Untitled Task", hovering: false)

            #expect(HostedView.pixelsDiffer(idle, hovered))
            #expect(HostedView.pixelsDiffer(hovered, selected))
            #expect(HostedView.pixelsDiffer(idle, untitled))
            #expect(!HostedView.pixelsDiffer(untitled, placeholder))
        }
    }
}
