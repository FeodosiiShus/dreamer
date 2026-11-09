import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalAppearanceRefreshTests {
    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    @Test
    func refreshingAnUnchangedAppearanceTouchesNothingAndAChangedOneAppliesOnlyTheNewColors() async throws {
        try await withTempDir { directory in
            let themeModel = makeBundledThemeModel(in: directory)
            let first = try #require(themeModel.themes.first)
            let second = try #require(themeModel.themes.first { $0.terminal.text != first.terminal.text })
            themeModel.selectedTheme = first
            themeModel.selectedDarkTheme = first
            await withTerminalCoverageTheme(matchAppearance: false) {
                let view = TerminalEmulatorView(
                    url: directory,
                    terminalID: UUID(),
                    themeModel: themeModel
                ) { _ in }
                let coordinator = view.makeCoordinator()
                let terminal = terminalCoverageView()
                coordinator.appliedAppearance = view.configureView(terminal)
                terminal.feed(text: "\u{1B}[?1h")
                #expect(terminal.getTerminal().applicationCursor)
                terminal.nativeForegroundColor = .red

                view.refreshAppearance(of: terminal, coordinator: coordinator)

                #expect(terminal.nativeForegroundColor == .red)
                #expect(terminal.getTerminal().applicationCursor)

                themeModel.selectedTheme = second
                view.refreshAppearance(of: terminal, coordinator: coordinator)

                #expect(
                    terminalCoverageRGB(terminal.nativeForegroundColor)
                        == terminalCoverageRGB(NSColor(second.terminal.text.swiftColor))
                )
                #expect(terminal.getTerminal().applicationCursor)
                #expect(coordinator.appliedAppearance?.colors == second.terminal)

                terminal.nativeForegroundColor = .green
                view.refreshAppearance(of: terminal, coordinator: coordinator)
                #expect(terminal.nativeForegroundColor == .green)
            }
        }
    }

    @Test
    func aTerminalWithoutAnAppliedAppearanceReceivesItOnTheFirstRefresh() async throws {
        try withTempDir { directory in
            let view = TerminalEmulatorView(
                url: directory,
                terminalID: UUID(),
                themeModel: makeEmptyThemeModel(in: directory)
            ) { _ in }
            let coordinator = view.makeCoordinator()
            let terminal = terminalCoverageView()
            #expect(coordinator.appliedAppearance == nil)

            view.refreshAppearance(of: terminal, coordinator: coordinator)

            #expect(coordinator.appliedAppearance != nil)
            #expect(terminal.nativeBackgroundColor.alphaComponent == 0)
        }
    }

    @Test
    func theHostedTerminalFillsItsContainerAndKeepsItsModesAcrossLayoutPasses() async throws {
        try await withTempDir { directory in
            let task = fixture.makeTask(command: "true")
            let activeTask = CEActiveTask(task: task)
            let themeModel = makeEmptyThemeModel(in: directory)
            let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
                TerminalEmulatorView(url: directory, task: activeTask, themeModel: themeModel)
            }
            defer {
                hosted.close()
                TerminalCache.shared.removeCachedView(task.id)
            }
            hosted.layout()
            let container = try #require(hosted.views(of: TerminalContainerView.self).first)
            try await eventually { container.terminal.frame.size == container.bounds.size }
            #expect(container.terminal.superview === container)
            container.terminal.feed(text: "\u{1B}[?1h")
            #expect(container.terminal.getTerminal().applicationCursor)

            hosted.window.setContentSize(NSSize(width: 520, height: 360))
            hosted.layout()

            try await eventually { container.terminal.frame.size == container.bounds.size }
            #expect(container.terminal.getTerminal().applicationCursor)
        }
    }
}
