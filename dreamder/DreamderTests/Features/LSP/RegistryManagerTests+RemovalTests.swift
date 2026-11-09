import Foundation
import Testing
@testable import Dreamder

extension RegistryManagerTests {
    @Test
    func updateErrorsAreAlwaysRecordedForThePresentation() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let url = Self.registryURL
            let cause = NSError(domain: "RegistryManagerTests", code: 7)
            let errors: [Error] = [
                RegistryManagerError.installationRunning,
                RegistryManagerError.invalidResponse(statusCode: 418),
                RegistryManagerError.downloadFailed(url: url, error: cause),
                RegistryManagerError.maxRetriesExceeded(url: url, lastError: cause),
                RegistryManagerError.writeFailed(error: cause),
                RegistryManagerError.failedToSaveRegistryCache,
                RegistryManagerError.checksumMissing(file: "registry.json.zip"),
                RegistryManagerError.checksumMismatch(file: "registry.json.zip"),
                cause
            ]

            for error in errors {
                manager.downloadError = nil
                manager.handleUpdateError(error)
                #expect(manager.downloadError?.localizedDescription == error.localizedDescription)
            }
        }
    }

    @Test
    func togglingAnInstalledServerKeepsItsVersion() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1.2.3")
            defer { manager.installedLanguageServers.removeValue(forKey: name) }

            manager.setPackageEnabled(packageName: name, enabled: false)
            let disabled = SettingsData.InstalledLanguageServer(packageName: name, isEnabled: false, version: "1.2.3")
            #expect(manager.installedLanguageServers[name] == disabled)

            manager.setPackageEnabled(packageName: name, enabled: true)
            let enabled = SettingsData.InstalledLanguageServer(packageName: name, isEnabled: true, version: "1.2.3")
            #expect(manager.installedLanguageServers[name] == enabled)
        }
    }

    @Test
    func togglingAnUnknownServerDoesNotRegisterIt() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()

            manager.setPackageEnabled(packageName: name, enabled: true)

            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func removingAServerWithoutFilesOnlyForgetsIt() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1")
            defer { manager.installedLanguageServers.removeValue(forKey: name) }

            try await manager.removeLanguageServer(packageName: name)

            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func removingAServerDeletesItsDirectoryAndRegistration() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let name = uniqueName()
            let packageDirectory = path.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            try Data("binary".utf8).write(to: packageDirectory.appending(path: "server"))
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1")
            defer { manager.installedLanguageServers.removeValue(forKey: name) }

            try await manager.removeLanguageServer(packageName: name)

            #expect(FileManager.default.fileExists(atPath: packageDirectory.path) == false)
            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test(arguments: [
        "../victim",
        "..%2Fvictim",
        "%2E%2E%2Fvictim",
        "a;rm -rf ~",
        "-rf",
        "..",
        ".",
        "",
        "a/b",
        "a\u{0}b",
        "$(touch x)",
        "`touch x`",
        "a b"
    ])
    func removingAHostilePackageNameIsRejectedAndTouchesNothing(name: String) async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let victim = directory.appending(path: "victim", directoryHint: .isDirectory)
            let bystander = path.appending(path: "bystander", directoryHint: .isDirectory)
            for folder in [victim, bystander] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data("keep".utf8).write(to: folder.appending(path: "file"))
            }
            let keys = Set([name, name.removingPercentEncoding ?? name])
            for key in keys {
                manager.installedLanguageServers[key] = .init(packageName: key, isEnabled: true, version: "1")
            }
            defer {
                for key in keys {
                    manager.installedLanguageServers.removeValue(forKey: key)
                }
            }
            let before = try snapshot(of: directory)

            var failure: Error?
            do {
                try await manager.removeLanguageServer(packageName: name)
            } catch {
                failure = error
            }

            #expect(errorKind(failure) == "PackageManagerError.unsafeValue")
            #expect(try snapshot(of: directory) == before)
            #expect(FileManager.default.fileExists(atPath: victim.appending(path: "file").path))
            #expect(FileManager.default.fileExists(atPath: bystander.appending(path: "file").path))
            for key in keys {
                #expect(manager.installedLanguageServers[key] != nil)
            }
        }
    }

    @Test
    func removingASafeNameDeletesOnlyItsOwnDirectory() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let name = uniqueName()
            let neighbour = "\(name)-neighbour"
            for folder in [name, neighbour] {
                let url = path.appending(path: folder, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("binary".utf8).write(to: url.appending(path: "server"))
                manager.installedLanguageServers[folder] = .init(packageName: folder, isEnabled: true, version: "1")
            }
            defer {
                manager.installedLanguageServers.removeValue(forKey: name)
                manager.installedLanguageServers.removeValue(forKey: neighbour)
            }

            try await manager.removeLanguageServer(packageName: name)

            #expect(FileManager.default.fileExists(atPath: path.appending(path: name).path) == false)
            let neighbourServer = path.appending(path: neighbour).appending(path: "server")
            #expect(FileManager.default.fileExists(atPath: neighbourServer.path))
            #expect(manager.installedLanguageServers[name] == nil)
            #expect(manager.installedLanguageServers[neighbour] != nil)
        }
    }

    @Test
    func removingAPercentEncodedSafeNameDecodesItFirst() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let decodedName = "tool+\(uniqueName())"
            let packageDirectory = path.appending(path: decodedName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            manager.installedLanguageServers[decodedName] = .init(
                packageName: decodedName,
                isEnabled: true,
                version: "1"
            )
            defer { manager.installedLanguageServers.removeValue(forKey: decodedName) }

            try await manager.removeLanguageServer(packageName: decodedName.replacingOccurrences(of: "+", with: "%2B"))

            #expect(FileManager.default.fileExists(atPath: packageDirectory.path(percentEncoded: false)) == false)
            #expect(manager.installedLanguageServers[decodedName] == nil)
        }
    }

    @Test
    func failedRemovalKeepsTheServerRegistered() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let name = uniqueName()
            let packageDirectory = path.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1")
            let pathOnDisk = path.path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: pathOnDisk)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pathOnDisk)
                manager.installedLanguageServers.removeValue(forKey: name)
            }

            var failure: Error?
            do {
                try await manager.removeLanguageServer(packageName: name)
            } catch {
                failure = error
            }

            #expect(failure != nil)
            #expect(FileManager.default.fileExists(atPath: packageDirectory.path))
            #expect(manager.installedLanguageServers[name] != nil)
        }
    }

    @Test
    func removingANameWithAnInvalidPercentEscapeRejectsItAsWritten() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = "tool%zz"

            var failure: Error?
            do {
                try await manager.removeLanguageServer(packageName: name)
            } catch {
                failure = error
            }

            guard case .unsafeValue(let value) = failure as? PackageManagerError else {
                Issue.record("expected an unsafe value rejection, got \(String(describing: failure))")
                return
            }
            #expect(value == name)
        }
    }
}
