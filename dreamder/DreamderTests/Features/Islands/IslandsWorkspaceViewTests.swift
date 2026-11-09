import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import Dreamder

@MainActor
private final class IslandsWorkspaceRig {
    let workspace: WorkspaceDocument
    let hosted: HostedView
    let defaults: UserDefaults
    let windowRef: NSWindow
    private let suiteName: String

    init(
        directory: URL,
        size: NSSize = NSSize(width: 1200, height: 800),
        prepare: (WorkspaceDocument, UserDefaults) throws -> Void = { _, _ in }
    ) throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        let workspace = try HostedViewFixture.makeWorkspace(in: directory)
        try prepare(workspace, defaults)
        let windowRef = NSWindow()
        self.defaults = defaults
        self.suiteName = suiteName
        self.workspace = workspace
        self.windowRef = windowRef
        hosted = try HostedViewFixture.hostInWorkspace(workspace, size: size) {
            WindowObserver(window: WindowBox(value: windowRef)) {
                IslandsWorkspaceView()
            }
            .defaultAppStorage(defaults)
        }
    }

    var manager: ToolWindowManager {
        workspace.toolWindowManager
    }

    func savedString(_ key: WorkspaceStateKey) -> String? {
        workspace.getFromWorkspaceState(key) as? String
    }

    func close() {
        hosted.close()
        workspace.close()
        removeIsolatedDefaults(defaults, suiteName: suiteName)
    }
}

@MainActor
@Suite(.uiGate)
struct IslandsWorkspaceViewTests {
    private func lightLayout(_ workspace: WorkspaceDocument) {
        let manager = workspace.toolWindowManager
        manager.hideAll()
        manager.show(.project)
        manager.show(.problems)
    }

