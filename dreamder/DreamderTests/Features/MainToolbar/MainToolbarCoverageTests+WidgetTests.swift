import AppKit
import SwiftUI
import Testing
@testable import Dreamder

extension MainToolbarCoverageTests {
    @Test
    func widgetsPresentTheirMenusThroughTheAnchor() async throws {
        let anchor = MainToolbarMenuAnchor()
        let recorder = MainToolbarPopUpRecorder()
        recorder.install(on: anchor)
        let hosted = try await hostAnchor(anchor)
        defer { hosted.close() }

        ProjectToolbarWidget.presentMenu(on: anchor)
        SettingsToolbarWidget.presentMenu(on: anchor)
        RunToolbarWidget.presentMenu(on: anchor, taskManager: makeTaskManager())

        #expect(recorder.menus.map(\.title) == ["Project", "Settings", "Run Configuration"])
        #expect(recorder.menus[0].items[3].representedObject as? NSWindow === hosted.window)
    }

    @Test
    func runStartsTheSelectedTaskAndRevealsTheRunToolWindow() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let first = CETask(name: "First", command: "true")
            let second = CETask(name: "Second", command: "true")
            let manager = makeTaskManager(tasks: [first, second])

            RunToolbarWidget.run(taskManager: manager, workspace: workspace)

            #expect(manager.selectedTaskID == first.id)
            #expect(manager.taskShowingOutput == first.id)
            #expect(manager.executeCalls == 1)
            #expect(workspace.toolWindowManager.isVisible(.run))

            manager.selectedTaskID = second.id
            RunToolbarWidget.run(taskManager: manager, workspace: workspace)

