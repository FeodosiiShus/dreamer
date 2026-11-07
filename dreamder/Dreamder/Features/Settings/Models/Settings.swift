//
//  Settings.swift
//  DreamderModules/Settings
//
//  Created by Lukas Pistrol on 01.04.22.
//

import Foundation
import SwiftUI
import Observation

/// The Preferences View Model. Accessible via the singleton "``SettingsModel/shared``".
@Observable
@MainActor
final class Settings {

    /// The publicly available singleton instance of ``SettingsModel``
    static let shared: Settings = .init()

    @ObservationIgnored private var storeTask: Task<Void, Never>?

    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    private convenience init() {
        self.init(baseURL: Self.defaultBaseURL)
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.preferences = .init()
        self.preferences = loadSettings()

        self.storeTask = Task { [weak self] in
            for await data in Observations({ [weak self] in self?.preferences }) {
                guard !Task.isCancelled, let self, let data else { return }
                self.scheduleSave(of: data)
            }
        }
    }

    isolated deinit {
        storeTask?.cancel()
        pendingSave?.cancel()
    }

    private func scheduleSave(of data: SettingsData) {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? self?.savePreferences(data)
        }
    }

    static subscript<T>(_ path: WritableKeyPath<SettingsData, T>, suite: Settings = .shared) -> T {
        get {
            suite.preferences[keyPath: path]
        }
        set {
            suite.preferences[keyPath: path] = newValue
        }
    }

    /// Published instance of the ``Settings`` model.
    ///
    /// Changes are saved automatically.
    var preferences: SettingsData

    /// Load and construct ``Settings`` model from
    /// `~/Library/Application Support/Dreamder/settings.json`
    private func loadSettings() -> SettingsData {
        if !filemanager.fileExists(atPath: settingsURL.path) {
            try? filemanager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            return .init()
        }

        guard let json = try? Data(contentsOf: settingsURL),
              let prefs = try? JSONDecoder().decode(SettingsData.self, from: json)
        else {
            return .init()
        }
        return prefs
    }

    /// Save``Settings`` model to
    /// `~/Library/Application Support/Dreamder/settings.json`
    private func savePreferences(_ data: SettingsData) throws {
        let data = try JSONEncoder().encode(data)
        let json = try JSONSerialization.jsonObject(with: data)
        let prettyJSON = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try prettyJSON.write(to: settingsURL, options: .atomic)
    }

    /// Default instance of the `FileManager`
    private let filemanager = FileManager.default

    /// The base URL of settings.
    ///
    /// Points to `~/Library/Application Support/Dreamder/` unless the instance was created with a custom location.
    let baseURL: URL

    private static var defaultBaseURL: URL {
        let filemanager = FileManager.default
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return filemanager.temporaryDirectory.appending(path: "DreamderTests", directoryHint: .isDirectory)
        }
        return filemanager
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Dreamder", directoryHint: .isDirectory)
    }

    /// The URL of the `settings.json` settings file.
    ///
    /// Points to `~/Library/Application Support/Dreamder/settings.json`
    private var settingsURL: URL {
        baseURL
            .appending(path: "settings")
            .appendingPathExtension("json")
    }
}