    private func writePNG(to url: URL) throws {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemPink.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let representation = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(representation.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    @Test
    func rendersIslandsAndPersistsPlacementChanges() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in lightLayout(workspace) }
            defer { rig.close() }
            try await rig.hosted.settle()

            #expect(rig.hosted.renders())

            rig.manager.show(.find)

            try await eventually { rig.savedString(.toolWindowBottom) == "find" }
            #expect(rig.savedString(.toolWindowLeft) == "project")
        }
    }

    @Test
    func maximizingTheBottomWindowReplacesTheEditorRow() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in
                workspace.toolWindowManager.hideAll()
                workspace.toolWindowManager.show(.project)
            }
            defer { rig.close() }
            try await rig.hosted.settle()
            let editorRow = rig.hosted.snapshot()

            rig.manager.bottomMaximized = true
            try await eventually { rig.workspace.getFromWorkspaceState(.toolWindowBottomMaximized) as? Bool == true }

            rig.manager.show(.problems)
            try await eventually { rig.savedString(.toolWindowBottom) == "problems" }
            try await rig.hosted.settle()

            #expect(HostedView.pixelsDiffer(editorRow, rig.hosted.snapshot()))

            rig.manager.bottomMaximized = false
            try await eventually { rig.workspace.getFromWorkspaceState(.toolWindowBottomMaximized) as? Bool == false }
        }
    }

    @Test
    func mainAndSplitWindowsShareAnAnchorWithAMovableDivider() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in
                let manager = workspace.toolWindowManager
                manager.hideAll()
                manager.setSplit(.structure, true)
                manager.setSplit(.find, true)
                manager.show(.project)
                manager.show(.structure)
                manager.show(.problems)
                manager.show(.find)
            }
            defer { rig.close() }
            try await rig.hosted.settle()

            #expect(rig.hosted.renders())
            #expect(rig.manager.mainProportion(on: .left) == ToolWindowSplitState.defaultSideWeight)
            #expect(rig.manager.mainProportion(on: .bottom) == ToolWindowSplitState.defaultSideWeight)

            rig.manager.setMainProportion(on: .left, 0.7)
            rig.manager.setMainProportion(on: .bottom, 0.4)

            try await eventually { rig.workspace.getFromWorkspaceState(.toolWindowSideWeights) != nil }
            try await rig.hosted.settle()
            #expect(rig.hosted.renders())
            #expect(rig.savedString(.toolWindowLeftSplit) == "structure")
            #expect(rig.savedString(.toolWindowBottomSplit) == "find")
        }
    }

    @Test
    func anAnchorWithOnlyASplitWindowShowsItAlone() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in
                let manager = workspace.toolWindowManager
                manager.hideAll()
                manager.setSplit(.structure, true)
                manager.setSplit(.find, true)
                manager.show(.structure)
                manager.show(.find)
            }
            defer { rig.close() }
            try await rig.hosted.settle()

            #expect(rig.hosted.renders())
            #expect(rig.manager.active(.left) == .structure)
            #expect(rig.manager.active(.bottom) == .find)
        }
    }

    @Test
    func anEmptyWorkspaceRendersOnlyTheEditorIsland() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in
                workspace.toolWindowManager.hideAll()
            }
            defer { rig.close() }
            try await rig.hosted.settle()

            #expect(rig.hosted.renders())
        }
    }

    @Test
    func collapsingAndExpandingTheUtilityAreaHidesAndRestoresTheTerminal() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory)
            defer { rig.close() }
            let utilityArea = try #require(rig.workspace.utilityAreaModel)
            try await rig.hosted.settle()
            #expect(rig.manager.isVisible(.terminal))

            utilityArea.isCollapsed = true
            try await eventually { !rig.manager.isVisible(.terminal) }

            utilityArea.isCollapsed = false
            try await eventually { rig.manager.isVisible(.terminal) }
        }
    }

    @Test
    func collapsingWithoutAVisibleTerminalLeavesTheLayoutAlone() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in lightLayout(workspace) }
            defer { rig.close() }
            let utilityArea = try #require(rig.workspace.utilityAreaModel)
            try await rig.hosted.settle()

            utilityArea.isCollapsed = true
            try await rig.hosted.settle(.milliseconds(100))

            #expect(rig.manager.isVisible(.problems))
            #expect(!rig.manager.isVisible(.terminal))
        }
    }

    @Test
    func showingTaskOutputOpensTheRunToolWindow() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in lightLayout(workspace) }
            defer { rig.close() }
            let taskManager = try #require(rig.workspace.taskManager)
            try await rig.hosted.settle()
            #expect(!rig.manager.isVisible(.run))

            taskManager.taskShowingOutput = UUID()

            try await eventually { rig.manager.isVisible(.run) }
        }
    }

    @Test
    func expandingTheUtilityAreaWhileATaskShowsOutputRestoresTheRunWindow() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in lightLayout(workspace) }
            defer { rig.close() }
            let utilityArea = try #require(rig.workspace.utilityAreaModel)
            let taskManager = try #require(rig.workspace.taskManager)
            try await rig.hosted.settle()

            utilityArea.isCollapsed = true
            try await rig.hosted.settle(.milliseconds(100))
            let activeTask = CEActiveTask(task: CETask(name: "output", command: "true"))
            taskManager.activeTasks[activeTask.task.id] = activeTask
            taskManager.taskShowingOutput = activeTask.task.id
            try await eventually { rig.manager.isVisible(.run) }
            rig.manager.hide(.run)

            utilityArea.isCollapsed = false
            try await eventually { rig.manager.isVisible(.run) }
            #expect(!rig.manager.isVisible(.terminal))
        }
    }

    @Test
    func focusingTheActiveEditorRendersItsOwnLayout() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in
                lightLayout(workspace)
                workspace.editorManager?.isFocusingActiveEditor = true
            }
            defer { rig.close() }
            try await rig.hosted.settle()

            #expect(rig.hosted.renders())
        }
    }

    @Test
    func theBackgroundImageFollowsTheStoredPath() async throws {
        try await withTempDir { directory in
            let imageURL = directory.appending(path: "background.png")
            try writePNG(to: imageURL)
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in lightLayout(workspace) }
            defer { rig.close() }
            try await rig.hosted.settle()
            let plain = rig.hosted.snapshot()

            rig.defaults.set(0.6, forKey: Islands.BackgroundImageKey.opacity)
            rig.defaults.set(imageURL.path, forKey: Islands.BackgroundImageKey.path)
            try await eventually { HostedView.pixelsDiffer(plain, rig.hosted.snapshot()) }
            let withImage = rig.hosted.snapshot()

            rig.defaults.set("", forKey: Islands.BackgroundImageKey.path)
            try await eventually { HostedView.pixelsDiffer(withImage, rig.hosted.snapshot()) }
        }
    }

    @Test
    func changingTheDensityRebuildsTheWorkspace() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in lightLayout(workspace) }
            defer { rig.close() }
            try await rig.hosted.settle()

            rig.defaults.set(Islands.Density.default.rawValue, forKey: Islands.densityKey)
            try await rig.hosted.settle()

            #expect(rig.hosted.renders())
        }
    }

    @Test
    func closingTheWindowRecordsItsFrameInTheWorkspaceState() async throws {
        try await withTempDir { directory in
            let rig = try IslandsWorkspaceRig(directory: directory) { workspace, _ in lightLayout(workspace) }
            defer { rig.close() }
            try await rig.hosted.settle()
            #expect(rig.savedString(.workspaceWindowSize) == nil)

            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: rig.windowRef)

            try await eventually { rig.savedString(.workspaceWindowSize) == NSStringFromRect(rig.windowRef.frame) }
        }
    }
}
