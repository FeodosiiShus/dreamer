import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct DreamderWindowControllerSearchEverywhereCoverageTests {
    @MainActor
    private struct Harness {
        let workspace: WorkspaceDocument
        let controller: DreamderWindowController
        let window: NSWindow

        var panels: [SearchEverywherePanel] {
            (window.childWindows ?? []).compactMap { $0 as? SearchEverywherePanel }
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            workspace.close()
        }

        func tab(of panel: SearchEverywherePanel) throws -> SearchEverywhereTab {
            let hostingView = try #require(panel.contentView as? NSHostingView<SearchEverywhereView>)
            return hostingView.rootView.model.tab
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

    @Test
    func searchEverywhereOpensItsPanelOnTheAllTab() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }

            harness.controller.openSearchEverywhere(nil)

            let panel = try #require(harness.panels.first)
            #expect(harness.panels.count == 1)
            #expect(try harness.tab(of: panel) == .all)
        }
    }

    @Test
    func eachSearchEverywhereActionSelectsItsTabInTheSamePanel() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let actions: [(SearchEverywhereTab, (Any?) -> Void)] = [
                (.classes, harness.controller.openSearchEverywhereClasses),
                (.files, harness.controller.openSearchEverywhereFiles),
                (.symbols, harness.controller.openSearchEverywhereSymbols),
                (.actions, harness.controller.openSearchEverywhereActions),
                (.text, harness.controller.openSearchEverywhereText)
            ]
            var firstPanel: SearchEverywherePanel?

            for (tab, action) in actions {
                action(nil)

                let panel = try #require(harness.panels.first)
                #expect(harness.panels.count == 1)
                #expect(try harness.tab(of: panel) == tab)
                firstPanel = firstPanel ?? panel
                #expect(panel === firstPanel)
            }
        }
    }

    @Test
    func searchEverywhereNeedsAWorkspace() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.openSearchEverywhere(nil)
        controller.openSearchEverywhereText(nil)

        #expect((window.childWindows ?? []).isEmpty)
    }
}
