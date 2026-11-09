import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class MainToolbarPopUpRecorder {
    var menus: [NSMenu] = []
    var points: [NSPoint] = []
    var views: [NSView] = []

    func install(on anchor: MainToolbarMenuAnchor) {
        anchor.popUp = { [self] menu, point, view in
            menus.append(menu)
            points.append(point)
            views.append(view)
        }
    }
}

@MainActor
private final class MainToolbarRecordingTaskManager: TaskManager {
    private(set) var executeCalls = 0
    private(set) var terminateCalls = 0
    private(set) var rerunCalls = 0
    private(set) var stopAllCalls = 0

    override func executeActiveTask() {
        executeCalls += 1
    }

    override func terminateActiveTask() {
        terminateCalls += 1
    }

    override func rerunLastTask() -> Task<Void, Never>? {
        rerunCalls += 1
        return nil
    }

    override func stopAllTasks() {
        stopAllCalls += 1
    }
}

@MainActor
private final class MainToolbarCloseProbe: NSObject, NSWindowDelegate {
    var closeRequests = 0

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequests += 1
        return false
    }
}

@MainActor
@Suite(.uiGate)
struct MainToolbarCoverageTests {
    private func makeTaskManager(tasks: [CETask] = []) -> MainToolbarRecordingTaskManager {
        let manager = MainToolbarRecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        manager.workspaceSettings.tasks = tasks
        return manager
    }

    private func perform(_ item: NSMenuItem) throws -> Bool {
        let action = try #require(item.action)
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    private func hostAnchor(
        _ anchor: MainToolbarMenuAnchor,
        size: NSSize = NSSize(width: 100, height: 40)
    ) async throws -> HostedView {
        let hosted = HostedViewFixture.host(size: size) {
            MainToolbarMenuAnchorView(anchor: anchor).frame(width: size.width, height: size.height)
        }
        try await hosted.settle()
        return hosted
    }

    @Test
    func anchorPresentsMenusBelowItsViewOnlyWhenItHasOne() async throws {
        let anchor = MainToolbarMenuAnchor()
        let recorder = MainToolbarPopUpRecorder()
        recorder.install(on: anchor)
        anchor.present(NSMenu(title: "detached"))
        #expect(recorder.menus.isEmpty)

        let hosted = try await hostAnchor(anchor)
        defer { hosted.close() }
        let view = try #require(anchor.view)
        let menu = NSMenu(title: "attached")
        anchor.present(menu)

        #expect(recorder.menus == [menu])
        #expect(recorder.views == [view])
        #expect(recorder.points == [NSPoint(x: 0, y: view.bounds.height + Islands.islandGap)])
        #expect(view.isFlipped)
        #expect(view.hitTest(NSPoint(x: 1, y: 1)) == nil)
    }

    @Test
    func projectMenuListsOpenRecentAndCloseProject() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let menu = MainToolbarMenuActions.shared.projectMenu(window: window)

        #expect(menu.title == "Project")
        #expect(menu.items.map(\.title) == ["Open…", "Open Recent", "", "Close Project"])
        #expect(menu.items[1].submenu != nil)
        #expect(menu.items[2].isSeparatorItem)
        #expect(menu.items[3].representedObject as? NSWindow === window)
        #expect(MainToolbarMenuActions.shared.projectMenu(window: nil).items[3].representedObject == nil)
    }

    @Test
    func openMenuItemRoutesToTheDocumentController() throws {
        let menu = MainToolbarMenuActions.shared.projectMenu(window: nil)

        #expect(try perform(menu.items[0]))
    }

    @Test
    func closeProjectAsksTheWindowToClose() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let probe = MainToolbarCloseProbe()
        window.delegate = probe
        window.orderFront(nil)
        defer {
            window.delegate = nil
            window.close()
        }
        let menu = MainToolbarMenuActions.shared.projectMenu(window: window)

