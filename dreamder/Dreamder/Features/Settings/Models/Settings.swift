//
//  Settings.swift
//  DreamderModules/Settings
//
//  Created by Lukas Pistrol on 01.04.22.
//

import Foundation
import SwiftUI
import Observation
import Synchronization
import os

nonisolated final class AutosaveFlag: Sendable {
    private let state: Mutex<Bool>

    init(isEnabled: Bool = false) {
        state = Mutex(isEnabled)
    }

    var isEnabled: Bool {
        state.withLock { $0 }
    }

    func set(_ isEnabled: Bool) {
        state.withLock { $0 = isEnabled }
    }
}

nonisolated enum AutosavePreference {
    static let shared = AutosaveFlag()
}

/// The Preferences View Model. Accessible via the singleton "``SettingsModel/shared``".
@Observable
@MainActor
final class Settings {

    /// The publicly available singleton instance of ``SettingsModel``
    static let shared: Settings = .init()

    @ObservationIgnored private var storeTask: Task<Void, Never>?

    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    @ObservationIgnored private var savedPreferences: SettingsData = .init()

    @ObservationIgnored private let clock: any Clock<Duration>

    static let saveDebounce: Duration = .seconds(2)

    private static let logger = Logger(subsystem: "dev.dreamder.Dreamder", category: "Settings")

    private convenience init() {
        self.init(baseURL: Self.defaultBaseURL(), autosaveFlag: Self.processWideAutosaveFlag())
    }

    static func processWideAutosaveFlag(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AutosaveFlag? {
        TestHost.isActive(in: environment) ? nil : AutosavePreference.shared
    }

    init(
        baseURL: URL,
        autosaveFlag: AutosaveFlag? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        fileManager: FileManager = .default
    ) {
        self.baseURL = baseURL
        self.autosaveFlag = autosaveFlag
        self.clock = clock
        self.filemanager = fileManager
        self.preferences = .init()
        self.preferences = loadSettings()
        self.savedPreferences = preferences
        applyAutosavePreference()
        self.storeTask = Task { [weak self] in
            for await _ in Observations({ [weak self] in self?.preferences }) {
                guard !Task.isCancelled, let self else { return }
                self.scheduleSave()
            }
        }
    }

    isolated deinit {
        storeTask?.cancel()
        flushPendingSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self, clock] in
            try? await Task.sleep(for: Self.saveDebounce, clock: clock)
            guard !Task.isCancelled else { return }
            self?.flushPendingSave()
        }
    }

    func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard !isSavingBlocked, preferences != savedPreferences else { return }
        try? savePreferences(preferences)
    }

    private func applyAutosavePreference() {
        autosaveFlag?.set(preferences.general.isAutoSaveOn)
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
    var preferences: SettingsData {
        didSet {
            applyAutosavePreference()
        }
    }

    private let autosaveFlag: AutosaveFlag?

    /// Load and construct ``Settings`` model from
    /// `~/Library/Application Support/Dreamder/settings.json`
    private func loadSettings() -> SettingsData {
        if !filemanager.fileExists(atPath: settingsURL.path) {
            try? filemanager.createDirectory(at: baseURL, withIntermediateDirectories: true)
            return .init()
        }

        do {
            let json = try Data(contentsOf: settingsURL)
            return try JSONDecoder().decode(SettingsData.self, from: json)
        } catch {
            let path = settingsURL.path
            let reason = error.localizedDescription
            Self.logger.error("Cannot load \(path, privacy: .public): \(reason, privacy: .public)")
            preserveUnreadableSettingsFile()
            return .init()
        }
    }

    private func preserveUnreadableSettingsFile() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let preservedName = "\(settingsURL.lastPathComponent).invalid-\(timestamp)-\(UUID().uuidString)"
        let path = settingsURL.path
        do {
            try filemanager.moveItem(at: settingsURL, to: baseURL.appending(path: preservedName))
        } catch {
            let reason = error.localizedDescription
            Self.logger.error("Cannot preserve \(path, privacy: .public), saving off: \(reason, privacy: .public)")
            isSavingBlocked = true
        }
    }

    /// Save``Settings`` model to
    /// `~/Library/Application Support/Dreamder/settings.json`
    private func savePreferences(_ data: SettingsData) throws {
        let encoded = try JSONEncoder().encode(data)
        let json = try JSONSerialization.jsonObject(with: encoded)
        let prettyJSON = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
        try prettyJSON.write(to: settingsURL, options: .atomic)
        savedPreferences = data
    }

    private let filemanager: FileManager

    @ObservationIgnored private var isSavingBlocked = false

    /// The base URL of settings.
    ///
    /// Points to `~/Library/Application Support/Dreamder/` unless the instance was created with a custom location.
    let baseURL: URL

    static func defaultBaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if TestHost.isActive(in: environment) {
            let shard = environment["DREAMDER_SHARD"].map { "-\($0)" } ?? ""
            return fileManager.temporaryDirectory.appending(path: "DreamderTests\(shard)", directoryHint: .isDirectory)
        }
        return fileManager
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
