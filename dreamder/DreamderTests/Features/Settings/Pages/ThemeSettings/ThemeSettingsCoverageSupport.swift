import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

nonisolated enum ThemeSettingsCoverageThemes {
    static func make(
        name: String,
        displayName: String? = nil,
        appearance: Theme.ThemeType = .dark,
        author: String = "Tester",
        isBundled: Bool = false
    ) -> Theme {
        let accent = Theme.Attributes(color: "#112233")
        let background = Theme.Attributes(color: "#445566")
        let editor = Theme.EditorColors(
            text: accent,
            insertionPoint: accent,
            invisibles: accent,
            background: background,
            lineHighlight: accent,
            selection: accent,
            keywords: accent,
            commands: accent,
            types: accent,
            attributes: accent,
            variables: accent,
            values: accent,
            numbers: accent,
            strings: accent,
            characters: accent,
            comments: accent
        )
        let terminal = Theme.TerminalColors(
            text: accent,
            boldText: accent,
            cursor: accent,
            background: background,
            selection: accent,
            black: accent,
            red: accent,
            green: accent,
            yellow: accent,
            blue: accent,
            magenta: accent,
            cyan: accent,
            white: accent,
            brightBlack: accent,
            brightRed: accent,
            brightGreen: accent,
            brightYellow: accent,
            brightBlue: accent,
            brightMagenta: accent,
            brightCyan: accent,
            brightWhite: accent
        )
        return Theme(
            editor: editor,
            terminal: terminal,
            author: author,
            license: "MIT",
            metadataDescription: "Coverage theme",
            distributionURL: "https://example.com",
            isBundled: isBundled,
            name: name,
            displayName: displayName ?? name,
            appearance: appearance,
            version: "1"
        )
    }

    static func data(_ theme: Theme) throws -> Data {
        try JSONEncoder().encode(theme)
    }

    static func decode(_ url: URL) throws -> Theme {
        try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
    }
}

@MainActor
struct ThemeSettingsCoverageEnvironment {
    let root: URL
    let bundledURL: URL
    let baseURL: URL
    let themesURL: URL
    let outsideURL: URL
    let settings: Dreamder.Settings

    init(root: URL) throws {
        self.root = root
        bundledURL = root.appending(path: "bundled", directoryHint: .isDirectory)
        baseURL = root.appending(path: "base", directoryHint: .isDirectory)
        themesURL = baseURL.appending(path: "Themes", directoryHint: .isDirectory)
        outsideURL = root.appending(path: "outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundledURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        settings = Settings(baseURL: root.appending(path: "settings", directoryHint: .isDirectory))
    }

    @discardableResult
    func addBundled(_ theme: Theme) throws -> URL {
        let url = bundledURL.appending(path: "\(theme.name).cetheme")
        try ThemeSettingsCoverageThemes.data(theme).write(to: url)
        return url
    }

    @discardableResult
    func addUser(_ theme: Theme) throws -> URL {
        try FileManager.default.createDirectory(at: themesURL, withIntermediateDirectories: true)
        let url = themesURL.appending(path: "\(theme.name).cetheme")
        try ThemeSettingsCoverageThemes.data(theme).write(to: url)
        return url
    }

    @discardableResult
    func addOutside(_ theme: Theme) throws -> URL {
        let url = outsideURL.appending(path: "\(theme.name).cetheme")
        try ThemeSettingsCoverageThemes.data(theme).write(to: url)
        return url
    }

    func makeModel(filePanels: any FilePanelPresenting = FakeFilePanels()) -> ThemeModel {
        ThemeModel(baseURL: baseURL, bundledThemesURL: bundledURL, preferencesStore: settings, filePanels: filePanels)
    }

    func makeModel(bundledThemesURL: URL?) -> ThemeModel {
        ThemeModel(
            baseURL: baseURL,
            bundledThemesURL: bundledThemesURL,
            preferencesStore: settings,
            filePanels: FakeFilePanels()
        )
    }

    func makeModel(appearance name: NSAppearance.Name) throws -> ThemeModel {
        let appearance = try #require(NSAppearance(named: name))
        var model: ThemeModel?
        appearance.performAsCurrentDrawingAppearance {
            model = makeModel()
        }
        return try #require(model)
    }

    func seededModel(filePanels: any FilePanelPresenting = FakeFilePanels()) throws -> ThemeModel {
        try addBundled(ThemeSettingsCoverageThemes.make(name: "bundled-dark", displayName: "Bundled Dark"))
        try addBundled(
            ThemeSettingsCoverageThemes.make(name: "bundled-light", displayName: "Bundled Light", appearance: .light)
        )
        try addUser(ThemeSettingsCoverageThemes.make(name: "mine", displayName: "Mine"))
        settings.preferences.theme.selectedDarkTheme = "mine"
        settings.preferences.theme.selectedLightTheme = "bundled-light"
        settings.preferences.theme.selectedTheme = "mine"
        return makeModel(filePanels: filePanels)
    }
}

@MainActor
func themeSettingsCoverageTheme(_ model: ThemeModel, named name: String) throws -> Theme {
    try #require(model.themes.first { $0.name == name })
}
