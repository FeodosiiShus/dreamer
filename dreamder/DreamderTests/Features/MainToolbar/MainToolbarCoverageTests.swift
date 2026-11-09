import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class MainToolbarPopUpRecorder {
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
final class MainToolbarRecordingTaskManager: TaskManager {
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
    func makeTaskManager(tasks: [CETask] = []) -> MainToolbarRecordingTaskManager {
        let manager = MainToolbarRecordingTaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
        manager.workspaceSettings.tasks = tasks
        return manager
    }

    func perform(_ item: NSMenuItem) throws -> Bool {
        let action = try #require(item.action)
        return NSApplication.shared.sendAction(action, to: item.target, from: item)
    }

    func hostAnchor(
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
}
