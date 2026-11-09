//
//  Settings.swift
//  DreamderModules/Settings
//
//  Created by Lukas Pistrol on 01.04.22.
//

import SwiftUI
import Foundation

/// # Settings
///
/// The model structure of settings for `Dreamder`
///
/// A `JSON` representation is persisted in `~/Library/Application Support/Dreamder/preference.json`.
/// - Attention: Don't use `UserDefaults` for persisting user accessible settings.
///  If a further setting is needed, extend the struct like ``GeneralSettings``,
///  ``ThemeSettings``,  or ``TerminalSettings`` does.
///
/// - Note: Also make sure to implement the ``init(from:)`` initializer, decoding
///  all properties with
///  [`decodeIfPresent`](https://developer.apple.com/documentation/swift/keyeddecodingcontainer/2921389-decodeifpresent)
///  and providing a default value. Otherwise all settings get overridden.
struct SettingsData: Codable, Hashable {

    /// The general global settings
    var general: GeneralSettings = .init()

    /// The global settings for themes
    var navigation: NavigationSettings = .init()

    /// The global settings for themes
    var theme: ThemeSettings = .init()

    /// The global settings for text editing
    var textEditing: TextEditingSettings = .init()

    /// The global settings for the terminal emulator
    var terminal: TerminalSettings = .init()

    /// The global settings for source control
    var sourceControl: SourceControlSettings = .init()

    /// Search Settings
    var search: SearchSettings = .init()

    /// Language Server Settings
    var languageServers: LanguageServerSettings = .init()

    /// Developer settings for Dreamder developers
    var developerSettings: DeveloperSettings = .init()

    var markdownPreview: MarkdownPreviewSettings = .init()

    /// Default initializer
    init() {}

    /// Explicit decoder init for setting default values when key is not present in `JSON`
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.general = container.lenient(.general, default: .init())
        self.navigation = container.lenient(.navigation, default: .init())
        self.theme = container.lenient(.theme, default: .init())
        self.terminal = container.lenient(.terminal, default: .init())
        self.textEditing = container.lenient(.textEditing, default: .init())
        self.search = container.lenient(.search, default: .init())
        self.sourceControl = container.lenient(.sourceControl, default: .init())
        self.languageServers = container.lenient(.languageServers, default: .init())
        self.developerSettings = container.lenient(.developerSettings, default: .init())
        self.markdownPreview = container.lenient(.markdownPreview, default: .init())
    }

    // swiftlint:disable cyclomatic_complexity
    func propertiesOf(_ name: SettingsPage.Name) -> [SettingsPage] {
        var settings: [SettingsPage] = []

        switch name {
        case .general:
            general.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .appearance:
            AppearanceSettingsView.searchKeys.forEach {
                settings.append(.init(name, isSetting: true, settingName: $0))
            }
        case .navigation:
            navigation.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .theme:
            theme.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .textEditing:
            textEditing.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .terminal:
            terminal.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .search:
            search.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .sourceControl:
            sourceControl.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .location:
            LocationsSettings().searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .languageServers:
            LanguageServerSettings().searchKeys.forEach {
                settings.append(.init(name, isSetting: true, settingName: $0))
            }
        case .developer:
            developerSettings.searchKeys.forEach { settings.append(.init(name, isSetting: true, settingName: $0)) }
        case .behavior: return [.init(name, settingName: "Error")]
        case .components: return [.init(name, settingName: "Error")]
        case .keybindings: return [.init(name, settingName: "Error")]
        case .advanced: return [.init(name, settingName: "Error")]
        }

        return settings
    }
    // swiftlint:enable cyclomatic_complexity
}
