//
//  GeneralSettings.swift
//  DreamderModules/Settings
//
//  Created by Nanashi Li on 2022/04/08.
//

import SwiftUI

extension SettingsData {

    /// The general global setting
    struct GeneralSettings: Codable, Hashable, SearchableSettingsPage {

        /// The appearance of the app
        var appAppearance: Appearances = .dark

        /// The search keys
        var searchKeys: [String] {
            [
                "Appearance",
                "File Icon Style",
                "Dim editors without focus",
                "Automatically save change to disk",
                "Automatically reveal in project navigator",
                "Reopen Behavior",
                "After the last window is closed",
                "File Extensions",
                "Find Navigator Detail",
                "Show “Open With Dreamder“ option in Finder",
                "Check for updates",
                "Automatically check for app updates",
                "Include pre-release versions"
            ]
            .map { NSLocalizedString($0, comment: "") }
        }

        /// Dims editors without focus
        var dimEditorsWithoutFocus: Bool = false

        /// The show file extensions behavior of the app
        var fileExtensionsVisibility: FileExtensionsVisibility = .showAll

        /// The file extensions collection to display
        var shownFileExtensions: FileExtensions = .default

        /// The file extensions collection to hide
        var hiddenFileExtensions: FileExtensions = .default

        /// The style for file icons
        var fileIconStyle: FileIconStyle = .color

        /// The reopen behavior of the app
        var reopenBehavior: ReopenBehavior = .welcome

        /// Decides what the app does after a workspace is closed
        var reopenWindowAfterClose: ReopenWindowBehavior = .doNothing

        /// The Find Navigator Detail line limit
        var findNavigatorDetail: NavigatorDetail = .upTo3

        /// The reveal file in navigator when focus changes behavior of the app.
        var revealFileOnFocusChange: Bool = false

        /// Auto save behavior toggle
        var isAutoSaveOn: Bool = true

        /// Default initializer
        init() {}

        // swiftlint:disable function_body_length
        /// Explicit decoder init for setting default values when key is not present in `JSON`
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.appAppearance = container.lenient(.appAppearance, default: .dark)
            self.dimEditorsWithoutFocus = container.lenient(.dimEditorsWithoutFocus, default: false)
            self.fileExtensionsVisibility = container.lenient(.fileExtensionsVisibility, default: .showAll)
            self.shownFileExtensions = container.lenient(.shownFileExtensions, default: .default)
            self.hiddenFileExtensions = container.lenient(.hiddenFileExtensions, default: .default)
            self.fileIconStyle = container.lenient(.fileIconStyle, default: .color)
            self.reopenBehavior = container.lenient(.reopenBehavior, default: .welcome)
            self.reopenWindowAfterClose = container.lenient(.reopenWindowAfterClose, default: .doNothing)
            self.findNavigatorDetail = container.lenient(.findNavigatorDetail, default: .upTo3)
            self.revealFileOnFocusChange = container.lenient(.revealFileOnFocusChange, default: false)
            self.isAutoSaveOn = container.lenient(.isAutoSaveOn, default: true)
        }
        // swiftlint:enable function_body_length
    }

    /// The appearance of the app
    /// - **system**: uses the system appearance
    /// - **dark**: always uses dark appearance
    /// - **light**: always uses light appearance
    enum Appearances: String, Codable {
        case system
        case light
        case dark

        /// Applies the selected appearance
        func applyAppearance() {
            switch self {
            case .system:
                NSApp.appearance = nil

            case .dark:
                NSApp.appearance = .init(named: .darkAqua)

            case .light:
                NSApp.appearance = .init(named: .aqua)
            }
        }
    }

    /// The style for file extensions visibility
    ///  - **hideAll**: File extensions are hidden
    ///  - **showAll** File extensions are visible
    ///  - **showOnly** Specific file extensions are visible
    ///  - **hideOnly** Specific file extensions are hidden
    enum FileExtensionsVisibility: Codable, Hashable {
        case hideAll
        case showAll
        case showOnly
        case hideOnly
    }

    /// The collection of file extensions used by
    /// ``FileExtensionsVisibility/showOnly`` or  ``FileExtensionsVisibility/hideOnly`` preference
    struct FileExtensions: Codable, Hashable {
        var extensions: [String]

        var string: String {
            get {
                extensions.joined(separator: ", ")
            }
            set {
                extensions = newValue
                    .components(separatedBy: ",")
                    .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .filter({ !$0.isEmpty || string.count < newValue.count })
            }
        }

        static var `default` = FileExtensions(extensions: [
            "c", "cc", "cpp", "h", "hpp", "m", "mm", "gif",
            "icns", "jpeg", "jpg", "png", "tiff", "swift"
        ])
    }
    /// The style for file icons
    /// - **color**: File icons appear in their default colors
    /// - **monochrome**: File icons appear monochromatic
    enum FileIconStyle: String, Codable {
        case color
        case monochrome
    }

    /// The reopen behavior of the app
    /// - **welcome**: On restart the app will show the welcome screen
    /// - **openPanel**: On restart the app will show an open panel
    /// - **newDocument**: On restart a new empty document will be created
    enum ReopenBehavior: String, Codable {
        case welcome
        case openPanel
        case newDocument
    }

    enum ReopenWindowBehavior: String, Codable {
        case showWelcomeWindow
        case doNothing
        case quit
    }

    /// The Navigation Detail behavior of the app
    ///  - Use **rawValue** to set lineLimit
    enum NavigatorDetail: Int, Codable, CaseIterable {
        case upTo1 = 1
        case upTo2 = 2
        case upTo3 = 3
        case upTo4 = 4
        case upTo5 = 5
        case upTo10 = 10
        case upTo30 = 30

        var label: String {
            switch self {
            case .upTo1:
                return "One Line"
            default:
                return "Up to \(self.rawValue) lines"
            }
        }
    }
}
