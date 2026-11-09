//
//  ThemeModel.swift
//  DreamderModules/Settings
//
//  Created by Lukas Pistrol on 31.03.22.
//

import SwiftUI
import UniformTypeIdentifiers
import os

/// The Theme View Model. Accessible via the singleton "``ThemeModel/shared``".
@Observable
final class ThemeModel {
    static let shared: ThemeModel = .init()

    @ObservationIgnored
    @AppSettings(\.theme)
    var settings

    /// Default instance of the `FileManager`
    let filemanager = FileManager.default

    static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "ThemeModel")

    static var themeFileTypes: [UTType] {
        [UTType(filenameExtension: "cetheme")].compactMap(\.self)
    }

    private let baseURL: URL

    let bundledThemesURL: URL?

    @ObservationIgnored
    let preferencesStore: Settings

    static var defaultBaseURL: URL {
        Settings.defaultBaseURL()
    }

    static var defaultBundledThemesURL: URL? {
        Bundle.main.resourceURL?.appending(path: "DefaultThemes", directoryHint: .isDirectory)
    }

    /// The URL of the `Themes` folder
    internal var themesURL: URL {
        baseURL.appending(path: "Themes", directoryHint: .isDirectory)
    }

    /// The URL of the `Extensions` folder
    internal var extensionsURL: URL {
        baseURL.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    /// The URL of the `settings.json` file
    internal var settingsURL: URL {
        baseURL.appending(path: "settings.json", directoryHint: .isDirectory)
    }

    /// System color scheme
    var colorScheme: ColorScheme = .light

    /// Selected 'light' theme
    /// Used for auto-switching theme to match macOS system appearance
    var selectedLightTheme: Theme? {
        didSet {
            Task {
                preferencesStore.preferences.theme.selectedLightTheme = selectedLightTheme?.name ?? "Broken"
            }
        }
    }

    /// Selected 'dark' theme
    /// Used for auto-switching theme to match macOS system appearance
    var selectedDarkTheme: Theme? {
        didSet {
            Task {
                preferencesStore.preferences.theme.selectedDarkTheme = selectedDarkTheme?.name ?? "Broken"
            }
        }
    }

    var detailsIsPresented: Bool = false

    var isAdding: Bool = false

    var detailsTheme: Theme?

    /// An array of loaded ``Theme``.
    var themes: [Theme] = []

    /// The currently selected ``Theme``.
    var selectedTheme: Theme? {
        didSet {
            Task {
                preferencesStore.preferences.theme.selectedTheme = selectedTheme?.name
            }
        }
    }

    var previousTheme: Theme?

    /// Only themes where ``Theme/appearance`` == ``Theme/ThemeType/dark``
    var darkThemes: [Theme] {
        themes.filter { $0.appearance == .dark }
    }

    /// Only themes where ``Theme/appearance`` == ``Theme/ThemeType/light``
    var lightThemes: [Theme] {
        themes.filter { $0.appearance == .light }
    }

    @ObservationIgnored
    let filePanels: any FilePanelPresenting

    init(
        baseURL: URL = ThemeModel.defaultBaseURL,
        bundledThemesURL: URL? = ThemeModel.defaultBundledThemesURL,
        preferencesStore: Settings = .shared,
        filePanels: any FilePanelPresenting = SystemFilePanels()
    ) {
        self.baseURL = baseURL
        self.bundledThemesURL = bundledThemesURL
        self.preferencesStore = preferencesStore
        self.filePanels = filePanels
        do {
            try loadThemes()
        } catch {
            Self.logger.error("Failed to load themes: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// This function stores  'dark' and 'light' themes into `ThemePreferences` if user happens to select a theme
    func updateAppearanceTheme() {
        if self.selectedTheme?.appearance == .dark {
            self.selectedDarkTheme = self.selectedTheme
        } else if self.selectedTheme?.appearance == .light {
            self.selectedLightTheme = self.selectedTheme
        }
    }

    func cancelDetails(_ theme: Theme) {
        if let index = themes.firstIndex(where: { $0.fileURL == theme.fileURL }),
        let detailsTheme = self.detailsTheme {
            self.themes[index] = detailsTheme
            self.save(self.themes[index])
        }
    }

    func getThemeActive(_ theme: Theme) -> Bool {
        return selectedTheme == theme
    }

    /// Activates the current theme, setting ``selectedTheme`` and ``selectedLightTheme``/``selectedDarkTheme`` as
    /// necessary.
    /// - Parameter theme: The theme to activate.
    func activateTheme(_ theme: Theme) {
        selectedTheme = theme
        if colorScheme == .light {
            selectedLightTheme = theme
        }
        if colorScheme == .dark {
            selectedDarkTheme = theme
        }
    }

    func exportTheme(_ theme: Theme) {
        guard let themeFileURL = theme.fileURL else {
            Self.logger.error("Theme file URL not found.")
            return
        }

        let request = SavePanelRequest(
            prompt: "Export",
            nameFieldStringValue: theme.displayName,
            allowedContentTypes: Self.themeFileTypes,
            canCreateDirectories: true
        )
        guard let destinationURL = filePanels.chooseSaveLocation(request) else { return }
        do {
            try FileManager.default.copyItem(at: themeFileURL, to: destinationURL)
            Self.logger.info("Theme exported successfully to \(destinationURL.path, privacy: .public)")
        } catch {
            Self.logger.error("Failed to export theme: \(error.localizedDescription, privacy: .public)")
        }
    }

    func exportAllCustomThemes() {
        let request = OpenPanelRequest(
            prompt: "Export",
            canChooseFiles: false,
            canChooseDirectories: true
        )
        guard let exportDirectory = filePanels.chooseFiles(request).first else { return }
        let customThemes = themes.filter { !$0.isBundled }

        for theme in customThemes {
            guard let sourceURL = theme.fileURL else { continue }

            let destinationURL = exportDirectory.appending(path: "\(theme.displayName).cetheme")

            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                Self.logger.info("Exported \(theme.displayName, privacy: .public) to \(destinationURL.path, privacy: .public)")
            } catch {
                Self.logger.error("Failed to export \(theme.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func duplicateSelectedTheme() {
        if let selectedTheme, let fileURL = selectedTheme.fileURL {
            duplicate(fileURL)
        }
    }

    func matchAppearanceChanged(to matchAppearance: Bool, colorScheme: ColorScheme) {
        if matchAppearance {
            selectedTheme = colorScheme == .dark ? selectedDarkTheme : selectedLightTheme
        } else {
            selectedTheme = themes.first { $0.name == preferencesStore.preferences.theme.selectedTheme }
        }
    }

    func showDetails(of theme: Theme) {
        detailsTheme = theme
        detailsIsPresented = true
    }

    func commitDetails(_ newValue: Theme, at index: Int, editing theme: Theme) {
        guard detailsIsPresented else { return }
        themes[index] = newValue
        save(newValue)
        if preferencesStore.preferences.theme.selectedTheme == theme.name {
            activateTheme(newValue)
        }
    }

    func scheduleAddingReset(after delay: TimeInterval = 1.0) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.isAdding = false
        }
    }

    func beginDuplicating(_ theme: Theme) -> Theme? {
        guard let fileURL = theme.fileURL else { return nil }
        duplicate(fileURL)
        return theme
    }

    func finishDetails(_ theme: Theme) {
        if !theme.isBundled {
            rename(to: theme.displayName, theme: theme)
        }
    }

    func cancelDetailsEditing(_ theme: Theme, duplicatingTheme: Theme?, deleteDelay: TimeInterval = 1.0) -> Bool {
        if isAdding {
            if let previousTheme {
                activateTheme(previousTheme)
            }
            if let duplicatingTheme {
                detailsTheme = duplicatingTheme
                delete(theme)
            } else {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(deleteDelay))
                    self?.delete(theme)
                }
            }
        } else {
            cancelDetails(theme)
        }

        guard duplicatingTheme != nil else { return true }
        isAdding = false
        return false
    }
}
