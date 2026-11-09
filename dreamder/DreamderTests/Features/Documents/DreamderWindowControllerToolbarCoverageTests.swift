import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerToolbarCoverageTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        func close() {
            window.close()
            workspace.close()
        }
    }

    private static let widgets: [NSToolbarItem.Identifier] = [
        .projectWidget,
        .vcsBranchWidget,
        .searchEverywhereWidget,
        .flexibleSpace,
        .runWidget,
        .settingsWidget
    ]

    private func makeHarness(in directory: URL) throws -> Harness {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        return Harness(workspace: workspace, controller: controller, window: window)
    }

    private func makeIncompleteController() -> (controller: DreamderWindowController, window: NSWindow) {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        return (DreamderWindowController(window: window, workspace: WorkspaceDocument()), window)
    }

    private func item(
        _ identifier: NSToolbarItem.Identifier,
        of controller: DreamderWindowController
    ) -> NSToolbarItem? {
        controller.toolbar(
            NSToolbar(identifier: "DreamderWindowControllerToolbarCoverageTests"),
            itemForItemIdentifier: identifier,
            willBeInsertedIntoToolbar: false
        )
    }

    @Test
    func theToolbarOffersTheMainWidgetsInOrder() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let toolbar = NSToolbar(identifier: "DreamderWindowControllerToolbarCoverageTests")

            #expect(harness.controller.toolbarDefaultItemIdentifiers(toolbar) == Self.widgets)
            #expect(harness.controller.toolbarAllowedItemIdentifiers(toolbar) == Self.widgets)
        }
    }

    @Test
    func theMainToolbarIsConfiguredAsAnIconOnlyTransparentChrome() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let toolbar = try #require(harness.window.toolbar)

            #expect(toolbar.identifier == "DreamderMainToolbar")
            #expect(toolbar.displayMode == .iconOnly)
            #expect(!toolbar.allowsUserCustomization)
            #expect(!toolbar.autosavesConfiguration)
            #expect(toolbar.delegate === harness.controller)
            #expect(harness.window.titleVisibility == .hidden)
            #expect(harness.window.titlebarAppearsTransparent)
            #expect(harness.window.titlebarSeparatorStyle == .none)
            #expect(harness.window.toolbarStyle == .unifiedCompact)
        }
    }

    @Test
    func everyWidgetItemIsLabelledBorderlessAndHostsItsView() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let labels: [(NSToolbarItem.Identifier, String)] = [
                (.projectWidget, "Project"),
                (.vcsBranchWidget, "Git Branch"),
                (.searchEverywhereWidget, "Search Everywhere"),
                (.runWidget, "Run"),
                (.settingsWidget, "Settings")
            ]

            for (identifier, label) in labels {
                let toolbarItem = try #require(item(identifier, of: harness.controller))

                #expect(toolbarItem.itemIdentifier == identifier)
                #expect(toolbarItem.label == label)
                #expect(toolbarItem.paletteLabel == label)
                #expect(!toolbarItem.isBordered)
                #expect(toolbarItem.visibilityPriority == .high)
                #expect(toolbarItem.view?.contentHuggingPriority(for: .horizontal) == .required)
                #expect(toolbarItem.view?.contentHuggingPriority(for: .vertical) == .required)
                if #available(macOS 26.0, *) {
                    #expect(toolbarItem.style == .plain)
                }
            }
        }
    }

    @Test
    func identifiersTheDelegateDoesNotKnowProduceNoItem() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            #expect(item(.flexibleSpace, of: harness.controller) == nil)
            #expect(item(.activityViewer, of: harness.controller) == nil)
            #expect(item(.notificationItem, of: harness.controller) == nil)
        }
    }

    @Test
    func widgetsThatNeedWorkspaceServicesAreMissingWithoutThem() {
        let (controller, window) = makeIncompleteController()
        defer { window.close() }

        #expect(item(.projectWidget, of: controller) != nil)
        #expect(item(.vcsBranchWidget, of: controller) == nil)
        #expect(item(.runWidget, of: controller) == nil)
        #expect(item(.searchEverywhereWidget, of: controller) != nil)
        #expect(item(.settingsWidget, of: controller) != nil)
    }

    @Test
    func widgetsThatNeedAWorkspaceAreMissingWithoutOne() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        #expect(item(.projectWidget, of: controller) == nil)
        #expect(item(.vcsBranchWidget, of: controller) == nil)
        #expect(item(.runWidget, of: controller) == nil)
        #expect(item(.searchEverywhereWidget, of: controller) != nil)
        #expect(item(.settingsWidget, of: controller) != nil)
    }

    @Test
    func collapsingTheToolbarShowsTheFolderNameAsTheWindowTitleAndRemembersIt() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.toggleToolbar()

            #expect(harness.controller.toolbarCollapsed)
            #expect(harness.window.toolbar == nil)
            #expect(harness.window.titleVisibility == .visible)
            #expect(harness.window.title == directory.lastPathComponent)
            #expect(harness.window.titlebarSeparatorStyle == .none)
            #expect(harness.workspace.getFromWorkspaceState(.toolbarCollapsed) as? Bool == true)

            harness.controller.toggleToolbar()

            #expect(!harness.controller.toolbarCollapsed)
            #expect(harness.window.toolbar?.identifier == "DreamderMainToolbar")
            #expect(harness.window.titleVisibility == .hidden)
            #expect(harness.workspace.getFromWorkspaceState(.toolbarCollapsed) as? Bool == false)
        }
    }

    @Test
    func aCollapsedToolbarWithoutAWorkspaceTitlesTheWindowEmpty() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.toggleToolbar()

        #expect(window.title == "Empty")
        #expect(window.toolbar == nil)
    }

    @Test
    func toolbarIdentifiersUsedByTheNotificationItemAreStable() {
        #expect(NSToolbarItem.Identifier.activityViewer.rawValue == "ActivityViewer")
        #expect(NSToolbarItem.Identifier.notificationItem.rawValue == "notificationItem")
    }
}
