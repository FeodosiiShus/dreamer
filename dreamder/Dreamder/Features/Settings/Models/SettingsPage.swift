//
//  SettingsPage.swift
//  Dreamder
//
//  Created by Raymond Vleeshouwer on 30/03/23.
//

import Foundation
import SwiftUI

/// A struct for a settings page
struct SettingsPage: Hashable, Equatable, Identifiable {
    /// A struct for a sidebar icon, with a base color and SF Symbol
    enum IconResource: Equatable, Hashable {
        case system(_ name: String)
        case symbol(_ name: String)
        case asset(_ name: String)
    }

    /// An enum of all the settings pages
    nonisolated enum Name: String, CaseIterable, Sendable {
        case general = "General"
        case appearance = "Appearance"
        case behavior = "Behaviors"
        case navigation = "Navigation"
        case theme = "Theme"
        case textEditing = "Text Editing"
        case terminal = "Terminal"
        case search = "Search"
        case keybindings = "Key Bindings"
        case sourceControl = "Source Control"
        case components = "Components"
        case location = "Locations"
        case advanced = "Advanced"
        case languageServers = "Language Servers"
        case developer = "Developer"
    }

    let id: UUID = UUID()

    let name: Name
    let baseColor: Color?
    let isSetting: Bool
    let settingName: String
    var nameString: LocalizedStringKey {
        LocalizedStringKey(name.rawValue)
    }
    let icon: IconResource?

    /// Default initializer
    init(
        _ name: Name,
        baseColor: Color? = nil,
        icon: IconResource? = nil,
        isSetting: Bool = false,
        settingName: String = ""
    ) {
        self.name = name
        self.baseColor = baseColor
        self.icon = icon
        self.isSetting = isSetting
        self.settingName = settingName
    }
}

extension SettingsPage {
    /// The IntelliJ settings tree groups, in the order they appear in the navigation pane.
    nonisolated enum Category: String, CaseIterable, Identifiable, Hashable, Sendable {
        case appearanceAndBehavior = "Appearance & Behavior"
        case keymap = "Keymap"
        case editor = "Editor"
        case versionControl = "Version Control"
        case languagesAndFrameworks = "Languages & Frameworks"
        case tools = "Tools"

        var id: String { rawValue }

        /// The pages of this group, in display order.
        var pages: [Name] {
            switch self {
            case .appearanceAndBehavior: [.appearance, .general]
            case .keymap: [.keybindings]
            case .editor: [.textEditing, .theme, .navigation, .search]
            case .versionControl: [.sourceControl]
            case .languagesAndFrameworks: [.languageServers]
            case .tools: [.terminal, .location, .developer]
            }
        }
    }
}

nonisolated extension SettingsPage.Name {
    /// The tree group this page belongs to, or `nil` for pages without a settings view.
    var category: SettingsPage.Category? {
        switch self {
        case .general, .appearance: .appearanceAndBehavior
        case .keybindings: .keymap
        case .textEditing, .theme, .navigation, .search: .editor
        case .sourceControl: .versionControl
        case .languageServers: .languagesAndFrameworks
        case .terminal, .location, .developer: .tools
        case .behavior, .components, .advanced: nil
        }
    }
}
