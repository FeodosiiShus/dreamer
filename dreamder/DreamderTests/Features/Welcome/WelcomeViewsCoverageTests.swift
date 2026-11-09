import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct WelcomeViewsCoverageTests {
    private func makeModel(
        _ defaults: UserDefaults,
        paths: [String],
        recorder: WelcomeRecorder
    ) -> WelcomeViewModel {
        WelcomeViewModel(
            manager: makeWelcomeManager(defaults, paths: paths),
            services: recorder.services(),
            home: "/Users/me"
        )
    }

    @Test
    func rowActionsForwardTheirProjectToTheModel() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: ["/p/a", "/p/b"], recorder: recorder)
        let project = try #require(model.projects.first)
        let row = WelcomeProjectRow(project: project, isSelected: false, model: model)

        row.reveal()
        row.copyPath()
        row.openProject()
        row.remove()

        #expect(recorder.revealed == [[project.url]])
        #expect(recorder.copied == [project.path])
        #expect(recorder.opened == [project.url])
        #expect(recorder.confirmed.map(\.path) == [project.path])
        #expect(model.manager.recentPaths == ["/p/b"])
    }

    @Test
    func theHoverStateFollowsItsLastReport() {
        let state = WelcomeHoverState()
        #expect(state.isHovering == false)

        state.setHovering(true)
        #expect(state.isHovering)

        state.setHovering(false)
        #expect(state.isHovering == false)
        #expect(WelcomeHoverState(isHovering: true).isHovering)
    }

    @Test
    func hoveringAndSelectingARowPaintItDifferentlyFromAnIdleRow() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: ["/p/a"], recorder: WelcomeRecorder())
        let project = try #require(model.projects.first)
        let size = NSSize(width: 480, height: 80)
        let idle = HostedViewFixture.host(size: size) {
            WelcomeProjectRow(project: project, isSelected: false, model: model)
        }
        let hovered = HostedViewFixture.host(size: size) {
            WelcomeProjectRow(
                project: project,
                isSelected: false,
                model: model,
                hoverState: WelcomeHoverState(isHovering: true)
            )
        }
        let selected = HostedViewFixture.host(size: size) {
            WelcomeProjectRow(project: project, isSelected: true, model: model)
        }
        defer {
            idle.close()
            hovered.close()
            selected.close()
        }
        try await idle.settle(.milliseconds(100))
        try await hovered.settle(.milliseconds(100))
        try await selected.settle(.milliseconds(100))
        let resting = idle.snapshot()

        #expect(HostedView.pixelsDiffer(resting, hovered.snapshot()))
        #expect(HostedView.pixelsDiffer(resting, selected.snapshot()))
    }

    @Test
    func aHoveredRowButtonIsHighlighted() async throws {
        let idle = HostedViewFixture.host(size: NSSize(width: 80, height: 60)) {
            WelcomeRowButton(icon: "general/close", help: "Remove", action: {})
        }
        let hovered = HostedViewFixture.host(size: NSSize(width: 80, height: 60)) {
            WelcomeRowButton(
                icon: "general/close",
                help: "Remove",
                hoverState: WelcomeHoverState(isHovering: true),
                action: {}
            )
        }
        defer {
            idle.close()
            hovered.close()
        }
        try await idle.settle(.milliseconds(100))
        try await hovered.settle(.milliseconds(100))

        #expect(HostedView.pixelsDiffer(idle.snapshot(), hovered.snapshot()))
    }

    @Test
    func aHoveredActionButtonIsHighlightedAndTheStylesDiffer() async throws {
        let size = NSSize(width: 320, height: 80)
        let large = HostedViewFixture.host(size: size) {
            WelcomeActionButton(title: "Open", icon: "general/open", style: .large, action: {})
        }
        let hovered = HostedViewFixture.host(size: size) {
            WelcomeActionButton(
                title: "Open",
                icon: "general/open",
                style: .large,
                hoverState: WelcomeHoverState(isHovering: true),
                action: {}
            )
        }
        let toolbar = HostedViewFixture.host(size: size) {
            WelcomeActionButton(title: "Open", icon: "general/open", style: .toolbar, action: {})
        }
        defer {
            large.close()
            hovered.close()
            toolbar.close()
        }
        try await large.settle(.milliseconds(100))
        try await hovered.settle(.milliseconds(100))
        try await toolbar.settle(.milliseconds(100))
        let resting = large.snapshot()

        #expect(HostedView.pixelsDiffer(resting, hovered.snapshot()))
        #expect(HostedView.pixelsDiffer(resting, toolbar.snapshot()))
    }

    @Test
    func aTabButtonSelectsItsTabAndPaintsSelection() async throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let model = makeModel(defaults, paths: [], recorder: WelcomeRecorder())
        let selected = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            WelcomeTabButton(tab: .projects, isSelected: true, model: model)
        }
        let unselected = HostedViewFixture.host(size: NSSize(width: 200, height: 60)) {
            WelcomeTabButton(tab: .projects, isSelected: false, model: model)
        }
        defer {
            selected.close()
            unselected.close()
        }
        try await selected.settle(.milliseconds(100))
        try await unselected.settle(.milliseconds(100))

        WelcomeTabButton(tab: .projects, isSelected: false, model: model).select()

        #expect(model.selectedTab == .projects)
        #expect(HostedView.pixelsDiffer(selected.snapshot(), unselected.snapshot()))
    }

    @Test
    func theListKeyHandlersMoveOpenAndRemoveTheSelection() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: ["/p/a", "/p/b", "/p/c"], recorder: recorder)
        let list = WelcomeProjectsList(model: model)

        #expect(list.moveDown() == .handled)
        #expect(model.selection == "/p/b")
        #expect(list.moveUp() == .handled)
        #expect(model.selection == "/p/a")
        #expect(list.openSelection() == .handled)
        #expect(recorder.opened == [URL(filePath: "/p/a", directoryHint: .isDirectory)])
        #expect(list.removeSelection() == .handled)
        #expect(recorder.confirmed.map(\.path) == ["/p/a"])
        #expect(model.manager.recentPaths == ["/p/b", "/p/c"])
    }

    @Test
    func droppingURLsOpensThemAndReportsWhetherAnythingWasDropped() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }
        let recorder = WelcomeRecorder()
        let model = makeModel(defaults, paths: [], recorder: recorder)
        let view = WelcomeView(model: model)
        let dropped = URL(filePath: "/p/dropped")

        #expect(view.dropURLs([dropped], at: .zero))
        #expect(view.dropURLs([], at: .zero) == false)
        #expect(recorder.opened == [dropped])
    }
}
