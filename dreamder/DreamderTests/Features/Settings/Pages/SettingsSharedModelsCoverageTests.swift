import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct SettingsSharedModelsCoverageTests {
    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    @Test
    func generalSettingsDecodeDefaultsAndRoundTripEveryField() throws {
        #expect(try decode(SettingsData.GeneralSettings.self, from: "{}") == SettingsData.GeneralSettings())

        var settings = SettingsData.GeneralSettings()
        settings.appAppearance = .light
        settings.dimEditorsWithoutFocus = true
        settings.fileExtensionsVisibility = .hideOnly
        settings.shownFileExtensions = .init(extensions: ["a"])
        settings.hiddenFileExtensions = .init(extensions: ["b"])
        settings.fileIconStyle = .monochrome
        settings.reopenBehavior = .openPanel
        settings.reopenWindowAfterClose = .quit
        settings.findNavigatorDetail = .upTo10
        settings.revealFileOnFocusChange = true
        settings.isAutoSaveOn = false

        #expect(try roundTrip(settings) == settings)
        #expect(SettingsData.GeneralSettings().searchKeys.count == 13)
    }

    @Test
    func appearancesApplyToTheApplication() {
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }

        SettingsData.Appearances.dark.applyAppearance()
        #expect(NSApp.appearance?.name == .darkAqua)
        SettingsData.Appearances.light.applyAppearance()
        #expect(NSApp.appearance?.name == .aqua)
        SettingsData.Appearances.system.applyAppearance()
        #expect(NSApp.appearance == nil)
    }

    @Test
    func fileExtensionsConvertToAndFromEditableText() {
        var extensions = SettingsData.FileExtensions(extensions: ["a", "b"])
        #expect(extensions.string == "a, b")

        extensions.string = "x, y ,z"
        #expect(extensions.extensions == ["x", "y", "z"])

        extensions.string = "x, y,"
        #expect(extensions.extensions == ["x", "y"])

        var shorter = SettingsData.FileExtensions(extensions: ["x"])
        shorter.string = "x,"
        #expect(shorter.extensions == ["x", ""])

        #expect(SettingsData.FileExtensions.default.extensions.contains("swift"))
    }

    @Test
    func navigatorDetailLabelsDescribeTheLineLimit() {
        #expect(SettingsData.NavigatorDetail.upTo1.label == "One Line")
        #expect(SettingsData.NavigatorDetail.upTo5.label == "Up to 5 lines")
        #expect(SettingsData.NavigatorDetail.allCases.count == 7)
    }

    @Test
    func terminalSettingsDecodeDefaultsAndRoundTripEveryField() throws {
        #expect(try decode(SettingsData.TerminalSettings.self, from: "{}") == SettingsData.TerminalSettings())

        var settings = SettingsData.TerminalSettings()
        settings.darkAppearance = true
        settings.optionAsMeta = true
        settings.shell = .zsh
        settings.font.size = 15
        settings.font.name = "Menlo"
        settings.font.weight = .bold
        settings.cursorStyle = .bar
        settings.cursorBlink = true
        settings.useTextEditorFont = false
        settings.useShellIntegration = false
        settings.useLoginShell = false

        #expect(try roundTrip(settings) == settings)
        #expect(SettingsData.TerminalSettings().searchKeys.count == 7)
    }

    @Test
    func terminalFontDecodesDefaultsAndResolvesTheCurrentFont() throws {
        let defaults = try decode(SettingsData.TerminalFont.self, from: "{}")
        #expect(defaults.size == 12)
        #expect(defaults.name == "SF Mono")
        #expect(defaults.weight == .medium)

        var custom = SettingsData.TerminalFont()
        custom.name = "Menlo"
        custom.size = 13
        custom.weight = .regular
        #expect(custom.current.pointSize == 13)

        custom.name = "Definitely Missing Font Family"
        #expect(custom.current.pointSize == 13)
        #expect(custom.current.isFixedPitch)
    }

    @Test
    func developerSettingsDecodeDefaultsAndRoundTripEveryField() throws {
        let defaults = try decode(SettingsData.DeveloperSettings.self, from: "{}")
        #expect(defaults == SettingsData.DeveloperSettings())
        #expect(defaults.lspBinaries.isEmpty)
        #expect(defaults.showInternalDevelopmentInspector == false)

        var settings = SettingsData.DeveloperSettings()
        settings.lspBinaries = ["swift": "/usr/bin/sourcekit-lsp"]
        settings.showInternalDevelopmentInspector = true

        #expect(try roundTrip(settings) == settings)
        #expect(settings.searchKeys.count == 4)
    }

    @Test
    func navigationSettingsDecodeDefaultsAndRoundTrip() throws {
        #expect(try decode(SettingsData.NavigationSettings.self, from: "{}").navigationStyle == .openInTabs)

        var settings = SettingsData.NavigationSettings()
        settings.navigationStyle = .openInPlace

        #expect(try roundTrip(settings) == settings)
        #expect(settings.searchKeys.count == 1)
    }

    @Test
    func searchSettingsDecodeDefaultsAndRoundTrip() throws {
        #expect(try decode(SettingsData.SearchSettings.self, from: "{}").ignoreGlobPatterns.isEmpty)

        var settings = SettingsData.SearchSettings()
        settings.ignoreGlobPatterns = [GlobPattern(value: "*.log"), GlobPattern(value: "build")]

        #expect(try roundTrip(settings) == settings)
        #expect(settings.searchKeys.count == 2)
    }

    @Test
    func locationsSettingsListSearchKeys() {
        #expect(SettingsData.LocationsSettings().searchKeys.count == 3)
    }

    @MainActor
    private final class PersistedPatterns {
        var latest: [GlobPattern]?
    }

    @Test
    func searchSettingsModelAddsFindsAndRemovesPatterns() async throws {
        let persisted = PersistedPatterns()
        let model = SearchSettingsModel(patterns: []) { persisted.latest = $0 }

        model.addPattern()
        model.addPattern()
        #expect(model.ignoreGlobPatterns.count == 2)
        let first = model.ignoreGlobPatterns[0]
        let second = model.ignoreGlobPatterns[1]
        #expect(model.getPattern(for: first.id) == first)
        #expect(model.getPattern(for: UUID()) == nil)

        model.selection = [first.id]
        model.removePatterns([first.id])
        #expect(model.ignoreGlobPatterns == [second])
        #expect(model.selection.isEmpty)

        model.selection = [second.id]
        model.removePatterns(nil)
        #expect(model.ignoreGlobPatterns == [second])
        #expect(model.selection.isEmpty)

        model.removePatterns([UUID()])
        #expect(model.ignoreGlobPatterns == [second])

        try await eventually { persisted.latest == [second] }
    }

    @Test
    func aSearchSettingsModelStartsFromAndPersistsIntoTheSettingsItWasBuiltFrom() async throws {
        try await withTempDir { dir in
            let store = Dreamder.Settings(baseURL: dir)
            store.preferences.search.ignoreGlobPatterns = [GlobPattern(value: "*.log")]
            let model = SearchSettingsModel(settings: store)
            #expect(model.ignoreGlobPatterns.map(\.value) == ["*.log"])

            model.addPattern()

            try await eventually { store.preferences.search.ignoreGlobPatterns == model.ignoreGlobPatterns }
            #expect(store.preferences.search.ignoreGlobPatterns.count == 2)
        }
    }

    @Test
    func theSettingsSubscriptReadsAndWritesTheSuiteItIsGiven() throws {
        try withTempDir { dir in
            let store = Dreamder.Settings(baseURL: dir)
            let other = Dreamder.Settings(baseURL: dir.appending(path: "other", directoryHint: .isDirectory))
            let pattern = GlobPattern(value: "*.generated")

            Dreamder.Settings[\.search, store].ignoreGlobPatterns = [pattern]

            #expect(Dreamder.Settings[\.search, store].ignoreGlobPatterns == [pattern])
            #expect(store.preferences.search.ignoreGlobPatterns == [pattern])
            #expect(other.preferences.search.ignoreGlobPatterns.contains(pattern) == false)
        }
    }

    @Test
    func searchSettingsModelLocatesItsFoldersInApplicationSupport() {
        let model = SearchSettingsModel.shared

        #expect(model.searchURL.lastPathComponent == "search")
        #expect(model.extensionsURL.lastPathComponent == "Extensions")
        #expect(model.settingsURL.lastPathComponent == "settings.json")
        #expect(model.searchURL == Settings.defaultBaseURL().appending(path: "search", directoryHint: .isDirectory))
    }

    @Test
    func backgroundImageFillsDescribeThemselves() {
        #expect(BackgroundImageFill.allCases.map(\.title) == ["Fill", "Fit", "Center", "Tile"])
        #expect(BackgroundImageFill.allCases.map(\.id) == ["fill", "fit", "center", "tile"])
    }

    @Test
    func backgroundImageSettingsApplyThePathToTheGivenDefaults() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suiteName) }

        BackgroundImageSettings.apply("/tmp/settings-shared.png", defaults: defaults)
        #expect(defaults.string(forKey: Islands.BackgroundImageKey.path) == "/tmp/settings-shared.png")

        BackgroundImageSettings.apply("", defaults: defaults)
        #expect(defaults.string(forKey: Islands.BackgroundImageKey.path) == "")
    }

    @Test
    func backgroundImageSettingsLoadOnlyExistingImages() async throws {
        try withTempDir { directory in
            let imageURL = directory.appending(path: "background.png")
            let representation = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: 4,
                    pixelsHigh: 4,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )
            )
            try #require(representation.representation(using: .png, properties: [:])).write(to: imageURL)

            #expect(BackgroundImageSettings.image(at: "") == nil)
            #expect(BackgroundImageSettings.image(at: directory.appending(path: "missing.png").path) == nil)
            #expect(BackgroundImageSettings.image(at: imageURL.path) != nil)
        }
    }

    @Test
    func backgroundImageSettingsChooseThroughThePanel() throws {
        let panels = FakeFilePanels(files: [URL(fileURLWithPath: "/tmp/settings-shared-chosen.png")])

        let chosen = BackgroundImageSettings.chooseImage(panels: panels)

        #expect(chosen == "/tmp/settings-shared-chosen.png")
        let request = try #require(panels.openRequests.first)
        #expect(panels.openRequests.count == 1)
        #expect(request.prompt == "Choose")
        #expect(request.message == "Choose a background image")
        #expect(request.allowedContentTypes == [.image])
        #expect(request.allowsMultipleSelection == false)
        #expect(request.canChooseDirectories == false)
        #expect(request.canChooseFiles)
        panels.chosenFiles = []
        #expect(BackgroundImageSettings.chooseImage(panels: panels) == nil)
    }

    @Test
    func backgroundImageSettingsReturnNothingWhenThePanelIsCancelled() {
        #expect(BackgroundImageSettings.chooseImage() == nil)
    }
}
