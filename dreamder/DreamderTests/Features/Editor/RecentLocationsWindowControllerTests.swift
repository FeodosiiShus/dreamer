import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct RecentLocationsWindowControllerTests {
    @MainActor
    private struct Harness {
        let fixture: RecentLocationsPopupFixture
        let controller: DreamderWindowController
        let window: NSWindow

        var panels: [ShowUsagesPanel] {
            (window.childWindows ?? []).compactMap { $0 as? ShowUsagesPanel }
        }

        func close() {
            for child in window.childWindows ?? [] {
                child.close()
            }
            window.close()
            fixture.workspace.close()
        }
    }

    private func makeHarness(in directory: URL, names: [String]) throws -> Harness {
        let fixture = try RecentLocationsPopupFixture.make(in: directory, names: names)
        fixture.workspace.makeWindowControllers()
        let controller = try #require(fixture.workspace.windowControllers.first as? DreamderWindowController)
        let window = try #require(controller.window)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: false)
        return Harness(fixture: fixture, controller: controller, window: window)
    }

    private func model(of panel: ShowUsagesPanel) throws -> RecentLocationsViewModel {
        let hosting = try #require(panel.contentView as? NSHostingView<RecentLocationsView>)
        return hosting.rootView.model
    }

    @Test
    func theActionShowsAFixedSizePanelWithTheRecentPlaces() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt", "b.txt"])
            defer { harness.close() }
            try harness.fixture.open("a.txt", line: 1)
            try harness.fixture.open("b.txt", line: 1)
            harness.fixture.recordBack([harness.fixture.place("a.txt", line: 5)])

            harness.controller.showRecentLocations(nil)

            let panel = try #require(harness.panels.first)
            let hosting = try #require(panel.contentView as? NSHostingView<RecentLocationsView>)
            #expect(harness.panels.count == 1)
            #expect(hosting.sizingOptions.isEmpty)
            #expect(hosting.frame.size == RecentLocationsPanelHost.panelSize)
            #expect(hosting.rootView.model.rows.map(\.fileName) == ["a.txt"])
            #expect(!hosting.rootView.model.showChangedOnly)
        }
    }

    @Test
    func invokingTheActionAgainTogglesTheEditedOnlyList() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            defer { harness.close() }
            harness.controller.showRecentLocations(nil)
            let panel = try #require(harness.panels.first)
            let model = try model(of: panel)

            harness.controller.showRecentLocations(nil)
            #expect(model.showChangedOnly)
            #expect(harness.panels.count == 1)

            harness.controller.showRecentLocations(nil)
            #expect(!model.showChangedOnly)
            #expect(harness.panels.count == 1)
        }
    }

    @Test
    func escapeClosesThePanelAndAllowsReopening() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt"])
            defer { harness.close() }
            harness.controller.showRecentLocations(nil)
            let panel = try #require(harness.panels.first)

            let handled = panel.onKeyEvent?(try recentLocationsKeyEvent(53))

            #expect(handled == true)
            #expect(harness.panels.isEmpty)
            harness.controller.showRecentLocations(nil)
            #expect(harness.panels.count == 1)
            #expect(harness.panels.first !== panel)
        }
    }

    @Test
    func returnOpensTheSelectedPlaceAndClosesThePanel() async throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory, names: ["a.txt", "b.txt"])
            defer { harness.close() }
            try harness.fixture.open("a.txt", line: 1)
            try harness.fixture.open("b.txt", line: 12)
            harness.fixture.recordBack([harness.fixture.place("a.txt", line: 7)])
            harness.controller.showRecentLocations(nil)
            let panel = try #require(harness.panels.first)

            let handled = panel.onKeyEvent?(try recentLocationsKeyEvent(36))

            #expect(handled == true)
            #expect(harness.panels.isEmpty)
            #expect(harness.fixture.selectedName == "a.txt")
            #expect(harness.fixture.caretLine == 7)
            #expect(harness.fixture.tracker.history.backPlaces.map(\.fileURL.lastPathComponent).contains("b.txt"))
        }
    }

    @Test
    func controllersWithoutAWorkspaceShowNothing() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        let controller = DreamderWindowController(window: window, workspace: nil)

        controller.showRecentLocations(nil)

        #expect((window.childWindows ?? []).isEmpty)
    }
}