        #expect(try perform(menu.items[3]))
        #expect(probe.closeRequests == 1)
    }

    @Test
    func closeProjectWithoutAWindowDoesNothing() throws {
        let menu = MainToolbarMenuActions.shared.projectMenu(window: nil)

        #expect(try perform(menu.items[3]))
        let action = try #require(menu.items[3].action)
        #expect(NSApplication.shared.sendAction(action, to: menu.items[3].target, from: nil))
    }

    @Test
    func settingsMenuListsSettingsAndTheCommandPalette() throws {
        let menu = MainToolbarMenuActions.shared.settingsMenu()

        #expect(menu.title == "Settings")
        #expect(menu.items.map(\.title) == ["Settings…", "", "Command Palette"])
        #expect(menu.items[0].keyEquivalent == ",")
        #expect(menu.items[1].isSeparatorItem)
        #expect(try perform(menu.items[0]))
        #expect(try perform(menu.items[2]))
    }

    @Test
    func taskMenuListsTasksMarksTheSelectionAndSelectsOnPerform() throws {
        let named = CETask(name: "Build", command: "make")
        let unnamed = CETask(name: "", command: "make test")
        let manager = makeTaskManager(tasks: [named, unnamed])
        manager.selectedTaskID = named.id

        let menu = MainToolbarMenuActions.shared.taskMenu(taskManager: manager)

        #expect(menu.title == "Run Configuration")
        #expect(
            menu.items.map(\.title) == [
                "Build", "Untitled Task", "", "Rerun Last Task", "Stop All", "", "Edit Configurations…"
            ]
        )
        #expect(menu.items[0].state == .on)
        #expect(menu.items[1].state == .off)
        #expect(menu.items.allSatisfy { !$0.isSectionHeader })
        #expect(try perform(menu.items[1]))
        #expect(manager.selectedTaskID == unnamed.id)
        #expect(try perform(menu.items[6]))
    }

    @Test
    func taskMenuGroupsDiscoveredTasksUnderTheirSources() throws {
        let mine = CETask(name: "Build", command: "make")
        let manager = makeTaskManager(tasks: [mine])
        manager.applyDiscoveredGroups([
            DiscoveredTaskGroup(
                kind: .npm,
                directory: "",
                manifest: "package.json",
                tasks: [
                    DiscoveredTask(
                        kind: .npm,
                        name: "npm run dev",
                        command: "npm run dev",
                        workingDirectory: "",
                        manifest: "package.json"
                    )
                ]
            )
        ])

        let menu = MainToolbarMenuActions.shared.taskMenu(taskManager: manager)

        #expect(
            menu.items.map(\.title) == [
                "Workspace", "Build", "npm", "npm run dev", "", "Rerun Last Task", "Stop All", "", "Edit Configurations…"
            ]
        )
        #expect(menu.items.map(\.isSectionHeader) == [true, false, true, false, false, false, false, false, false])
        let discovered = menu.items[3]
        #expect(try perform(discovered))
        #expect(manager.selectedTask?.command == "npm run dev")
    }

    @Test
    func rerunAndStopAllAreEnabledOnlyWhenTheyCanAct() throws {
        let task = CETask(name: "Build", command: "make")
        let manager = makeTaskManager(tasks: [task])

        let idle = MainToolbarMenuActions.shared.taskMenu(taskManager: manager)
        #expect(!idle.items[2].isEnabled)
        #expect(!idle.items[3].isEnabled)

        manager.lastRunTask = task
        let activeTask = CEActiveTask(task: task)
        activeTask.updateTaskStatus(to: .running)
        manager.activeTasks[task.id] = activeTask
        let busy = MainToolbarMenuActions.shared.taskMenu(taskManager: manager)
        #expect(busy.items[2].isEnabled)
        #expect(busy.items[3].isEnabled)
    }

    @Test
    func rerunAndStopAllItemsActOnTheTaskManager() throws {
        let task = CETask(name: "Build", command: "make")
        let manager = makeTaskManager(tasks: [task])
        manager.lastRunTask = task
        let menu = MainToolbarMenuActions.shared.taskMenu(taskManager: manager)

        #expect(try perform(menu.items[2]))
        #expect(manager.rerunCalls == 1)
        #expect(manager.taskShowingOutput == task.id)

        #expect(try perform(menu.items[3]))
        #expect(manager.stopAllCalls == 1)
    }

    @Test
    func rerunAndStopAllItemsWithoutATaskManagerDoNothing() throws {
        let manager = makeTaskManager(tasks: [CETask(name: "Build", command: "make")])
        let menu = MainToolbarMenuActions.shared.taskMenu(taskManager: manager)

        for item in [menu.items[2], menu.items[3]] {
            let action = try #require(item.action)
            #expect(NSApplication.shared.sendAction(action, to: item.target, from: nil))
        }

        #expect(manager.rerunCalls == 0)
        #expect(manager.stopAllCalls == 0)
    }

    @Test
    func taskMenuWithoutTasksOnlyOffersTheConfigurationEditor() throws {
        let menu = MainToolbarMenuActions.shared.taskMenu(taskManager: makeTaskManager())

        #expect(menu.items.map(\.title) == ["Edit Configurations…"])
    }

    @Test
    func selectingAMenuItemWithoutATaskLeavesTheSelectionAlone() throws {
        let task = CETask(name: "Build", command: "make")
        let manager = makeTaskManager(tasks: [task])
        manager.selectedTaskID = task.id
        let item = try #require(MainToolbarMenuActions.shared.taskMenu(taskManager: manager).items.first)
        let action = try #require(item.action)

        #expect(NSApplication.shared.sendAction(action, to: item.target, from: nil))
        #expect(manager.selectedTaskID == task.id)
    }

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

            #expect(managers.map { RunToolbarWidget.taskName(of: $0) } == ["No Tasks", "Build", "Build", "Untitled Task"])
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
    func iconControlsRenderEnabledAndDisabledWithAndWithoutHover() async throws {
        let plain = HostedViewFixture.host(size: NSSize(width: 60, height: 50)) {
            MainToolbarIconContent(icon: "general/settings")
        }
        let hovering = HostedViewFixture.host(size: NSSize(width: 60, height: 50)) {
            MainToolbarIconContent(icon: "general/settings", isHovering: true)
        }
        let button = HostedViewFixture.host(size: NSSize(width: 60, height: 50)) {
            MainToolbarIconButton(icon: "run/run", help: "Run", action: {})
        }
        let disabled = HostedViewFixture.host(size: NSSize(width: 60, height: 50)) {
            MainToolbarIconButton(icon: "run/run", help: "Run", isEnabled: false, action: {})
        }
        let glass = HostedViewFixture.host(size: NSSize(width: 60, height: 50)) {
            Color.red.frame(width: 30, height: 20).modifier(MainToolbarGlass())
        }
        defer {
            plain.close()
            hovering.close()
            button.close()
            disabled.close()
            glass.close()
        }
        for hosted in [plain, hovering, button, disabled, glass] {
            try await hosted.settle()
            #expect(hosted.renders())
        }

        #expect(HostedView.pixelsDiffer(button.snapshot(), disabled.snapshot()))
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

@MainActor
private final class SearchEverywhereSendRecorder {
    var selectors: [Selector] = []
}

@MainActor
@Suite(.uiGate)
struct MainToolbarInteractionCoverageTests {
    private func makeTaskManager(tasks: [CETask] = []) -> MainToolbarRecordingTaskManager {
        let manager = MainToolbarRecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        manager.workspaceSettings.tasks = tasks
        return manager
    }

    private func recordedAnchor() -> (MainToolbarMenuAnchor, MainToolbarPopUpRecorder) {
        let anchor = MainToolbarMenuAnchor()
        let recorder = MainToolbarPopUpRecorder()
        recorder.install(on: anchor)
        return (anchor, recorder)
    }

    private func hostAnchor(_ anchor: MainToolbarMenuAnchor) async throws -> HostedView {
        let hosted = HostedViewFixture.host(size: NSSize(width: 100, height: 40)) {
            MainToolbarMenuAnchorView(anchor: anchor).frame(width: 100, height: 40)
        }
        try await hosted.settle()
        return hosted
    }

    private func renderHovered<Content: View>(
        _ content: (MainToolbarHoverState) -> Content
    ) async throws {
        let hover = MainToolbarHoverState()
        hover.setHovering(true)
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 80)) { content(hover) }
        defer { hosted.close() }
        try await hosted.settle()
        try await eventually(timeout: .seconds(60)) { hosted.renders() }
        #expect(hover.isHovering)
    }

    @Test
    func theProjectWidgetPresentsTheProjectMenuAndRendersHovered() async throws {
        try await withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let (anchor, recorder) = recordedAnchor()
            let anchorHost = try await hostAnchor(anchor)
            defer { anchorHost.close() }

            ProjectToolbarWidget(workspace: workspace, menuAnchor: anchor).showMenu()

            #expect(recorder.menus.map(\.title) == ["Project"])
            try await renderHovered { hover in ProjectToolbarWidget(workspace: workspace, hover: hover) }
        }
    }

    @Test
    func theProjectWidgetShowsTheDocumentNameWhenThereIsNoFolder() async throws {
        let named = WorkspaceDocument()
        named.displayName = "Alpha"
        let unnamed = WorkspaceDocument()
        var snapshots: [NSBitmapImageRep?] = []
        for workspace in [named, unnamed] {
            let hosted = HostedViewFixture.host(size: NSSize(width: 300, height: 50)) {
                ProjectToolbarWidget(workspace: workspace)
            }
            defer { hosted.close() }
            try await hosted.settle()
            try await eventually(timeout: .seconds(30)) { hosted.renders() }
            snapshots.append(hosted.snapshot())
        }

        #expect(HostedView.pixelsDiffer(snapshots[0], snapshots[1]))
    }

    @Test
    func theSettingsWidgetPresentsTheSettingsMenuAndRendersHovered() async throws {
        let (anchor, recorder) = recordedAnchor()
        let anchorHost = try await hostAnchor(anchor)
        defer { anchorHost.close() }

        SettingsToolbarWidget(menuAnchor: anchor).showMenu()

        #expect(recorder.menus.map(\.title) == ["Settings"])
        try await renderHovered { hover in SettingsToolbarWidget(hover: hover) }
    }

    @Test
    func theRunSelectorPresentsTheTaskMenuAndRendersHovered() async throws {
        let manager = makeTaskManager(tasks: [CETask(name: "Build", command: "make")])
        let (anchor, recorder) = recordedAnchor()
        let anchorHost = try await hostAnchor(anchor)
        defer { anchorHost.close() }

        RunTaskSelector(taskManager: manager, menuAnchor: anchor).showMenu()

        #expect(recorder.menus.map(\.title) == ["Run Configuration"])
        try await renderHovered { hover in
            RunTaskSelector(taskManager: manager, menuAnchor: MainToolbarMenuAnchor(), hover: hover)
        }
    }

    @Test
    func theIconButtonRendersHovered() async throws {
        try await renderHovered { hover in
            MainToolbarIconButton(icon: "run/run", help: "Run", action: {}, hover: hover)
        }
    }

    @Test
    func hoverStateFollowsTheHoverCallback() {
        let hover = MainToolbarHoverState()
        #expect(!hover.isHovering)

        hover.setHovering(true)
        #expect(hover.isHovering)

        hover.setHovering(false)
        #expect(!hover.isHovering)
    }

    @Test
    func theSearchEverywhereWidgetSendsTheOpenActionAndRendersHovered() async throws {
        let recorder = SearchEverywhereSendRecorder()
        let widget = SearchEverywhereToolbarWidget(send: { recorder.selectors.append($0) })

        widget.openSearchEverywhere()

        #expect(recorder.selectors == [#selector(DreamderWindowController.openSearchEverywhere(_:))])
        try await renderHovered { hover in SearchEverywhereToolbarWidget(hover: hover) }
    }

    @Test
    func taskNamesFollowTheSelectionAndFallBackWhenThereIsNone() {
        let named = CETask(name: "Build", command: "make")
        let unnamed = CETask(name: "", command: "make")

        let empty = makeTaskManager()
        #expect(RunToolbarWidget.taskName(of: empty) == "No Tasks")

        let firstByDefault = makeTaskManager(tasks: [named, unnamed])
        #expect(RunToolbarWidget.taskName(of: firstByDefault) == "Build")

        firstByDefault.selectedTaskID = unnamed.id
        #expect(RunToolbarWidget.taskName(of: firstByDefault) == "Untitled Task")

        firstByDefault.selectedTaskID = UUID()
        #expect(RunToolbarWidget.taskName(of: firstByDefault) == "No Tasks")
    }

    @Test
    func theRunButtonRunsTheSelectedTaskAndIsEnabledOnlyWithTasks() async throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let task = CETask(name: "Build", command: "make")
            let manager = makeTaskManager(tasks: [task])

            let button = RunToolbarWidget.runButton(taskManager: manager, workspace: workspace)
            button.action()

            #expect(button.isEnabled)
            #expect(button.help == "Run")
            #expect(manager.executeCalls == 1)
            #expect(manager.taskShowingOutput == task.id)
            #expect(!RunToolbarWidget.runButton(taskManager: makeTaskManager(), workspace: workspace).isEnabled)
        }
    }

    @Test
    func theStopButtonTerminatesTheActiveTaskAndIsEnabledOnlyWhileRunning() {
        let task = CETask(name: "Build", command: "make")
        let manager = makeTaskManager(tasks: [task])
        manager.selectedTaskID = task.id
        #expect(!RunToolbarWidget.isRunning(manager))
        #expect(!RunToolbarWidget.stopButton(taskManager: manager).isEnabled)
        #expect(!RunToolbarWidget.isRunning(makeTaskManager()))

        let active = CEActiveTask(task: task)
        active.updateTaskStatus(to: .running)
        manager.activeTasks[task.id] = active
        let button = RunToolbarWidget.stopButton(taskManager: manager)
        button.action()

        #expect(RunToolbarWidget.isRunning(manager))
        #expect(button.isEnabled)
        #expect(button.help == "Stop")
        #expect(manager.terminateCalls == 1)
    }
}
