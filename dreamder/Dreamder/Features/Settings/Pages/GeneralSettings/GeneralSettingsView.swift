//
//  GeneralSettingsView.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/1/23.
//

import SwiftUI

/// A view that implements the `General` settings page
struct GeneralSettingsView: View {
    private let inputWidth: Double = 160
    private let textEditorWidth: Double = 220
    private let textEditorHeight: Double = 30

    @FocusState private var focusedField: UUID?

    @AppSettings(\.general)
    var settings

    @State private var openInDreamder: Bool = true

    init() {
        guard let defaults = UserDefaults.init(
            suiteName: "dev.dreamder.Dreamder.shared"
        ) else {
            print("Failed to get/init shared defaults")
            return
        }

        self.openInDreamder = defaults.bool(forKey: "enableOpenInCE")
    }

    var body: some View {
        SettingsForm {
            Section {
                appearance
                fileIconStyle
                dimEditorsWithoutFocus
            }
            Section {
                autoSave
                revealFileOnFocusChangeToggle
                reopenBehavior
                afterWindowsCloseBehaviour
                fileExtensions
            }
            Section {
                findNavigatorDetail
            }
            Section {
                openInDreamderToggle
            }
        }
    }
}

/// The extension of the view with all the preferences
private extension GeneralSettingsView {
    var appearance: some View {
        Picker("Appearance", selection: $settings.appAppearance) {
            Text("System")
                .tag(SettingsData.Appearances.system)
            Divider()
            Text("Light")
                .tag(SettingsData.Appearances.light)
            Text("Dark")
                .tag(SettingsData.Appearances.dark)
        }
        .onChange(of: settings.appAppearance) { _, tag in
            tag.applyAppearance()
        }
    }

    var dimEditorsWithoutFocus: some View {
        Toggle("Dim editors without focus", isOn: $settings.dimEditorsWithoutFocus)
    }

    var fileExtensions: some View {
        Group {
            Picker("File Extensions", selection: $settings.fileExtensionsVisibility) {
                Text("Hide all")
                    .tag(SettingsData.FileExtensionsVisibility.hideAll)
                Text("Show all")
                    .tag(SettingsData.FileExtensionsVisibility.showAll)
                Divider()
                Text("Show only")
                    .tag(SettingsData.FileExtensionsVisibility.showOnly)
                Text("Hide only")
                    .tag(SettingsData.FileExtensionsVisibility.hideOnly)
            }
            if case .showOnly = settings.fileExtensionsVisibility {
                TextField("", text: $settings.shownFileExtensions.string, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(1...3)
            }
            if case .hideOnly = settings.fileExtensionsVisibility {
                TextField("", text: $settings.hiddenFileExtensions.string, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(1...3)
            }
        }
    }

    var fileIconStyle: some View {
        Picker("File Icon Style", selection: $settings.fileIconStyle) {
            Text("Color")
                .tag(SettingsData.FileIconStyle.color)
            Text("Monochrome")
                .tag(SettingsData.FileIconStyle.monochrome)
        }
        .pickerStyle(.radioGroup)
    }

    var reopenBehavior: some View {
        Picker("Reopen Behavior", selection: $settings.reopenBehavior) {
            Text("Welcome Screen")
                .tag(SettingsData.ReopenBehavior.welcome)
            Divider()
            Text("Open Panel")
                .tag(SettingsData.ReopenBehavior.openPanel)
            Text("New Document")
                .tag(SettingsData.ReopenBehavior.newDocument)
        }
    }

    var afterWindowsCloseBehaviour: some View {
        Picker(
            "After the last window is closed",
            selection: $settings.reopenWindowAfterClose
        ) {
            Text("Do nothing")
                .tag(SettingsData.ReopenWindowBehavior.doNothing)
            Divider()
            Text("Show Welcome Window")
                .tag(SettingsData.ReopenWindowBehavior.showWelcomeWindow)
            Text("Quit")
                .tag(SettingsData.ReopenWindowBehavior.quit)
        }
    }

    var findNavigatorDetail: some View {
        Picker("Find Navigator Detail", selection: $settings.findNavigatorDetail) {
            ForEach(SettingsData.NavigatorDetail.allCases, id: \.self) { tag in
                Text(tag.label).tag(tag)
            }
        }
    }

    var autoSave: some View {
        Toggle("Automatically save changes to disk", isOn: $settings.isAutoSaveOn)
    }

    var openInDreamderToggle: some View {
        Toggle("Show “Open With Dreamder” option in Finder", isOn: $openInDreamder)
            .onChange(of: openInDreamder) { _, newValue in
                guard let defaults = UserDefaults.init(
                    suiteName: "dev.dreamder.Dreamder.shared"
                ) else {
                    print("Failed to get/init shared defaults")
                    return
                }

                defaults.set(newValue, forKey: "enableOpenInCE")
            }
    }

    var revealFileOnFocusChangeToggle: some View {
        Toggle("Automatically reveal in project navigator", isOn: $settings.revealFileOnFocusChange)
    }
}
