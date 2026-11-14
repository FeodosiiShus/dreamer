//
//  SearchSettingsModel.swift
//  Dreamder
//
//  Created by Esteban on 12/10/23.
//

import SwiftUI

/// The Search Settings View Model. Accessible via the singleton "``SearchSettings/shared``".
@Observable
final class SearchSettingsModel {
    private let persist: @MainActor ([GlobPattern]) -> Void

    init(patterns: [GlobPattern], persist: @escaping @MainActor ([GlobPattern]) -> Void) {
        self.persist = persist
        self.ignoreGlobPatterns = patterns
    }

    convenience init(settings: Settings) {
        self.init(patterns: settings.preferences.search.ignoreGlobPatterns) {
            settings.preferences.search.ignoreGlobPatterns = $0
        }
    }

    static let shared = SearchSettingsModel(settings: .shared)

    private var baseURL: URL {
        Settings.defaultBaseURL()
    }

    /// The URL of the `search` folder
    internal var searchURL: URL {
        baseURL.appending(path: "search", directoryHint: .isDirectory)
    }

    /// The URL of the `Extensions` folder
    internal var extensionsURL: URL {
        baseURL.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    /// The URL of the `settings.json` file
    internal var settingsURL: URL {
        baseURL.appending(path: "settings.json", directoryHint: .isDirectory)
    }

    /// Selected patterns
    var selection: Set<UUID> = []

    /// Stores the new values from the Search Settings Model into the settings.json whenever
    /// `ignoreGlobPatterns` is updated
    var ignoreGlobPatterns: [GlobPattern] {
        didSet {
            Task {
                persist(ignoreGlobPatterns)
            }
        }
    }

    func getPattern(for id: UUID) -> GlobPattern? {
        return ignoreGlobPatterns.first(where: { $0.id == id })
    }

    func addPattern() {
        ignoreGlobPatterns.append(GlobPattern(value: ""))
    }

    func removePatterns(_ selection: Set<UUID>? = nil) {
        let patternsToRemove = selection?.compactMap { getPattern(for: $0) } ?? []
        ignoreGlobPatterns.removeAll { patternsToRemove.contains($0) }
        self.selection.removeAll()
    }
}
