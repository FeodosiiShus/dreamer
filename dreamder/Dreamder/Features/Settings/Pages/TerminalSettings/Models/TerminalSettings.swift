//
//  TerminalPreferences.swift
//  DreamderModules/Settings
//
//  Created by Nanashi Li on 2022/04/08.
//

import AppKit
import Foundation

extension SettingsData {

    /// The global settings for the terminal emulator
    struct TerminalSettings: Codable, Hashable, SearchableSettingsPage {

        /// The search keys
        var searchKeys: [String] {
            [
                "Shell",
                "Use \"Option\" key as \"Meta\"",
                "Use text editor font",
                "Font",
                "Font Size",
                "Terminal Cursor Style",
                "Blink Cursor"
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// If true terminal will use editor theme.
        var useEditorTheme: Bool = true

        /// If true terminal appearance will always be `dark`. Otherwise it adapts to the system setting.
        var darkAppearance: Bool = false

        /// If true, the terminal treats the `Option` key as the `Meta` key
        var optionAsMeta: Bool = false

        /// The selected shell to use.
        var shell: TerminalShell = .system

        /// The font to use in terminal.
        var font: TerminalFont = .init()

        // The cursor style to use in terminal
        var cursorStyle: TerminalCursorStyle = .block

        // Toggle for blinking cursor or not
        var cursorBlink: Bool = false

        // Use font settings from Text Editing
        var useTextEditorFont: Bool = true

        /// If `true`, use injection scripts for terminal features like automatic tab title.
        var useShellIntegration: Bool = true

        /// If `true`, use a login shell.
        var useLoginShell: Bool = true

        /// Default initializer
        init() {}

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.darkAppearance = container.lenient(.darkAppearance, default: false)
            self.optionAsMeta = container.lenient(.optionAsMeta, default: false)
            self.shell = container.lenient(.shell, default: .system)
            self.font = container.lenient(.font, default: .init())
            self.cursorStyle = container.lenient(.cursorStyle, default: .block)
            self.cursorBlink = container.lenient(.cursorBlink, default: false)
            self.useTextEditorFont = container.lenient(.useTextEditorFont, default: true)
            self.useShellIntegration = container.lenient(.useShellIntegration, default: true)
            self.useLoginShell = container.lenient(.useLoginShell, default: true)
        }
    }

    /// The shell options.
    /// - **bash**: uses the default bash shell
    /// - **zsh**: uses the ZSH shell
    /// - **system**: uses the system default shell (most likely ZSH)
    enum TerminalShell: String, Codable, Hashable {
        case bash
        case zsh
        case system
    }

    enum TerminalCursorStyle: String, Codable, Hashable {
        case block
        case underline
        case bar
    }

    struct TerminalFont: Codable, Hashable {
        /// The font size for the custom font
        var size: Double = 12

        /// The name of the custom font
        var name: String = "SF Mono"

        /// The weight of the custom font
        var weight: NSFont.Weight = .medium

        /// Default initializer
        init() {}

        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.size = container.lenient(.size, default: size)
            self.name = container.lenient(.name, default: name)
            self.weight = container.lenient(.weight, default: weight)
        }

        /// Returns an NSFont representation of the current configuration.
        ///
        /// Returns the custom font, if enabled and able to be instantiated.
        /// Otherwise returns a default system font monospaced.
        var current: NSFont {
            let customFont = NSFont(name: name, size: size)?.withWeight(weight: weight)
            return customFont ?? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
        }
    }
}
