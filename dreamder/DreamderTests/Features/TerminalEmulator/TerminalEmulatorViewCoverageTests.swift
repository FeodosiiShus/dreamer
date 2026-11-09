import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class TerminalEmulatorTitleBox {
    var titles: [String] = []
}

@MainActor
func makeEmptyThemeModel(in directory: URL) -> ThemeModel {
    ThemeModel(baseURL: directory, bundledThemesURL: nil, preferencesStore: Dreamder.Settings(baseURL: directory))
}

@MainActor
func makeBundledThemeModel(in directory: URL) -> ThemeModel {
    ThemeModel(
        baseURL: directory,
        bundledThemesURL: ThemeModel.defaultBundledThemesURL,
        preferencesStore: Dreamder.Settings(baseURL: directory)
    )
}

@MainActor
func withTerminalCoverageTheme(
    matchAppearance: Bool,
    useThemeBackground: Bool = true,
    perform body: () async throws -> Void
) async rethrows {
    try await withCoverageSettingsStore { store in
        store.preferences.theme.matchAppearance = matchAppearance
        store.preferences.theme.useThemeBackground = useThemeBackground
        try await body()
    }
}

func terminalCoverageRGB(_ color: NSColor) -> [CGFloat]? {
    color.usingColorSpace(.sRGB).map { [$0.redComponent, $0.greenComponent, $0.blueComponent] }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalEmulatorViewCoverageTests {
    private let fixture: TasksCoverageFixture

    init() throws {
        fixture = try TasksCoverageFixture()
    }

    @Test
    func configureViewFallsBackToSystemColorsWithoutAThemeAndAppliesTerminalSettings() async throws {
        try await withTempDir { directory in
            await withTerminalCoverageSettings({ settings in
                settings.cursorStyle = .underline
                settings.cursorBlink = true
                settings.useTextEditorFont = false
                settings.darkAppearance = true
                settings.optionAsMeta = true
            }) {
                await withTerminalCoverageTheme(matchAppearance: true) {
                    let view = TerminalEmulatorView(
                        url: directory,
                        terminalID: UUID(),
                        themeModel: makeEmptyThemeModel(in: directory)
                    ) { _ in }
                    let terminal = terminalCoverageView()

                    view.configureView(terminal)

                    #expect(terminal.appearance?.name == .darkAqua)
                    #expect(terminal.optionAsMetaKey)
                    #expect(terminal.caretColor.alphaComponent == 0.5)
                    #expect(terminal.caretTextColor?.alphaComponent == 0.5)
                    let expectedFont = SettingsScope.current?.preferences.terminal.font.current
                    #expect(expectedFont != nil)
                    #expect(terminal.font.fontName == expectedFont?.fontName)
                    #expect(terminal.font.pointSize == expectedFont?.pointSize)
                    let scrollers = terminal.subviews.compactMap { $0 as? NSScroller }
                    #expect(!scrollers.isEmpty)
                    #expect(scrollers.allSatisfy { $0.isHidden })
                }
            }
        }
    }

    @Test
    func configureViewSupportsBarCursorsAndTheEditorFont() async throws {
        try await withTempDir { directory in
            await withTerminalCoverageSettings({ settings in
                settings.cursorStyle = .bar
                settings.cursorBlink = true
                settings.useTextEditorFont = true
                settings.darkAppearance = false
            }) {
                await withTerminalCoverageTheme(matchAppearance: false) {
                    let view = TerminalEmulatorView(
                        url: directory,
                        terminalID: UUID(),
                        themeModel: makeEmptyThemeModel(in: directory)
                    ) { _ in }
                    let terminal = terminalCoverageView()

                    view.configureView(terminal)

                    let expectedFont = SettingsScope.current?.preferences.textEditing.font.current
                    #expect(expectedFont != nil)
                    #expect(terminal.appearance == nil)
                    #expect(terminal.font.fontName == expectedFont?.fontName)
                    #expect(!terminal.optionAsMetaKey)
                }
            }
        }
    }

    @Test
    func configureViewSupportsSteadyBarAndBlockCursors() async throws {
        try await withTempDir { directory in
            let view = TerminalEmulatorView(
                url: directory,
                terminalID: UUID(),
                themeModel: makeEmptyThemeModel(in: directory)
            ) { _ in }
            for style in [SettingsData.TerminalCursorStyle.bar, .block, .underline] {
                await withTerminalCoverageSettings({ settings in
                    settings.cursorStyle = style
                    settings.cursorBlink = false
                }) {
                    view.configureView(terminalCoverageView())
                }
            }
        }
    }

    @Test
    func configureViewSupportsBlinkingBlockCursors() async throws {
        try await withTempDir { directory in
            let view = TerminalEmulatorView(
                url: directory,
                terminalID: UUID(),
                themeModel: makeEmptyThemeModel(in: directory)
            ) { _ in }
            await withTerminalCoverageSettings({ settings in
                settings.cursorStyle = .block
                settings.cursorBlink = true
                settings.optionAsMeta = true
            }) {
                let terminal = terminalCoverageView()

                view.configureView(terminal)

                #expect(terminal.optionAsMetaKey)
                #expect(terminal.nativeBackgroundColor.alphaComponent == 0)
            }
        }
    }

    @Test
    func taskModeHasNoTitleHandlerSoTerminalTitlesAreDropped() throws {
        try withTempDir { directory in
            let activeTask = CEActiveTask(task: fixture.makeTask(command: "true"))
            let view = TerminalEmulatorView(
                url: directory,
                task: activeTask,
                themeModel: makeEmptyThemeModel(in: directory)
            )
            let coordinator = view.makeCoordinator()

            coordinator.setTerminalTitle(source: terminalCoverageView(), title: "ignored")

            #expect(view.onTitleChange == nil)
            #expect(coordinator.onTitleChange == nil)
        }
    }

    @Test
    func configureViewUsesTheSelectedThemeColors() async throws {
        try await withTempDir { directory in
            let themeModel = makeBundledThemeModel(in: directory)
            let theme = try #require(themeModel.themes.first)
            themeModel.selectedTheme = theme
            themeModel.selectedDarkTheme = theme
            await withTerminalCoverageSettings({ $0.darkAppearance = false }) {
                await withTerminalCoverageTheme(matchAppearance: false) {
                    let view = TerminalEmulatorView(
                        url: directory,
                        terminalID: UUID(),
                        themeModel: themeModel
                    ) { _ in }
                    let terminal = terminalCoverageView()

                    view.configureView(terminal)

                    #expect(
                        terminalCoverageRGB(terminal.nativeForegroundColor)
                            == terminalCoverageRGB(NSColor(theme.terminal.text.swiftColor))
                    )
                    #expect(
                        terminalCoverageRGB(terminal.selectedTextBackgroundColor)
                            == terminalCoverageRGB(NSColor(theme.terminal.selection.swiftColor))
                    )
                }
            }
            await withTerminalCoverageSettings({ $0.darkAppearance = true }) {
                await withTerminalCoverageTheme(matchAppearance: true) {
                    let view = TerminalEmulatorView(
                        url: directory,
                        terminalID: UUID(),
                        themeModel: themeModel
                    ) { _ in }
                    let terminal = terminalCoverageView()

                    view.configureView(terminal)

                    #expect(
                        terminalCoverageRGB(terminal.nativeForegroundColor)
                            == terminalCoverageRGB(NSColor(theme.terminal.text.swiftColor))
                    )
                }
            }
        }
    }

    @Test
    func oldTerminalSettingsFilesWithTheRemovedBackgroundKeyStillDecode() throws {
        let json = Data(#"{"useThemeBackground": false, "optionAsMeta": true}"#.utf8)

        let settings = try JSONDecoder().decode(SettingsData.TerminalSettings.self, from: json)

        #expect(settings.optionAsMeta)
    }

    @Test
    func terminalStaysTransparentEvenWhenTheThemeBackgroundIsUsed() async throws {
        try await withTempDir { directory in
            let themeModel = makeBundledThemeModel(in: directory)
            let theme = try #require(themeModel.themes.first)
            themeModel.selectedTheme = theme
            themeModel.selectedDarkTheme = theme
            let view = TerminalEmulatorView(
                url: directory,
                terminalID: UUID(),
                themeModel: themeModel
            ) { _ in }

            await withTerminalCoverageTheme(matchAppearance: false, useThemeBackground: true) {
                let terminal = terminalCoverageView()
                view.configureView(terminal)
                #expect(terminal.nativeBackgroundColor.alphaComponent == 0)
            }
        }
    }

    @Test
    func configureViewToleratesATerminalWithoutAScroller() async throws {
        try withTempDir { directory in
            let view = TerminalEmulatorView(
                url: directory,
                terminalID: UUID(),
                themeModel: makeEmptyThemeModel(in: directory)
            ) { _ in }
            let terminal = terminalCoverageView()
            for scroller in terminal.subviews.compactMap({ $0 as? NSScroller }) {
                scroller.removeFromSuperview()
            }

            view.configureView(terminal)

            #expect(terminal.subviews.compactMap { $0 as? NSScroller }.isEmpty)
        }
    }

    @Test
    func taskModeAdoptsTheTaskOutputAndConfiguresItOnce() async throws {
        try await withTempDir { directory in
            let task = fixture.makeTask(command: "true")
            let activeTask = CEActiveTask(task: task)
            let themeModel = makeEmptyThemeModel(in: directory)
            let first = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
                TerminalEmulatorView(url: directory, task: activeTask, themeModel: themeModel)
            }
            defer {
                first.close()
                TerminalCache.shared.removeCachedView(task.id)
            }
            first.layout()
            try await first.settle()

            let output = try #require(activeTask.output)
            #expect(activeTask.hasOutputBeenConfigured)
            #expect(output.processDelegate != nil)
            #expect(TerminalCache.shared.getTerminalView(task.id) === output)
            #expect(first.views(of: CEActiveTaskTerminalView.self).contains { $0 === output })
            first.close()

            let second = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
                TerminalEmulatorView(url: directory, task: activeTask, themeModel: themeModel)
            }
            defer { second.close() }
            second.layout()
            try await second.settle()

            #expect(activeTask.output === output)
            #expect(second.views(of: CEActiveTaskTerminalView.self).contains { $0 === output })

            second.close()
            activeTask.hasOutputBeenConfigured = false
            let third = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
                TerminalEmulatorView(url: directory, task: activeTask, themeModel: themeModel)
            }
            defer { third.close() }
            third.layout()
            try await third.settle()

            #expect(activeTask.hasOutputBeenConfigured)
            #expect(activeTask.output === output)
        }
    }

    @Test
    func shellModeReusesACachedTerminalAndForwardsTitleChanges() async throws {
        try await withTempDir { directory in
            let id = UUID()
            let cached = terminalCoverageView()
            TerminalCache.shared.cacheTerminalView(for: id, view: cached)
            defer { TerminalCache.shared.removeCachedView(id) }
            let box = TerminalEmulatorTitleBox()
            let hosted = HostedViewFixture.host(size: NSSize(width: 480, height: 320)) {
                TerminalEmulatorView(
                    url: directory,
                    terminalID: id,
                    shellType: .zsh,
                    themeModel: makeEmptyThemeModel(in: directory)
                ) { box.titles.append($0) }
            }
            defer { hosted.close() }
            hosted.layout()
            try await hosted.settle()

            #expect(cached.processDelegate != nil)
            #expect(hosted.views(of: CELocalShellTerminalView.self).contains { $0 === cached })
            #expect(TerminalCache.shared.getTerminalView(id) === cached)

            cached.setTerminalTitle(source: cached, title: "renamed")
            #expect(box.titles == ["renamed"])
        }
    }

    @Test
    func coordinatorForwardsTitlesAndIgnoresDirectoryAndSizeChanges() {
        let box = TerminalEmulatorTitleBox()
        let coordinator = TerminalEmulatorView.Coordinator(
            terminalID: UUID(),
            mode: .shell(shellType: nil)
        ) { box.titles.append($0) }
        let view = terminalCoverageView()

        coordinator.hostCurrentDirectoryUpdate(source: view, directory: "file:///tmp")
        coordinator.sizeChanged(source: view, newCols: 10, newRows: 5)
        coordinator.setTerminalTitle(source: view, title: "first")
        coordinator.onTitleChange = { box.titles.append($0.uppercased()) }
        coordinator.setTerminalTitle(source: view, title: "second")

        #expect(box.titles == ["first", "SECOND"])
    }

    @Test
    func finishedShellSessionsExplainHowToStartANewOne() {
        let id = UUID()
        let view = terminalCoverageView()
        TerminalCache.shared.cacheTerminalView(for: id, view: view)
        defer { TerminalCache.shared.removeCachedView(id) }
        let coordinator = TerminalEmulatorView.Coordinator(
            terminalID: id,
            mode: .shell(shellType: .zsh)
        ) { _ in }

        coordinator.processTerminated(source: view, exit: nil)
        #expect(TerminalCache.shared.getTerminalView(id) === view)
        #expect(terminalCoverageText(view).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        coordinator.processTerminated(source: view, exit: .exited(code: 5))
        let text = terminalCoverageText(view)
        #expect(text.contains("Exit code: 5"))
        #expect(text.contains("To open a new session, create a new terminal tab."))
        #expect(TerminalCache.shared.getTerminalView(id) == nil)
    }

    @Test
    func finishedTasksKeepTheirTerminalCached() {
        let task = fixture.makeTask(command: "true")
        let activeTask = CEActiveTask(task: task)
        let view = terminalCoverageView()
        TerminalCache.shared.cacheTerminalView(for: task.id, view: view)
        defer { TerminalCache.shared.removeCachedView(task.id) }
        let coordinator = TerminalEmulatorView.Coordinator(
            terminalID: task.id,
            mode: .task(activeTask: activeTask)
        ) { _ in }

        coordinator.processTerminated(source: view, exit: .exited(code: 0))

        #expect(TerminalCache.shared.getTerminalView(task.id) === view)
        #expect(terminalCoverageText(view).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
