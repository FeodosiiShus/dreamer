//
//  ThemePreferencesView.swift
//  Dreamder
//
//  Created by Lukas Pistrol on 30.03.22.
//

import SwiftUI

/// A view that implements the `Theme` preference section
struct ThemeSettingsView: View {
    @Environment(\.colorScheme)
    var colorScheme
    @Bindable private var themeModel: ThemeModel
    @AppSettings(\.theme)
    var settings
    @AppSettings(\.terminal.darkAppearance)
    var useDarkTerminalAppearance

    @State private var listView: Bool = false
    @State private var themeSearchQuery: String
    @State private var filteredThemes: [Theme] = []

    init(themeModel: ThemeModel = .shared, initialSearchQuery: String = "") {
        self.themeModel = themeModel
        _themeSearchQuery = State(initialValue: initialSearchQuery)
    }

    var body: some View {
        VStack {
            SettingsForm {
                Section {
                    HStack(spacing: 10) {
                        SearchField("Search", text: $themeSearchQuery)

                        Button(action: themeModel.duplicateSelectedTheme) {
                            Image(systemName: "plus")
                        }
                        .disabled(themeModel.selectedTheme == nil)
                        .help("Create a new Theme")

                        MenuWithButtonStyle(systemImage: "ellipsis", menu: { importExportMenu })
                            .padding(.horizontal, 5)
                            .help("Import or Export Custom Themes")
                    }
                }
                if themeSearchQuery.isEmpty {
                    Section {
                        changeThemeOnSystemAppearance
                        if settings.matchAppearance {
                            alwaysUseDarkTerminalAppearance
                        }
                        useThemeBackground
                    }
                }
                Section {
                    VStack(spacing: 0) {
                        ForEach(filteredThemes) { theme in
                            if let themeIndex = themeModel.themes.firstIndex(of: theme) {
                                Divider().padding(.horizontal, 10)
                                ThemeSettingsThemeRow(
                                    theme: $themeModel.themes[themeIndex],
                                    active: themeModel.getThemeActive(theme),
                                    themeModel: themeModel
                                ).id(theme)
                            }
                        }
                    }
                    .padding(-10)
                } footer: {
                    HStack {
                        Spacer()
                        Button("Import...", action: themeModel.importTheme)
                    }
                    .padding(.top, 10)
                }
                .sheet(isPresented: $themeModel.detailsIsPresented, onDismiss: endAdding) { detailsSheet }
                .onAppear { updateFilteredThemes() }
                .onChange(of: themeSearchQuery) { _, _ in updateFilteredThemes() }
                .onChange(of: themeModel.themes, themesChanged)
                .onChange(of: colorScheme, colorSchemeChanged)
            }
        }
    }

    /// Sorts themes by `colorScheme` and `themeSearchQuery`.
    /// Dark mode themes appear before light themes if in dark mode, and vice versa.
    private func updateFilteredThemes(overrideColorScheme: ColorScheme? = nil) {
        // This check is necessary because, when calling `updateFilteredThemes` from within the
        // `onChange` handler that monitors the `colorScheme`, there are cases where the function
        // is invoked with outdated values of `colorScheme`.
        let isDarkScheme = overrideColorScheme ?? colorScheme == .dark

        let themes: [Theme] = isDarkScheme
        ? (themeModel.darkThemes + themeModel.lightThemes)
        : (themeModel.lightThemes + themeModel.darkThemes)

        Task {
            filteredThemes = themeSearchQuery.isEmpty ? themes : await filterAndSortThemes(themes)
        }
    }

    private func filterAndSortThemes(_ themes: [Theme]) async -> [Theme] {
        return await themes.fuzzySearch(query: themeSearchQuery).map { $1 }
    }

    func applyMatchAppearance(_ value: Bool) {
        themeModel.matchAppearanceChanged(to: value, colorScheme: colorScheme)
    }

    func endAdding() {
        themeModel.scheduleAddingReset()
    }

    func themesChanged(_ oldValue: [Theme], _ newValue: [Theme]) {
        updateFilteredThemes()
    }

    func colorSchemeChanged(_ oldValue: ColorScheme, _ newValue: ColorScheme) {
        updateFilteredThemes(overrideColorScheme: newValue)
    }
}

extension ThemeSettingsView {
    private var useThemeBackground: some View {
        Toggle("Use theme background ", isOn: $settings.useThemeBackground)
    }

    private var alwaysUseDarkTerminalAppearance: some View {
        Toggle("Always use dark terminal appearance", isOn: $useDarkTerminalAppearance)
    }

    private var changeThemeOnSystemAppearance: some View {
        Toggle(
            "Automatically change theme based on system appearance",
            isOn: $settings.matchAppearance
        )
        .onChange(of: settings.matchAppearance) { _, value in applyMatchAppearance(value) }
    }

    var importExportMenu: some View {
        Group {
            Button(action: themeModel.importTheme) {
                Text("Import Theme...")
            }
            Button(action: themeModel.exportAllCustomThemes) {
                Text("Export All Custom Themes...")
            }
            .disabled(themeModel.themes.filter { !$0.isBundled }.isEmpty)
        }
    }

    func detailsBinding(editing theme: Theme, at index: Int) -> Binding<Theme> {
        Binding(
            get: { themeModel.themes[index] },
            set: { themeModel.commitDetails($0, at: index, editing: theme) }
        )
    }

    @ViewBuilder
    var detailsSheet: some View {
        if let theme = themeModel.detailsTheme, let index = themeModel.themes.firstIndex(where: {
            $0.fileURL?.absoluteString == theme.fileURL?.absoluteString
        }) {
            ThemeSettingsThemeDetails(theme: detailsBinding(editing: theme, at: index), themeModel: themeModel)
        }
    }
}
