import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized)
struct HostingSizingPolicyTests {
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }
    }

    private func makeHarness(in directory: URL) throws -> Harness {
        let workspace = WorkspaceDocument()
        try workspace.read(from: directory, ofType: "")
        workspace.makeWindowControllers()
        let controller = try #require(workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return Harness(workspace: workspace, controller: controller, window: window)
    }

    private func childPanel<Panel: NSPanel>(_ type: Panel.Type, in window: NSWindow) throws -> Panel {
        try #require(window.childWindows?.compactMap { $0 as? Panel }.first)
    }

    @Test
    func toolbarHostingViewsUseStandardBoundsAroundFixedSizeRoots() {
        let hostingView = DreamderWindowController.makeToolbarHostingView(Text("Toolbar"))

        #expect(hostingView.sizingOptions == .standardBounds)
    }

    @Test
    func toolbarItemsAreHostedWithIntrinsicSizing() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let toolbar = NSToolbar(identifier: "HostingSizingPolicyTests")
            let identifiers: [NSToolbarItem.Identifier] = [
                .projectWidget,
                .searchEverywhereWidget,
                .runWidget,
                .settingsWidget
            ]

            for identifier in identifiers {
                let item = try #require(harness.controller.toolbar(
                    toolbar,
                    itemForItemIdentifier: identifier,
                    willBeInsertedIntoToolbar: false
                ))
                let view = try #require(item.view)

                #expect(String(describing: type(of: view)).contains("NSHostingView"))
                #expect(view.intrinsicContentSize.width > 0)
                #expect(view.intrinsicContentSize.height > 0)
            }

            let branchItem = try #require(harness.controller.toolbar(
                toolbar,
                itemForItemIdentifier: .vcsBranchWidget,
                willBeInsertedIntoToolbar: false
            ))
            #expect(String(describing: type(of: try #require(branchItem.view))).contains("NSHostingView"))
        }
    }

    @Test
    func windowControllerInstallsWorkspaceHostingControllerWithoutContentSizing() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            let hostingController = try #require(harness.controller.workspaceHostingController)

            #expect(hostingController.sizingOptions == [])
            #expect(hostingController.view is NSHostingView<AnyView>)
            #expect(harness.window.contentViewController === hostingController)
        }
    }

    @Test
    func searchEverywherePanelHasFixedHostingSize() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            SearchEverywherePanelHost.shared.toggle(in: harness.controller)

            let panel = try childPanel(SearchEverywherePanel.self, in: harness.window)
            let hostingView = try #require(panel.contentView as? NSHostingView<SearchEverywhereView>)
            #expect(hostingView.sizingOptions == [])
        }
    }

    @Test
    func quickDocumentationPanelHasFixedHostingSize() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            QuickDocumentationPanelHost.shared.showMessage("No documentation", in: harness.controller)

            let panel = try childPanel(QuickDocumentationPanel.self, in: harness.window)
            let hostingView = try #require(panel.contentView as? NSHostingView<QuickDocumentationView>)
            #expect(hostingView.sizingOptions == [])
        }
    }

    @Test
    func showUsagesPanelHasFixedHostingSize() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            ShowUsagesPanelHost.shared.showMessage("No usages", in: harness.controller)

            let panel = try childPanel(ShowUsagesPanel.self, in: harness.window)
            let hostingView = try #require(panel.contentView as? NSHostingView<ShowUsagesView>)
            #expect(hostingView.sizingOptions == [])
        }
    }

    @Test
    func branchesPopupPanelHasFixedHostingSize() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let sourceControlManager = try #require(harness.workspace.sourceControlManager)
            let anchor = try #require(harness.window.contentView)

            BranchesPopupPanelHost.shared.show(
                sourceControlManager: sourceControlManager,
                workspace: harness.workspace,
                anchoredTo: anchor
            )

            let panel = try childPanel(BranchesPopupPanel.self, in: harness.window)
            let hostingView = try #require(panel.contentView as? NSHostingView<GitBranchesPopupView>)
            #expect(hostingView.sizingOptions == [])
        }
    }
}