            #expect(manager.selectedTaskID == second.id)
            #expect(manager.taskShowingOutput == second.id)
            #expect(manager.executeCalls == 2)
        }
    }

    @Test
    func runWithoutTasksSelectsNothing() async throws {
        try withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let manager = makeTaskManager()

            RunToolbarWidget.run(taskManager: manager, workspace: workspace)

            #expect(manager.selectedTaskID == nil)
            #expect(manager.taskShowingOutput == nil)
            #expect(manager.executeCalls == 1)
        }
    }

    @Test
    func runWidgetRendersEveryTaskState() async throws {
        try await withTempDir { dir in
            let workspace = try HostedViewFixture.makeWorkspace(in: dir)
            defer { workspace.close() }
            let named = CETask(name: "Build", command: "make")
            let unnamed = CETask(name: "", command: "make")

            let empty = makeTaskManager()
            let fallback = makeTaskManager(tasks: [named])
            let running = makeTaskManager(tasks: [named, unnamed])
            running.selectedTaskID = named.id
            let activeTask = CEActiveTask(task: named)
            activeTask.updateTaskStatus(to: .running)
            running.activeTasks[named.id] = activeTask
            let untitled = makeTaskManager(tasks: [unnamed])
            untitled.selectedTaskID = unnamed.id

            let managers = [empty, fallback, running, untitled]
            for manager in managers {
                let anchor = MainToolbarMenuAnchor()
                let selector = HostedViewFixture.host(size: NSSize(width: 400, height: 50)) {
                    RunTaskSelector(taskManager: manager, menuAnchor: anchor)
                }
                defer { selector.close() }
                try await selector.settle()
                try await eventually(timeout: .seconds(60)) { selector.renders() }

                let widget = try HostedViewFixture.hostInWorkspace(workspace, size: NSSize(width: 400, height: 50)) {
                    RunToolbarWidget(taskManager: manager)
                }
                defer { widget.close() }
                try await widget.settle()
            }

            let expectedNames = ["No Tasks", "Build", "Build", "Untitled Task"]
            #expect(managers.map { RunToolbarWidget.taskName(of: $0) } == expectedNames)
            #expect(managers.map { RunToolbarWidget.runButton(taskManager: $0, workspace: workspace).isEnabled } == [
                false, true, true, true
            ])
            #expect(managers.map { RunToolbarWidget.stopButton(taskManager: $0).isEnabled } == [
                false, false, true, false
            ])
        }
    }

    @Test
    func projectWidgetRendersBadgesForEveryNameShape() async throws {
        try await withTempDir { dir in
            var snapshots: [NSBitmapImageRep?] = []
            for name in ["app", "my-app", "---"] {
                let projectDir = dir.appending(path: name, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
                let workspace = try HostedViewFixture.makeWorkspace(in: projectDir)
                defer { workspace.close() }
                let hosted = HostedViewFixture.host(size: NSSize(width: 200, height: 50)) {
                    ProjectToolbarWidget(workspace: workspace)
                }
                defer { hosted.close() }
                try await hosted.settle()
                #expect(hosted.renders())
                snapshots.append(hosted.snapshot())
            }

            #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[1]))
            #expect(HostedView.pixelsDiffer(snapshots[1], snapshots[2]))
        }
    }

    @Test
    func searchEverywhereWidgetRendersAndForwardsItsAction() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 50)) {
            SearchEverywhereToolbarWidget()
        }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.renders())
        SearchEverywhereToolbarWidget().openSearchEverywhere()
    }

    @Test
    func settingsWidgetRenders() async throws {
        let hosted = HostedViewFixture.host(size: NSSize(width: 60, height: 50)) {
            SettingsToolbarWidget()
        }
        defer { hosted.close() }
        try await hosted.settle()

        #expect(hosted.renders())
    }

    @Test
    func iconControlsRenderEnabledDisabledTintedAndAccented() async throws {
        let size = NSSize(width: 60, height: 50)
        let plain = HostedViewFixture.host(size: size) {
            MainToolbarIconContent(icon: "general/settings_20")
        }
        let tinted = HostedViewFixture.host(size: size) {
            MainToolbarIconContent(
                icon: "run/run",
                size: MainToolbarMetrics.runIconSize,
                tint: MainToolbarMetrics.runIconColor
            )
        }
        let original = HostedViewFixture.host(size: size) {
            MainToolbarIconContent(icon: "run/run", size: MainToolbarMetrics.runIconSize)
        }
        let button = HostedViewFixture.host(size: size) {
            MainToolbarIconButton(icon: "run/run", help: "Run", action: {})
        }
        let disabled = HostedViewFixture.host(size: size) {
            MainToolbarIconButton(icon: "run/run", help: "Run", isEnabled: false, action: {})
        }
        let accented = HostedViewFixture.host(size: size) {
            MainToolbarIconButton(
                icon: "run/run",
                help: "Run",
                tint: ActionButtonAccent.iconOverAccent,
                accent: .run,
                action: {}
            )
        }
        defer {
            plain.close()
            tinted.close()
            original.close()
            button.close()
            disabled.close()
            accented.close()
        }
        for hosted in [plain, tinted, original, button, disabled, accented] {
            try await hosted.settle()
            #expect(hosted.renders())
        }

        #expect(HostedView.pixelsDiffer(button.snapshot(), disabled.snapshot()))
        #expect(HostedView.pixelsDiffer(tinted.snapshot(), original.snapshot()))
        #expect(HostedView.pixelsDiffer(button.snapshot(), accented.snapshot()))
    }

    @Test
    func toolbarIdentifiersAreStable() {
        #expect(NSToolbarItem.Identifier.projectWidget.rawValue == "ProjectWidget")
        #expect(NSToolbarItem.Identifier.vcsBranchWidget.rawValue == "VCSBranchWidget")
        #expect(NSToolbarItem.Identifier.searchEverywhereWidget.rawValue == "SearchEverywhereWidget")
        #expect(NSToolbarItem.Identifier.runWidget.rawValue == "RunWidget")
        #expect(NSToolbarItem.Identifier.settingsWidget.rawValue == "SettingsWidget")
    }
}
