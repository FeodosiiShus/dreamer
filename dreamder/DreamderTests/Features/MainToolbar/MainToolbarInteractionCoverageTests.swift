import AppKit
import SwiftUI
import Testing
@testable import Dreamder

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
    func theSearchEverywhereWidgetSendsTheOpenActionAndRendersAFlatField() async throws {
        let recorder = SearchEverywhereSendRecorder()
        let widget = SearchEverywhereToolbarWidget(send: { recorder.selectors.append($0) })

        widget.openSearchEverywhere()

        #expect(recorder.selectors == [#selector(DreamderWindowController.openSearchEverywhere(_:))])
        let hosted = HostedViewFixture.host(size: NSSize(width: 320, height: 50)) { widget }
        defer { hosted.close() }
        try await hosted.settle()
        #expect(hosted.renders())
    }

    private func idleAndHoveredSnapshots<Content: View>(
        size: NSSize,
        _ content: (MainToolbarHoverState) -> Content
    ) async throws -> (idle: NSBitmapImageRep?, hovered: NSBitmapImageRep?) {
        let idleState = MainToolbarHoverState()
        let hoverState = MainToolbarHoverState()
        hoverState.setHovering(true)
        let idle = HostedViewFixture.host(size: size) { content(idleState) }
        let hovered = HostedViewFixture.host(size: size) { content(hoverState) }
        defer {
            idle.close()
            hovered.close()
        }
        try await idle.settle()
        try await hovered.settle()
        return (idle.snapshot(), hovered.snapshot())
    }

    @Test
    func hoveringPaintsTheToolbarHoverBackground() async throws {
        let size = NSSize(width: 60, height: 50)
        let settings = try await idleAndHoveredSnapshots(size: size) { hover in
            SettingsToolbarWidget(hover: hover)
        }
        let run = try await idleAndHoveredSnapshots(size: size) { hover in
            MainToolbarIconButton(icon: "run/run", help: "Run", action: {}, hover: hover)
        }
        let task = try await idleAndHoveredSnapshots(size: NSSize(width: 200, height: 50)) { hover in
            RunTaskSelector(
                taskManager: makeTaskManager(tasks: [CETask(name: "Build", command: "make")]),
                menuAnchor: MainToolbarMenuAnchor(),
                hover: hover
            )
        }

        #expect(HostedView.pixelsDiffer(settings.idle, settings.hovered))
        #expect(HostedView.pixelsDiffer(run.idle, run.hovered))
        #expect(HostedView.pixelsDiffer(task.idle, task.hovered))
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
        let idleStop = RunToolbarWidget.stopButton(taskManager: manager)
        #expect(!idleStop.isEnabled)
        #expect(idleStop.accent == nil)
        #expect(idleStop.tint == MainToolbarMetrics.defaultIconColor)
        #expect(!RunToolbarWidget.isRunning(makeTaskManager()))

        let active = CEActiveTask(task: task)
        active.updateTaskStatus(to: .running)
        manager.activeTasks[task.id] = active
        let button = RunToolbarWidget.stopButton(taskManager: manager)
        button.action()

        #expect(RunToolbarWidget.isRunning(manager))
        #expect(button.isEnabled)
        #expect(button.help == "Stop")
        #expect(button.accent == .stop)
        #expect(button.tint == ActionButtonAccent.iconOverAccent)
        #expect(button.iconSize == MainToolbarMetrics.runIconSize)
        #expect(manager.terminateCalls == 1)
    }

    @Test
    func theRunButtonTurnsGreenOnlyWhileTheSelectedTaskRuns() async throws {
        try withTempDir { directory in
            let workspace = try HostedViewFixture.makeWorkspace(in: directory)
            defer { workspace.close() }
            let task = CETask(name: "Build", command: "make")
            let manager = makeTaskManager(tasks: [task])
            manager.selectedTaskID = task.id

            let idle = RunToolbarWidget.runButton(taskManager: manager, workspace: workspace)
            #expect(idle.accent == nil)
            #expect(idle.tint == MainToolbarMetrics.runIconColor)
            #expect(idle.iconSize == MainToolbarMetrics.runIconSize)

            let active = CEActiveTask(task: task)
            active.updateTaskStatus(to: .running)
            manager.activeTasks[task.id] = active
            let running = RunToolbarWidget.runButton(taskManager: manager, workspace: workspace)
            #expect(running.accent == .run)
            #expect(running.tint == ActionButtonAccent.iconOverAccent)
        }
    }
}
