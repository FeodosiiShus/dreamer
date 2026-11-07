//
//  CEWorkspaceSettingsManager.swift
//  Dreamder
//
//  Created by Axel Martinez on 27/3/24.
//

import SwiftUI
import Observation

/// The Dreamder workspace settings model.
@Observable
final class CEWorkspaceSettings {
    var settings: CEWorkspaceSettingsData = .init()

    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    private let fileManager = FileManager.default

    private(set) var folderURL: URL

    var settingsURL: URL {
        folderURL.appending(path: "settings").appendingPathExtension("json")
    }

    init(workspaceURL: URL) {
        folderURL = workspaceURL.appending(path: ".dreamder", directoryHint: .isDirectory)
        loadSettings()
        startAutosave()
    }

    private func startAutosave() {
        observationTask = Task { [weak self] in
            let changes = Observations { [weak self] in
                self.map { ObjectIdentifier($0.settings) }
            }
            for await _ in changes {
                guard let self else { return }
                self.scheduleSave()
            }
        }
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            try? self?.savePreferences()
        }
    }

    func cleanUp() {
        observationTask?.cancel()
        observationTask = nil
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
    }

    isolated deinit {
        cleanUp()
    }

    /// Load and construct ``CEWorkspaceSettings`` model from `.dreamder/settings.json`
    private func loadSettings() {
        guard fileManager.fileExists(atPath: settingsURL.path),
              let json = try? Data(contentsOf: settingsURL),
              let prefs = try? JSONDecoder().decode(CEWorkspaceSettingsData.self, from: json)
        else { return }
        self.settings = prefs
    }

    /// Save``CEWorkspaceSettingsManager`` model to `.dreamder/settings.json`
    func savePreferences() throws {
        // If the user doesn't have any settings to save, don't save them.
        guard !settings.isEmpty() else {
            // Settings is empty, remove the file & directory if it's empty.
            if fileManager.fileExists(atPath: settingsURL.path()) {
                try fileManager.removeItem(at: settingsURL)

                if try fileManager.contentsOfDirectory(atPath: folderURL.path()).isEmpty {
                    try fileManager.removeItem(at: folderURL)
                }
            }
            return
        }

        if !fileManager.fileExists(atPath: folderURL.path()) {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        let data = try JSONEncoder().encode(settings)
        let json = try JSONSerialization.jsonObject(with: data)
        let prettyJSON = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try prettyJSON.write(to: settingsURL, options: .atomic)
    }
}
