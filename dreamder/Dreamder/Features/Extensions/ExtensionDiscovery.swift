//
//  ExtensionDiscovery.swift
//  Dreamder
//
//  Created by Wouter Hennen on 31/12/2022.
//

import Foundation
import ExtensionFoundation
import GRDB

/// Discovery of available extension endpoints.
@Observable
final class ExtensionDiscovery {
    /// Shared instance of this class.
    static var shared = ExtensionDiscovery()

    /// Endpoint used by extensions.
    nonisolated static let endPointIdentifier: StaticString = "dreamder.extension"

    private static var dbURL = URL.libraryDirectory
        .appending(path: "Preferences/com.apple.LaunchServices/com.apple.LaunchServices.SettingsStore.sql")

    /// Publishes a list of extension endpoints approved by the user.
    /// These endpoints can be used to create new extension processes with XPC.
    var extensions: [ExtensionInfo] = []

    @ObservationIgnored
    private var discoverTask: Task<Void, Never>?
    @ObservationIgnored
    private var availabilityTask: Task<Void, Never>?

    // Init is private as only 1 instance of this class may (needs to) exist.
    private init() {}

    func start() {
        guard discoverTask == nil else { return }
        discoverTask = discover()
        availabilityTask = availabilityOverview()
    }

    /// Discover all the extensions approved by the user. Updates `extensions` when an extension gets enabled/disabled.
    /// Warning: This function will continue to run and won't return. Therefore, it should be ran in a separate `Task`.
    private func discover() -> Task<Void, Never> {
        Task { [weak self] in
            do {
                let monitor = try await AppExtensionPoint.Monitor(
                    appExtensionPoint: AppExtensionPoint(identifier: Self.endPointIdentifier)
                )

                for await state in Observations({ monitor.state }) {
                    guard !Task.isCancelled && self != nil else { return }
                    await self?.updateExtensions(endpoints: state.identities, shouldRestartExisting: true)
                }
            } catch {
                print("Error while searching for extensions: \(error.localizedDescription)")
            }
        }
    }

    @concurrent
    private static func loadDetails(
        for endpoints: [AppExtensionIdentity]
    ) async -> [(endpoint: AppExtensionIdentity, details: ExtensionInfo.Details)] {
        await withTaskGroup(of: (Int, ExtensionInfo.Details?).self) { group in
            for (index, endpoint) in endpoints.enumerated() {
                group.addTask {
                    (index, try? await ExtensionInfo.loadDetails(for: endpoint))
                }
            }

            var loaded: [(index: Int, details: ExtensionInfo.Details)] = []
            for await (index, details) in group {
                if let details {
                    loaded.append((index, details))
                }
            }
            return loaded
                .sorted { $0.index < $1.index }
                .map { (endpoint: endpoints[$0.index], details: $0.details) }
        }
    }

    private func updateExtensions(endpoints: [AppExtensionIdentity], shouldRestartExisting: Bool = false) async {
        let loaded = await Self.loadDetails(for: endpoints)
        let extensions = loaded.compactMap {
            try? ExtensionInfo(endpoint: $0.endpoint, details: $0.details)
        }

        self.extensions = extensions

        if shouldRestartExisting {
            self.extensions.filter(\.isDebug)
                .forEach {
                    print("Restarting \($0.name)...")
                    $0.restart()
                }
        }
    }

    /// Observes extensions available on the system, and reports if extensions are disabled.
    /// These extensions must be enabled by the user first, before they can be discovered by `discover`.
    /// Warning: This function will continue to run and won't return. Therefore, it should be ran in a separate `Task`.
    private func availabilityOverview() -> Task<Void, Never> {
        Task { [weak self] in
            do {
                let monitor = try await AppExtensionPoint.Monitor(
                    appExtensionPoint: AppExtensionPoint(identifier: Self.endPointIdentifier)
                )

                for await availability in Observations({ monitor.state }) {
                    guard !Task.isCancelled && self != nil else { return }
                    do {
                        if availability.disabledCount > 0 {
                            print("Found \(availability.disabledCount) disabled extensions, trying to activate...")
                            try await self?.activateDisabledExtensions()
                        }

                        if availability.unapprovedCount > 0 {
                            print("Found \(availability.unapprovedCount) unapproved extensions, trying to activate...")

                            let identifiers = [("com.tweety.TestDreamder.AutoActivatedExtension", "2MMGJGVTB4")]
                            try await self?.activateUnapprovedExtensions(with: identifiers)
                        }

                        await self?.updateExtensions(endpoints: monitor.state.identities)
                    } catch {
                        print("Could not auto-activate extensions.")
                    }
                }
            } catch {
                print("Error while observing extension availability: \(error.localizedDescription)")
            }
        }
    }

    nonisolated struct SettingsStoreRecord: Codable, TableRecord, FetchableRecord, PersistableRecord {
        var identifier: String
        var timestamp: String
        var userElection: Int

        nonisolated static let databaseTableName: String = "Election"
    }

    private func activateDisabledExtensions() async throws {
        let dbQueue = try DatabaseQueue(path: Self.dbURL.path())

        return try await dbQueue.write {
            try SettingsStoreRecord
                .filter(Column("identifier").like("%\(Self.endPointIdentifier)%"))
                .filter(Column("userElection") == 2)
                .updateAll($0, Column("userElection") -= 1)
        }
    }

    private func activateUnapprovedExtensions(with identifiers: [(bundleID: String, devID: String)]) async throws {
        let dbQueue = try DatabaseQueue(path: Self.dbURL.path())
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        return try await dbQueue.write { table in
            try identifiers.map { identifier in
                SettingsStoreRecord(
                    // swiftlint:disable:next line_length
                    identifier: "\(bundleIdentifier)::\(Self.endPointIdentifier):\(identifier.bundleID):\(identifier.devID)",
                    timestamp: String(Date.now.description.dropLast(6)),
                    userElection: 1
                )
            }.forEach {
                try $0.save(table)
            }
        }
    }
}
